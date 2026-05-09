import SwiftUI

struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationStack {
            Group {
                if auth.isGuest {
                    SignInPromptView()
                        .navigationTitle("Insights")
                } else if vm.isLoading {
                    ProgressView("Loading insights…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isGenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Syncing health data…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Claude is analyzing your data…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.insights.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No insights yet")
                            .font(.headline)
                        Text("Tap Generate to create AI-powered insights from your health data.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.insights) { insight in
                        InsightRow(insight: insight)
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.load(force: true) }
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.generate() }
                    } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .disabled(vm.isLoading || vm.isGenerating)

                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading || vm.isGenerating)
                }
            }
            .task { await vm.load() }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
                Button("OK") { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
        }
    }
}

struct InsightRow: View {
    let insight: AIInsight

    private var typeLabel: String {
        switch insight.insightType {
        case "glucose":  return "Glucose"
        case "sleep":    return "Sleep"
        case "exercise": return "Exercise"
        case "combined": return "Overall"
        default:         return insight.insightType.capitalized
        }
    }

    private var typeColor: Color {
        switch insight.insightType {
        case "glucose":  return .blue
        case "sleep":    return .indigo
        case "exercise": return .green
        default:         return .teal
        }
    }

    private var typeIcon: String {
        switch insight.insightType {
        case "glucose":  return "drop.fill"
        case "sleep":    return "moon.zzz.fill"
        case "exercise": return "figure.run"
        default:         return "sparkles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: typeIcon)
                    .foregroundStyle(typeColor)
                Text(typeLabel)
                    .font(.caption.bold())
                    .foregroundStyle(typeColor)
                Spacer()
                if let week = insight.weekStart {
                    Text("Week of \(formattedWeek(week))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            MarkdownText(content: insight.content)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private static let inFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let outFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    private func formattedWeek(_ dateStr: String) -> String {
        guard let d = Self.inFmt.date(from: dateStr) else { return dateStr }
        return Self.outFmt.string(from: d)
    }
}

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var insights: [AIInsight] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var errorMessage: String?
    private var lastFetchDate: Date?

    func load(force: Bool = false) async {
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 300 { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            insights = try await APIService.shared.fetchInsights()
            lastFetchDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let response = try await APIService.shared.generateInsights()
            insights = response.data
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
