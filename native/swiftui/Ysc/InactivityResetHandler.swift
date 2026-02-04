//
//  InactivityResetHandler.swift
//  Ysc
//
//  LiveElement component that handles inactivity timeout and navigates to home

import SwiftUI
import LiveViewNative

@LiveElement
struct InactivityResetHandler<Root: RootRegistry>: View {
    let element: ElementNode
    // Use optional @Event to avoid initialization issues
    // Only access it after the view is fully connected
    @Event("native_nav", type: "click") private var navigate
    @State private var readyToNavigate = false
    @State private var pendingRoute: String?
    
    var body: some View {
        // Use a Button so @Event has a proper context
        Button(action: {
            guard readyToNavigate, let route = pendingRoute else { return }
            navigate(value: ["to": route])
            pendingRoute = nil
        }) {
            Color.clear
                .frame(width: 0, height: 0)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .onAppear {
            print("[InactivityResetHandler] Component appeared, waiting for @Event initialization...")
            // Wait longer to ensure @Event is fully initialized
            // The fatal error suggests @Event accesses element properties during init
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("[InactivityResetHandler] Marking as ready to navigate")
                readyToNavigate = true
                // If there's a pending route, trigger it now
                if let route = pendingRoute {
                    print("[InactivityResetHandler] Triggering pending navigation to \(route)")
                    navigate(value: ["to": route])
                    pendingRoute = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("InactivityTimeout"))) { notification in
            print("[InactivityResetHandler] Received InactivityTimeout notification")
            if let userInfo = notification.userInfo,
               let route = userInfo["route"] as? String {
                let routeToUse = element.attributeValue(for: "phx-value-to") as? String ?? route
                print("[InactivityResetHandler] Route to navigate: \(routeToUse), readyToNavigate: \(readyToNavigate)")
                pendingRoute = routeToUse
                
                // If already ready, trigger immediately
                if readyToNavigate {
                    print("[InactivityResetHandler] Triggering navigation to \(routeToUse)")
                    navigate(value: ["to": routeToUse])
                    pendingRoute = nil
                } else {
                    print("[InactivityResetHandler] Not ready yet, storing route for later")
                }
            }
        }
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @Addon
    struct InactivityResetHandlerView<Root: RootRegistry> {
        enum TagName: String {
            case inactivityResetHandler = "InactivityResetHandler"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .inactivityResetHandler:
                InactivityResetHandler<Root>(element: element)
            }
        }
    }
}
