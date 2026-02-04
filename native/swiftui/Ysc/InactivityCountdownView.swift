//
//  InactivityCountdownView.swift
//  Ysc
//
//  Visual countdown indicator shown when inactivity timeout is approaching

import SwiftUI

struct InactivityCountdownView: View {
    let secondsRemaining: Int
    let isCancelling: Bool
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    if isCancelling {
                        // Cancelling state
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(scale)
                        
                        Text("Cancelled")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        // Countdown number
                        Text("\(secondsRemaining)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                        
                        // Warning message
                        Text("Returning to home...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isCancelling ? Color.green.opacity(0.95) : Color.blue.opacity(0.95))
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                )
                .scaleEffect(scale)
                .padding(.trailing, 24)
                .padding(.bottom, 40)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: secondsRemaining)
        .onChange(of: isCancelling) { cancelling in
            if cancelling {
                // Animate checkmark appearance
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    scale = 1.2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scale = 1.0
                    }
                }
            }
        }
    }
}
