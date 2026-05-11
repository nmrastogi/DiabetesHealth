import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var navigateToConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var passwordsMatch: Bool { password == confirm }
    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && passwordsMatch && !auth.isLoading
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Create Account")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password (min 8 characters)", text: $password)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm password", text: $confirm)
                    .textFieldStyle(.roundedBorder)

                if !confirm.isEmpty && !passwordsMatch {
                    Text("Passwords do not match")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if let error = auth.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    do {
                        try await auth.signUp(email: email, password: password)
                        navigateToConfirm = true
                    } catch {
                        auth.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Group {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Text("Create Account")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onTapGesture { hideKeyboard() }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToConfirm) {
            ConfirmView(email: email, onSignIn: { dismiss() })
        }
    }
}
