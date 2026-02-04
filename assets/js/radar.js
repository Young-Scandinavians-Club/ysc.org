export default RadarMap = {
    mounted() {
        // Wait for Radar library to be available
        const initRadar = () => {
            if (typeof window.Radar === 'undefined' || !window.Radar) {
                setTimeout(initRadar, 100);
                return;
            }

            const radarKey = window.radarPublicKey || "prj_test_pk_5bcfd56661bb7fc596d70d5f21f0e2c6049b0966";
            window.Radar.initialize(radarKey);

            let existingMarker = undefined;
            let locked = false; // Scoped to this map instance
            let pendingMarker = null; // Store pending marker coordinates
            const elementID = this.el.getAttribute("id");
            const map = Radar.ui.map({
                container: elementID,
            });

            // Helper function to verify marker is attached to the map
            const verifyMarker = (marker) => {
                if (!marker) {
                    return false;
                }
                // Check if marker has a getMap method and is attached
                if (typeof marker.getMap === 'function') {
                    const attachedMap = marker.getMap();
                    return attachedMap !== null && attachedMap !== undefined;
                }
                // Fallback: if marker exists and was added to map, assume it's valid
                // Many map libraries don't expose getMap(), so we check if marker exists
                return true;
            };

            // Helper to check if map is ready
            const isMapReady = () => {
                // Check if map has a loaded() method
                if (typeof map.loaded === 'function') {
                    return map.loaded();
                }
                // If no loaded() method, assume map is ready after a short delay
                // This handles cases where the map object exists but loaded() isn't available
                return true;
            };

            const setMarker = (lat, lon) => {
                if (!lat || !lon) {
                    return false;
                }

                try {
                    if (existingMarker) {
                        existingMarker.remove();
                    }
                    existingMarker = Radar.ui.marker().setLngLat([lon, lat]).addTo(map);

                    // Verify marker was actually attached
                    if (!verifyMarker(existingMarker)) {
                        return false;
                    }

                    // fit map to markers
                    map.fitToMarkers({ maxZoom: 14, padding: 80 });
                    return true;
                } catch (error) {
                    console.error("Error setting marker:", error);
                    return false;
                }
            };

            // Wait for map to load before handling marker operations
            map.on("load", () => {
                // If there's a pending marker, set it now that map is loaded
                if (pendingMarker) {
                    const { lat, lon } = pendingMarker;
                    const success = setMarker(lat, lon);
                    if (success) {
                        pendingMarker = null; // Clear pending marker
                    }
                }

                // If there's an existing marker, ensure it's properly set and refit
                if (existingMarker) {
                    if (verifyMarker(existingMarker)) {
                        // Hack to make the zoom work on render (after map load)
                        setTimeout(() => {
                            map.fitToMarkers({ maxZoom: 14, padding: 80 });
                        }, 300);
                    } else {
                        // Marker exists but isn't properly attached, try to refit anyway
                        map.fitToMarkers({ maxZoom: 14, padding: 80 });
                    }
                }
            });

            this.handleEvent("add-marker", ({ lat, lon, locked: isLocked }) => {
                locked = isLocked || false;

                if (locked) {
                    // Store pending marker coordinates
                    pendingMarker = { lat, lon };

                    // Retry logic for locked maps to handle slow page loads
                    // Use recursive setTimeout pattern (not loops) to avoid blocking the UI
                    const addMarkerWithRetry = (attempts = 0) => {
                        // Stop after 10 seconds (20 attempts at 500ms each) to prevent infinite checking
                        if (attempts > 20) {
                            console.warn("Map marker retry limit reached. Marker may not be visible.");
                            // Don't clear pendingMarker - let map load event handle it
                            return;
                        }

                        // Check if map is ready before attempting to set marker
                        const mapReady = isMapReady();

                        if (mapReady) {
                            const success = setMarker(lat, lon);

                            if (success && verifyMarker(existingMarker)) {
                                // Marker successfully set and verified
                                pendingMarker = null; // Clear pending marker
                                return;
                            }
                        }

                        // If not ready or marker not set, wait 500ms and try again
                        setTimeout(() => addMarkerWithRetry(attempts + 1), 500);
                    };

                    // Initial attempt
                    addMarkerWithRetry();
                } else {
                    // For unlocked maps, set marker directly (user interaction will handle retries if needed)
                    setMarker(lat, lon);
                }
            });

            map.on("click", (e) => {
                if (locked) {
                    return;
                }

                // Only handle clicks if map is loaded
                if (typeof map.loaded === 'function' && !map.loaded()) {
                    return;
                }

                if (existingMarker) {
                    existingMarker.remove();
                }

                const { lng, lat } = e.lngLat;
                // create marker from click location
                try {
                    existingMarker = Radar.ui.marker().setLngLat([lng, lat]).addTo(map);

                    // Verify marker was set
                    if (!verifyMarker(existingMarker)) {
                        console.error("Failed to attach marker to map");
                        return;
                    }

                    this.pushEvent("map-new-marker", { lat: lat, long: lng });

                    // fit map to markers
                    map.fitToMarkers({ maxZoom: 14, padding: 80 });

                    existingMarker.on("click", (e) => {
                        existingMarker.remove();
                        map.fitToMarkers({ maxZoom: 14, padding: 80 }); // refit after marker removed
                    });
                } catch (error) {
                    console.error("Error creating marker on click:", error);
                }
            });

            this.handleEvent("position", () => {
                map.fitToMarkers({ maxZoom: 14, padding: 80 });
            });
        };

        initRadar();
    },
};
