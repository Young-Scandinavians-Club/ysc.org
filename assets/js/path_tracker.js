// PathTracker hook - listens for current_path push_events and posts to NotificationCenter
// This is used by the native SwiftUI app to track the current route
let PathTracker = {
    mounted() {
        console.log("[PathTracker] Hook mounted - setting up event listener");
        // Listen for push_event("current_path") from LiveView
        this.handleEvent("current_path", ({ path }) => {
            console.log("[PathTracker] Received current_path event:", path);

            // Post notification that SwiftUI can listen to via NotificationCenter
            // For native SwiftUI apps, we need to use a mechanism that can bridge JS to SwiftUI
            // Use a custom event that can be picked up by SwiftUI's web view bridge
            window.dispatchEvent(
                new CustomEvent("liveview:current_path", {
                    detail: { path }
                })
            );

            // Also try to post to NotificationCenter if available (for native apps)
            // This requires a bridge from JavaScript to SwiftUI via WKWebView message handlers
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pathTracker) {
                console.log("[PathTracker] Posting to webkit message handler");
                window.webkit.messageHandlers.pathTracker.postMessage({ path: path });
            } else {
                console.log("[PathTracker] webkit message handler not available - using CustomEvent");
            }

            // Also try to use a global function that SwiftUI can call
            // This is a fallback if message handlers don't work
            if (window.postPathToSwiftUI && typeof window.postPathToSwiftUI === 'function') {
                console.log("[PathTracker] Using postPathToSwiftUI function");
                window.postPathToSwiftUI(path);
            }
        });
    }
};