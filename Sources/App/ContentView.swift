import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        if auth.isSignedIn || auth.isGuest {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct SignInPromptView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in required")
                .font(.headline)
            Text("This feature needs an account to access your AI-powered health insights.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Sign In") {
                auth.isGuest = false
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

// MARK: - Shared markdown renderer (used by ChatView and InsightsView)

struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(for: line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(for line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(line.dropFirst(3))
                .font(.subheadline).fontWeight(.bold)
                .padding(.top, 4)
        } else if line.hasPrefix("### ") {
            Text(line.dropFirst(4))
                .font(.subheadline).fontWeight(.semibold)
                .padding(.top, 2)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.subheadline)
                inlineText(String(line.dropFirst(2)))
            }
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Spacer().frame(height: 2)
        } else {
            inlineText(line)
        }
    }

    private func inlineText(_ text: String) -> Text {
        if let attr = try? AttributedString(markdown: text) {
            return Text(attr).font(.subheadline)
        }
        return Text(text).font(.subheadline)
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "brain.head.profile")
                }
            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.circle.fill")
                }
        }
    }
}
