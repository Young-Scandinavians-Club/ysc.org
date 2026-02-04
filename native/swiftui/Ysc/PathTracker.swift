//
//  PathTracker.swift
//  Ysc
//
//  LiveElement component that reads the `is-home` attribute from LiveView
//  and updates shared state for ContentView to observe

import SwiftUI
import LiveViewNative

// Shared observable state for home page tracking with debounced updates
class HomePageState: ObservableObject {
    static let shared = HomePageState()
    @Published var isHome: Bool = true

    // Debounce mechanism to handle rapid value changes during navigation transitions
    private var pendingWorkItem: DispatchWorkItem?
    private var lastRequestedValue: Bool = true
    private let debounceInterval: TimeInterval = 0.15 // 150ms debounce

    private init() {}

    func requestUpdate(to newValue: Bool) {
        // Cancel any pending update
        pendingWorkItem?.cancel()
        lastRequestedValue = newValue

        // Schedule a new debounced update
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isHome != self.lastRequestedValue {
                print("[HomePageState] Debounced update: isHome = \(self.lastRequestedValue)")
                self.isHome = self.lastRequestedValue
            }
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    // Direct update (bypasses debounce) - use for forced navigation
    func setImmediate(_ value: Bool) {
        pendingWorkItem?.cancel()
        lastRequestedValue = value
        if isHome != value {
            print("[HomePageState] Immediate update: isHome = \(value)")
            isHome = value
        }
    }
}

@LiveElement
struct PathTracker<Root: RootRegistry>: View {
    let element: ElementNode

    // Read the is-home attribute from the element
    private var isHome: Bool {
        // attributeValue returns String?, convert to Bool
        guard let value = element.attributeValue(for: "is-home") else {
            return true // Default to home if attribute not present
        }
        // Handle string "true"/"false" or boolean
        if let stringValue = value as? String {
            return stringValue.lowercased() == "true"
        }
        return true
    }

    var body: some View {
        // Request a debounced state update
        // This filters out rapid alternations during navigation transitions
        let currentIsHome = isHome
        let _ = HomePageState.shared.requestUpdate(to: currentIsHome)

        // Use Text with single space so the view actually gets rendered (EmptyView might be optimized away)
        return Text(" ")
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @Addon
    struct PathTrackerView<Root: RootRegistry> {
        enum TagName: String {
            case pathTracker = "PathTracker"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .pathTracker:
                PathTracker<Root>(element: element)
            }
        }
    }
}
