import SwiftUI

struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading insights…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.insights.isEmpty {
                    ContentUnavailableView(
                        "No insights yet",
                        systemImage: "brain.head.profile",
                        description: Text("Insights are generated weekly once enough health data has been synced.")
                    )
                } else {
                    List(vm.insights) { insight in
                        InsightRow(insight: insight)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
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
            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func formattedWeek(_ dateStr: String) -> String {
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        guard let date = iso.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: date)
    }
}

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var insights: [AIInsight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            insights = try await APIService.shared.fetchInsights()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
