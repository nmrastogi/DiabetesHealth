import SwiftUI

struct ConfirmView: View {
    @EnvironmentObject var auth: AuthService
    let email: String
    @State private var code = ""
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss

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

            if let error = auth.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            if confirmed {
                Label("Account confirmed! Please sign in.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }

            Button {
                Task {
                    do {
                        try await auth.confirmSignUp(email: email, code: code)
                        confirmed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
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
            .disabled(code.count < 6 || auth.isLoading || confirmed)

            Spacer()
        }
        .padding(.horizontal, 32)
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
    }
}
