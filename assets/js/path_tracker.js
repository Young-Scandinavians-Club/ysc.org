// PathTracker hook - listens for current_path push_events and posts to NotificationCenter
// This is used by the native SwiftUI app to track the current route
let PathTracker = {
    mounted() {
        // Listen for push_event("current_path") from LiveView
        this.handleEvent("current_path", ({ path }) => {
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
                window.webkit.messageHandlers.pathTracker.postMessage({ path: path });
            }

            // Also try to use a global function that SwiftUI can call
            // This is a fallback if message handlers don't work
            if (window.postPathToSwiftUI && typeof window.postPathToSwiftUI === 'function') {
                window.postPathToSwiftUI(path);
            }
        });
    }
};