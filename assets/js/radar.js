import { loadScript, loadStylesheet } from "./load_external_asset";

/** Radar Web SDK core bundle — https://docs.radar.com/maps/maps */
const RADAR_VERSION = "5.1.0";

/** Maps plugin — registers `Radar.ui`; required from Radar SDK v5+ (core SDK alone has no `Radar.ui`). */
const RADAR_MAPS_VERSION = "1.0.0";

/**
 * Radar serves glyph PBFs at paths like `/fonts/Graphik Regular,Noto Sans Regular/0-255.pbf`.
 * Some Radar API deployments return 500 when commas/spaces are left unencoded in the path.
 * Rewriting only Radar `/fonts/*.pbf` URLs keeps tiles/sprites untouched.
 *
 * @param {string} url
 * @returns {{ url: string }}
 */
function radarGlyphTransformRequest(url) {
    try {
        const u = new URL(url);
        if (!u.hostname.endsWith("api.radar.io")) return { url };
        if (!u.pathname.endsWith(".pbf") || !u.pathname.includes("/fonts/")) return { url };

        const marker = "/fonts/";
        const start = u.pathname.indexOf(marker);
        if (start === -1) return { url };

        const afterFonts = u.pathname.slice(start + marker.length);
        const slashIdx = afterFonts.indexOf("/");
        if (slashIdx === -1) return { url };

        const fontstack = afterFonts.slice(0, slashIdx);
        const rest = afterFonts.slice(slashIdx);

        if (!/[,\s]/.test(fontstack)) return { url };

        const encodedFontstack = encodeURIComponent(fontstack);
        const newPath =
            u.pathname.slice(0, start + marker.length) + encodedFontstack + rest;

        u.pathname = newPath;
        return { url: u.toString() };
    } catch {
        return { url };
    }
}

export default RadarMap = {
    async mounted() {
        loadStylesheet(
            "radar-maps-css",
            `https://js.radar.com/maps/v${RADAR_MAPS_VERSION}/radar-maps.css`,
        );

        if (!window.radarPublicKey) {
            window.radarPublicKey = document.querySelector("meta[name='radar-public-key']")?.getAttribute("content");
        }

        const elementID = this.el.getAttribute("id");

        let existingMarker = undefined;
        let locked = false;
        let pendingMarker = null;
        let map = null;

        // Register handleEvent BEFORE async script load so we never miss the
        // initial push_event("add-marker") that fires during component mount.
        // If the map isn't ready yet we store the data in pendingMarker and
        // apply it once the map "load" event fires.
        this.handleEvent("add-marker", ({ lat, lon, locked: isLocked }) => {
            locked = isLocked || false;

            if (!map) {
                // Map not initialised yet — store for later
                pendingMarker = { lat, lon };
                return;
            }

            if (locked) {
                pendingMarker = { lat, lon };
                addMarkerWithRetry();
            } else {
                setMarker(lat, lon);
            }
        });

        this.handleEvent("position", () => {
            if (map) map.fitToMarkers({ maxZoom: 14, padding: 80 });
        });

        try {
            await loadScript("radar-js", `https://js.radar.com/v${RADAR_VERSION}/radar.min.js`);
            await loadScript(
                "radar-maps-js",
                `https://js.radar.com/maps/v${RADAR_MAPS_VERSION}/radar-maps.min.js`,
            );
        } catch (e) {
            console.error("Radar failed to load:", e);
            return;
        }

        const radarKey = window.radarPublicKey || "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966";

        const radarSetupError =
            "Radar Maps plugin is missing: load radar-maps.min.js after radar.min.js (see Radar docs).";

        if (!window.Radar || typeof window.Radar.initialize !== "function") {
            console.error(radarSetupError);
            return;
        }

        window.Radar.initialize(radarKey);

        if (!window.Radar.ui?.map) {
            console.error(radarSetupError);
            return;
        }

        map = window.Radar.ui.map({
            container: elementID,
            transformRequest: radarGlyphTransformRequest,
        });

        // Radar styles sometimes reference sprite icons (e.g. "viewpoint") not present for every zoom/style combo.
        map.on("styleimagemissing", (e) => {
            try {
                if (e.id !== "viewpoint") return;
                if (typeof map.hasImage === "function" && map.hasImage(e.id)) return;
                map.addImage(e.id, {
                    width: 1,
                    height: 1,
                    data: new Uint8Array(4),
                });
            } catch {
                /* ignore — avoid breaking map load */
            }
        });

        const verifyMarker = (marker) => {
            if (!marker) return false;
            if (typeof marker.getMap === 'function') {
                const attachedMap = marker.getMap();
                return attachedMap !== null && attachedMap !== undefined;
            }
            return true;
        };

        const isMapReady = () => {
            if (typeof map.loaded === 'function') return map.loaded();
            return true;
        };

        const setMarker = (lat, lon) => {
            if (!lat || !lon) return false;

            try {
                if (existingMarker) existingMarker.remove();
                existingMarker = Radar.ui.marker().setLngLat([lon, lat]).addTo(map);

                if (!verifyMarker(existingMarker)) return false;

                map.fitToMarkers({ maxZoom: 14, padding: 80 });
                return true;
            } catch (error) {
                console.error("Error setting marker:", error);
                return false;
            }
        };

        const addMarkerWithRetry = (attempts = 0) => {
            if (attempts > 20) {
                console.warn("Map marker retry limit reached. Marker may not be visible.");
                return;
            }

            if (pendingMarker && isMapReady()) {
                const success = setMarker(pendingMarker.lat, pendingMarker.lon);
                if (success && verifyMarker(existingMarker)) {
                    pendingMarker = null;
                    return;
                }
            }

            setTimeout(() => addMarkerWithRetry(attempts + 1), 500);
        };

        map.on("load", () => {
            if (pendingMarker) {
                const { lat, lon } = pendingMarker;
                if (setMarker(lat, lon)) pendingMarker = null;
            }

            if (existingMarker) {
                if (verifyMarker(existingMarker)) {
                    setTimeout(() => map.fitToMarkers({ maxZoom: 14, padding: 80 }), 300);
                } else {
                    map.fitToMarkers({ maxZoom: 14, padding: 80 });
                }
            }
        });

        map.on("click", (e) => {
            if (locked) return;
            if (typeof map.loaded === 'function' && !map.loaded()) return;

            if (existingMarker) existingMarker.remove();

            const { lng, lat } = e.lngLat;
            try {
                existingMarker = Radar.ui.marker().setLngLat([lng, lat]).addTo(map);

                if (!verifyMarker(existingMarker)) {
                    console.error("Failed to attach marker to map");
                    return;
                }

                this.pushEvent("map-new-marker", { lat: lat, long: lng });
                map.fitToMarkers({ maxZoom: 14, padding: 80 });

                existingMarker.on("click", () => {
                    existingMarker.remove();
                    map.fitToMarkers({ maxZoom: 14, padding: 80 });
                });
            } catch (error) {
                console.error("Error creating marker on click:", error);
            }
        });
    },
};
