import SwiftUI

struct AccountView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showChangePassword = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Text(initials)
                                .font(.title3.bold())
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.userEmail ?? "Signed in")
                                .font(.subheadline.bold())
                            Text("Diabetico account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Account actions
                Section("Account") {
                    Button {
                        showChangePassword = true
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                            .foregroundStyle(.primary)
                    }
                }

                // Data section
                Section("Data") {
                    HStack {
                        Label("HealthKit Sync", systemImage: "heart.fill")
                        Spacer()
                        Text(HealthKitService.shared.lastSyncDate.map { relativeDate($0) } ?? "Never")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView()
                    .environmentObject(auth)
            }
            .confirmationDialog("Sign out of Diabetico?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var initials: String {
        guard let email = auth.userEmail,
              let first = email.first else { return "?" }
        return String(first).uppercased()
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Change Password Sheet

struct ChangePasswordView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var success = false

    private var passwordsMatch: Bool { newPassword == confirm }
    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 8 && passwordsMatch && !auth.isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("Enter current password", text: $current)
                }

                Section("New Password") {
                    SecureField("New password (min 8 characters)", text: $newPassword)
                    SecureField("Confirm new password", text: $confirm)

                    if !confirm.isEmpty && !passwordsMatch {
                        Text("Passwords do not match")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if success {
                    Section {
                        Label("Password changed successfully.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                do {
                                    try await auth.changePassword(current: current, new: newPassword)
                                    success = true
                                    auth.errorMessage = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        dismiss()
                                    }
                                } catch {
                                    auth.errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSubmit)
                    }
                }
            }
        }
    }
}
