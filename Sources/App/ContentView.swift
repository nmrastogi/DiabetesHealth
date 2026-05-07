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

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "brain.head.profile")
                }
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
        }
    }
}
