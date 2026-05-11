import SwiftUI

struct ConfirmView: View {
    @EnvironmentObject var auth: AuthService
    let email: String
    let onSignIn: () -> Void

    @State private var code = ""
    @State private var confirmed = false
    @State private var resentCode = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Check your email")
                    .font(.title.bold())
                Text("We sent a confirmation code to\n\(email)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("6-digit code", text: $code)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .disabled(confirmed)

            if let error = auth.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            if resentCode {
                Label("Code resent. Check your inbox.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }

            if confirmed {
                VStack(spacing: 12) {
                    Label("Account confirmed!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)

                    Button {
                        onSignIn()
                    } label: {
                        Text("Sign In Now")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button {
                    Task {
                        do {
                            try await auth.confirmSignUp(email: email, code: code)
                            confirmed = true
                        } catch {
                            auth.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView()
                        } else {
                            Text("Confirm")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 6 || auth.isLoading)

                Button {
                    Task {
                        resentCode = false
                        do {
                            try await auth.resendConfirmationCode(email: email)
                            resentCode = true
                        } catch {
                            auth.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Text("Resend code")
                        .font(.subheadline)
                }
                .disabled(auth.isLoading)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
    }
}
