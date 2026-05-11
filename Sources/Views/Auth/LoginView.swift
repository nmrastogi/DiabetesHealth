import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Logo / Title
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    Text("DiabetesHealth")
                        .font(.largeTitle.bold())
                    Text("Track. Understand. Thrive.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Fields
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                // Sign In
                Button {
                    Task {
                        do {
                            try await auth.signIn(email: email, password: password)
                        } catch {
                            auth.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView()
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || auth.isLoading)

                // Sign Up
                Button("Don't have an account? Sign up") {
                    showSignUp = true
                }
                .font(.footnote)

                Button("Continue without account") {
                    auth.continueAsGuest()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 32)
            .onTapGesture { hideKeyboard() }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }
}
