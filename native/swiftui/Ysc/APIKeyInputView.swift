//
//  APIKeyInputView.swift
//  Ysc
//
//  View for entering API key on first launch
//

import SwiftUI

struct APIKeyInputView: View {
    @State private var apiKey: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false
    @Binding var isAuthenticated: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("API Key Required")
                    .font(.system(size: 28, weight: .bold))

                Text("Please enter your API key to continue")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            Spacer()

            // Input field
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                SecureField("Enter API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .disabled(isSubmitting)
                    .onSubmit {
                        submitAPIKey()
                    }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)

            // Submit button
            Button(action: submitAPIKey) {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(apiKey.isEmpty || isSubmitting ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(apiKey.isEmpty || isSubmitting)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func submitAPIKey() {
        guard !apiKey.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        // Store the API key
        if APIKeyManager.storeAPIKey(apiKey) {
            // Small delay to show success state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAuthenticated = true
            }
        } else {
            errorMessage = "Failed to store API key. Please try again."
            isSubmitting = false
        }
    }
}

#Preview {
    APIKeyInputView(isAuthenticated: .constant(false))
}
