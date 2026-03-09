import { loadScript, loadStylesheet } from "./load_external_asset";

export default RadarMap = {
    async mounted() {
        loadStylesheet("radar-css", "https://js.radar.com/v4.4.8/radar.css");

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
            await loadScript("radar-js", "https://js.radar.com/v4.4.8/radar.min.js");
        } catch (e) {
            console.error("Radar failed to load:", e);
            return;
        }

        const radarKey = window.radarPublicKey || "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966";
        window.Radar.initialize(radarKey);

        map = Radar.ui.map({
            container: elementID,
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
