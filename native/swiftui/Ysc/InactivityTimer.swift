//
//  InactivityTimer.swift
//  Ysc
//
//  Manages inactivity timer for check-in kiosk applications
//  Automatically resets to home screen after 30 seconds of inactivity

import SwiftUI
import Combine

/// Observable object that manages the inactivity timer
class InactivityTimer: ObservableObject {
    /// Timeout duration in seconds (30 seconds)
    static let timeoutDuration: TimeInterval = 15.0

    /// Warning threshold - show countdown when this many seconds remain
    static let warningThreshold: TimeInterval = 10.0

    /// Last time user interacted with the app
    @Published private(set) var lastInteractionTime: Date

    /// Seconds remaining until timeout (published for UI updates)
    @Published private(set) var secondsRemaining: TimeInterval = 0

    /// Whether the countdown is currently being cancelled (for animation)
    @Published private(set) var isCancelling: Bool = false

    /// Timer publisher for checking inactivity
    private var timer: Timer.TimerPublisher?
    private var cancellables = Set<AnyCancellable>()

    /// Callback to execute when inactivity timeout is reached
    var onTimeout: (() -> Void)?

    init() {
        self.lastInteractionTime = Date()
        self.secondsRemaining = Self.timeoutDuration
        startTimer()
        setupNotificationListeners()
    }

    /// Set up notification listeners for button presses and other interactions
    private func setupNotificationListeners() {
        // Listen for user interaction notifications
        NotificationCenter.default.publisher(for: NSNotification.Name("UserInteraction"))
            .sink { [weak self] _ in
                self?.reset()
            }
            .store(in: &cancellables)
    }

    deinit {
        stopTimer()
    }

    /// Start the inactivity monitoring timer
    private func startTimer() {
        stopTimer() // Stop any existing timer

        timer = Timer.publish(every: 1.0, on: .main, in: .common)
        timer?
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkInactivity()
            }
            .store(in: &cancellables)
    }

    /// Stop the inactivity monitoring timer
    private func stopTimer() {
        cancellables.removeAll()
        timer = nil
    }

    /// Check if user has been inactive for the timeout duration
    private func checkInactivity() {
        let timeSinceLastInteraction = Date().timeIntervalSince(lastInteractionTime)
        let remaining = Self.timeoutDuration - timeSinceLastInteraction

        // Update seconds remaining (clamp to 0)
        secondsRemaining = max(0, remaining)

        if timeSinceLastInteraction >= Self.timeoutDuration {
            // Timeout reached - trigger callback
            print("[InactivityTimer] Timeout reached after \(timeSinceLastInteraction) seconds")
            secondsRemaining = 0
            onTimeout?()
            // Reset the timer to prevent multiple rapid triggers
            reset()
        }
    }

    /// Reset the inactivity timer (call when user interacts)
    func reset() {
        // If countdown was showing, trigger cancelling animation
        if secondsRemaining <= Self.warningThreshold && secondsRemaining > 0 {
            isCancelling = true
            // Hide after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isCancelling = false
            }
        }

        lastInteractionTime = Date()
        secondsRemaining = Self.timeoutDuration // Reset countdown
    }

    /// Manually trigger the timeout (for testing)
    func triggerTimeout() {
        onTimeout?()
    }
}

// MARK: - View Modifier for Interaction Detection

/// View modifier that detects user interactions and resets the inactivity timer
struct InactivityDetectionModifier: ViewModifier {
    @ObservedObject var timer: InactivityTimer

    private func resetTimer() {
        timer.reset()
        // Also post notification for button presses and other interactions
        NotificationCenter.default.post(name: NSNotification.Name("UserInteraction"), object: nil)
    }

    func body(content: Content) -> some View {
        content
            // Use simultaneousGesture to detect interactions without blocking navigation
            // Only detect taps and significant drags (not edge swipes for back navigation)
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        resetTimer()
                    }
            )
            // Use a minimum distance for drags to avoid interfering with navigation gestures
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { _ in
                        resetTimer()
                    }
            )
            // Also add background layer with gestures as backup
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                resetTimer()
                            }
                    )
                    // Use higher minimum distance to avoid navigation edge swipes
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { _ in
                                resetTimer()
                            }
                    )
            )
            // Reset on view appearance (user navigated to this view)
            .onAppear {
                timer.reset()
            }
    }
}

extension View {
    /// Apply inactivity detection to a view
    /// This modifier detects taps, drags, and other interactions to reset the inactivity timer
    func detectInactivity(timer: InactivityTimer) -> some View {
        modifier(InactivityDetectionModifier(timer: timer))
    }
}
