import { loadScript, loadStylesheet } from "./load_external_asset";
import { pushEventIfConnected } from "./live_view_safe_push";

/** Radar Web SDK core bundle — https://docs.radar.com/maps/maps */
const RADAR_VERSION = "5.1.0";

/** Maps plugin — registers `Radar.ui`; required from Radar SDK v5+ (core SDK alone has no `Radar.ui`). */
const RADAR_MAPS_VERSION = "1.0.0";

function pushLocationSelected(hook, { location_name, address, latitude, longitude, place_id }) {
    pushEventIfConnected(hook, "location-selected", {
        location_name: location_name || "",
        address: address || "",
        latitude,
        longitude,
        place_id: place_id || null,
    });
}

function reverseGeocodeAndPush(hook, lat, lng) {
    if (!window.Radar?.reverseGeocode) {
        pushLocationSelected(hook, {
            latitude: lat,
            longitude: lng,
            location_name: "",
            address: "",
            place_id: null,
        });
        return;
    }

    window.Radar.reverseGeocode({ latitude: lat, longitude: lng })
        .then((result) => {
            const address = result?.addresses?.[0];

            if (address) {
                pushLocationSelected(hook, {
                    location_name: address.placeLabel || address.addressLabel || "",
                    address: address.formattedAddress || "",
                    latitude: lat,
                    longitude: lng,
                    place_id: address.placeId || null,
                });
            } else {
                pushLocationSelected(hook, {
                    latitude: lat,
                    longitude: lng,
                    location_name: "",
                    address: "",
                    place_id: null,
                });
            }
        })
        .catch(() => {
            pushLocationSelected(hook, {
                latitude: lat,
                longitude: lng,
                location_name: "",
                address: "",
                place_id: null,
            });
        });
}

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
        this._radarActive = true;

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
            if (map && map.style) map.fitToMarkers({ maxZoom: 14, padding: 80 });
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

        const cooperativeGestures = this.el.dataset.cooperativeGestures !== "false";

        // Safari (and mobile browsers generally) can drop the WebGL context, e.g. when the
        // tab is backgrounded or GPU memory is reclaimed. MapLibre then destroys its style
        // and sets `map.style = null`, so any further call on that instance throws
        // "null is not an object (evaluating 'this.style.imageManager')". Instead of
        // touching the dead map we tear it down and build a fresh one.
        const MAX_CONTEXT_REBUILDS = 3;
        const CONTEXT_REBUILD_DELAY_MS = 1000;
        let contextRebuilds = 0;

        const verifyMarker = (marker) => {
            if (!marker) return false;
            if (typeof marker.getMap === 'function') {
                const attachedMap = marker.getMap();
                return attachedMap !== null && attachedMap !== undefined;
            }
            return true;
        };

        const isMapReady = () => {
            if (!map || !map.style) return false;
            if (typeof map.loaded === 'function') return map.loaded();
            return true;
        };

        const setMarker = (lat, lon) => {
            if (!map || !map.style || !lat || !lon) return false;

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
            if (!this._radarActive) return;

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

        const handleContextLost = (instance) => {
            if (map !== instance || !this._radarActive) return;

            // Keep the marker position so the replacement map can restore it.
            try {
                const lngLat = existingMarker?.getLngLat?.();
                if (lngLat) pendingMarker = { lat: lngLat.lat, lon: lngLat.lng };
            } catch (_) {
                /* ignore */
            }
            existingMarker = null;

            map = null;
            this._radarMap = null;
            try {
                instance.remove();
            } catch (_) {
                /* style is already gone — nothing left to clean up */
            }

            if (contextRebuilds >= MAX_CONTEXT_REBUILDS) {
                console.warn("Radar map lost its WebGL context; giving up after repeated rebuilds.");
                return;
            }

            contextRebuilds += 1;
            this._radarRebuildTimer = setTimeout(() => {
                this._radarRebuildTimer = null;
                if (this._radarActive && !map) initMap();
            }, CONTEXT_REBUILD_DELAY_MS);
        };

        const initMap = () => {
            const instance = window.Radar.ui.map({
                container: elementID,
                transformRequest: radarGlyphTransformRequest,
                cooperativeGestures,
            });

            map = instance;
            this._radarMap = instance;

            instance.on("webglcontextlost", () => handleContextLost(instance));

            // Radar styles sometimes reference sprite icons (e.g. "viewpoint") not present for every zoom/style combo.
            instance.on("styleimagemissing", (e) => {
                try {
                    if (map !== instance || !instance.style) return;
                    if (e.id !== "viewpoint") return;
                    if (typeof instance.hasImage === "function" && instance.hasImage(e.id)) return;
                    instance.addImage(e.id, {
                        width: 1,
                        height: 1,
                        data: new Uint8Array(4),
                    });
                } catch {
                    /* ignore — avoid breaking map load */
                }
            });

            instance.on("load", () => {
                if (map !== instance) return;

                if (pendingMarker) {
                    const { lat, lon } = pendingMarker;
                    if (setMarker(lat, lon)) pendingMarker = null;
                }

                if (existingMarker) {
                    if (verifyMarker(existingMarker)) {
                        setTimeout(() => {
                            if (map === instance && instance.style) {
                                instance.fitToMarkers({ maxZoom: 14, padding: 80 });
                            }
                        }, 300);
                    } else {
                        instance.fitToMarkers({ maxZoom: 14, padding: 80 });
                    }
                }
            });

            instance.on("click", (e) => {
                if (!this._radarActive || map !== instance || !instance.style) return;
                if (locked) return;
                if (typeof instance.loaded === 'function' && !instance.loaded()) return;

                if (existingMarker) existingMarker.remove();

                const { lng, lat } = e.lngLat;
                try {
                    existingMarker = Radar.ui.marker().setLngLat([lng, lat]).addTo(instance);

                    if (!verifyMarker(existingMarker)) {
                        console.error("Failed to attach marker to map");
                        return;
                    }

                    reverseGeocodeAndPush(this, lat, lng);
                    instance.fitToMarkers({ maxZoom: 14, padding: 80 });

                    existingMarker.on("click", () => {
                        existingMarker.remove();
                        if (map === instance && instance.style) {
                            instance.fitToMarkers({ maxZoom: 14, padding: 80 });
                        }
                    });
                } catch (error) {
                    console.error("Error creating marker on click:", error);
                }
            });
        };

        initMap();
    },

    destroyed() {
        this._radarActive = false;
        if (this._radarRebuildTimer) {
            clearTimeout(this._radarRebuildTimer);
            this._radarRebuildTimer = null;
        }
        if (this._radarMap) {
            try {
                this._radarMap.remove();
            } catch (_) {
                /* ignore */
            }
            this._radarMap = null;
        }
    },
};
