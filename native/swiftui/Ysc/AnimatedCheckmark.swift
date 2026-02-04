//
//  AnimatedCheckmark.swift
//  Ysc
//
//  An animated success checkmark component for check-in completion

import SwiftUI
import LiveViewNative

@LiveElement
struct AnimatedCheckmark<Root: RootRegistry>: View {
    let element: ElementNode
    
    @State private var isAnimating = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var outerCircleScale: CGFloat = 0
    @State private var innerCircleScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Outer glow circle
            Circle()
                .fill(Color.green.opacity(0.06))
                .frame(width: 180, height: 180)
                .scaleEffect(outerCircleScale)
            
            // Inner glow circle
            Circle()
                .fill(Color.green.opacity(0.12))
                .frame(width: 140, height: 140)
                .scaleEffect(innerCircleScale)
            
            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
        }
        .onAppear {
            animateIn()
        }
    }
    
    private func animateIn() {
        // Staggered animation for a nice reveal effect
        
        // Outer circle expands first
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
            outerCircleScale = 1.0
        }
        
        // Inner circle follows
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
            innerCircleScale = 1.0
        }
        
        // Checkmark bounces in last
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }
        
        // Add a subtle pulse after the initial animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// Register the component with LiveView Native
extension Addons {
    @available(iOS 18.0, *)
    @Addon
    struct AnimatedCheckmarkView<Root: RootRegistry> {
        enum TagName: String {
            case animatedCheckmark = "AnimatedCheckmark"
        }
        
        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .animatedCheckmark:
                AnimatedCheckmark<Root>(element: element)
            }
        }
    }
}
