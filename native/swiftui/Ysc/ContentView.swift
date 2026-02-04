//
//  ContentView.swift
//  Ysc
//

import LiveViewNative
import LiveViewNativeLiveForm
import SwiftUI

@available(iOS 18.0, *)
struct ContentView: View {
    @State private var isAuthenticated: Bool = false
    @State private var apiKey: String?
    @StateObject private var inactivityTimer = InactivityTimer()

    private static func developmentURL() -> URL {
        // `.localhost(...)` resolves to `localhost` which often prefers IPv6 (`::1`).
        // Our Phoenix dev server is commonly bound on IPv4 only, which can lead to
        // `nw_socket_handle_socket_event ... ::1.4000 ... Connection refused`.
        //
        // Override in Xcode Scheme (Run > Arguments > Environment Variables):
        // - LVN_DEV_HOST (e.g. 127.0.0.1 for Simulator, or your Mac LAN IP for devices)
        // - LVN_DEV_PORT (defaults to 4000)
        let host = ProcessInfo.processInfo.environment["LVN_DEV_HOST"] ?? "127.0.0.1"
        let port = ProcessInfo.processInfo.environment["LVN_DEV_PORT"] ?? "4000"
        return URL(string: "http://\(host):\(port)/")!
    }

    init() {
        // Check if API key exists on initialization
        _isAuthenticated = State(initialValue: APIKeyManager.hasAPIKey())
        _apiKey = State(initialValue: APIKeyManager.getAPIKey())
    }

    var body: some View {
        if isAuthenticated, let apiKey = apiKey {
            // Show LiveView with API key in URL query parameter
            LiveViewWithAPIKey(
                developmentURL: Self.developmentURL(),
                productionURL: URL(string: "https://example.com/")!,
                apiKey: apiKey,
                inactivityTimer: inactivityTimer
            )
        } else {
            // Show API key input view
            APIKeyInputView(isAuthenticated: $isAuthenticated)
                .onChange(of: isAuthenticated) { newValue in
                    if newValue {
                        // Reload API key when authenticated
                        apiKey = APIKeyManager.getAPIKey()
                    }
                }
        }
    }
}

// Helper view that configures LiveView with API key in URL query parameter
@available(iOS 18.0, *)
struct LiveViewWithAPIKey: View {
    let baseDevelopmentURL: URL
    let baseProductionURL: URL
    let apiKey: String
    @ObservedObject var inactivityTimer: InactivityTimer
    @ObservedObject var homePageState = HomePageState.shared // Observe shared state from PathTracker
    @State private var forceNavigateToHome: Bool = false
    @State private var navigationKey: Int = 0
    @State private var justRedirected: Bool = false // Track if we just redirected (don't show countdown/redirect again)

    init(developmentURL: URL, productionURL: URL, apiKey: String, inactivityTimer: InactivityTimer) {
        self.baseDevelopmentURL = developmentURL
        self.baseProductionURL = productionURL
        self.apiKey = apiKey
        self._inactivityTimer = ObservedObject(wrappedValue: inactivityTimer)
    }

    private func urlWithAPIKey(_ baseURL: URL, path: String? = nil) -> URL {
        guard var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        // Set path if provided (for navigation to home)
        if let path = path {
            urlComponents.path = path
        }
        // Append API key as query parameter
        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        urlComponents.queryItems = queryItems
        return urlComponents.url ?? baseURL
    }

    private var developmentURLWithKey: URL {
        // If we need to navigate to home, use home path, otherwise use base URL
        urlWithAPIKey(baseDevelopmentURL, path: forceNavigateToHome ? "/" : nil)
    }

    private var productionURLWithKey: URL {
        urlWithAPIKey(baseProductionURL, path: forceNavigateToHome ? "/" : nil)
    }

    var body: some View {
        ZStack {
            #LiveView(
                .automatic(
                    development: developmentURLWithKey,
                    production: productionURLWithKey
                ),
                addons: [.liveForm, .roomCalendarView, .cabinRulesView, .pathTrackerView, .reservationsTableView, .animatedCheckmarkView]
            ) {
                ConnectingView()
            } disconnected: {
                DisconnectedView()
            } reconnecting: { content, isReconnecting in
                ReconnectingView(isReconnecting: isReconnecting) {
                    content
                        .detectInactivity(timer: inactivityTimer)
                        .onAppear {
                            // Set up timeout callback to navigate to home
                            setupInactivityHandler()
                        }
                }
                .onAppear {
                    // Reset timer when navigation happens (reconnecting view appears)
                    if !forceNavigateToHome {
                        justRedirected = false
                        inactivityTimer.reset()
                    } else {
                        // We're forcing to home
                        justRedirected = true // Set flag so we don't show countdown/redirect again
                        inactivityTimer.reset()
                    }
                }
            } error: { error in
                ErrorView(error: error)
            }
            .detectInactivity(timer: inactivityTimer)
            .onAppear {
                // Set up timeout callback to navigate to home
                setupInactivityHandler()
            }
            .onChange(of: forceNavigateToHome) { isForcing in
                // When we force navigate to home, update state immediately (bypass debounce)
                if isForcing {
                    homePageState.setImmediate(true)
                    justRedirected = true
                }
            }
            // Observe changes to homePageState.isHome (updated by PathTracker)
            .onChange(of: homePageState.isHome) { newValue in
                print("[ContentView] homePageState.isHome changed to: \(newValue)")
                justRedirected = false
                inactivityTimer.reset()
            }
            .id(navigationKey) // Force re-render when navigation key changes

            // Countdown indicator overlay (only show if not on home page and not just redirected)
            let shouldShowCountdown = !homePageState.isHome &&
                !justRedirected && // Don't show if we just redirected
                !forceNavigateToHome && // Don't show when navigating to home
                ((inactivityTimer.secondsRemaining <= InactivityTimer.warningThreshold && inactivityTimer.secondsRemaining > 0) || inactivityTimer.isCancelling)

            if shouldShowCountdown {
                InactivityCountdownView(
                    secondsRemaining: Int(inactivityTimer.secondsRemaining),
                    isCancelling: inactivityTimer.isCancelling
                )
            }
        }
    }

    private func setupInactivityHandler() {
        inactivityTimer.onTimeout = {
            // Only navigate if we're not on home page and haven't just redirected
            if !homePageState.isHome && !justRedirected {
                print("[ContentView] Inactivity timeout - navigating to home (isHome: \(homePageState.isHome))")
                // Force navigation by changing the URL to home and triggering a re-render
                DispatchQueue.main.async {
                    forceNavigateToHome = true
                    homePageState.setImmediate(true) // Bypass debounce for forced navigation
                    justRedirected = true // Set flag so we don't show countdown/redirect again
                    navigationKey += 1 // Force LiveView to reconnect with home URL
                    // Reset the flag after a short delay so normal navigation can work again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        forceNavigateToHome = false
                    }
                }
            } else {
                print("[ContentView] Inactivity timeout - already on home (isHome: \(homePageState.isHome)) or just redirected, skipping navigation")
            }
        }
    }
}

