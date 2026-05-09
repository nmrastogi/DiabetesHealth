import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Sync banner
                    if vm.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Syncing health data…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Summary cards
                    if let summary = vm.summary {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            SummaryCard(
                                title: "Avg Glucose",
                                value: summary.avgGlucose.map { String(format: "%.0f", $0) } ?? "—",
                                unit: "mg/dL",
                                color: glucoseColor(summary.avgGlucose),
                                icon: "drop.fill"
                            )
                            SummaryCard(
                                title: "Time in Range",
                                value: summary.timeInRange.map { String(format: "%.0f%%", $0) } ?? "—",
                                unit: "70-180 mg/dL",
                                color: tirColor(summary.timeInRange),
                                icon: "target"
                            )
                            SummaryCard(
                                title: "Avg Sleep",
                                value: summary.avgSleepHours.map {
                                    $0 > 24 ? "—" : String(format: "%.1fh", $0)
                                } ?? "—",
                                unit: "per night",
                                color: .indigo,
                                icon: "moon.zzz.fill"
                            )
                            SummaryCard(
                                title: "Exercise",
                                value: summary.totalExerciseMinutes.map { "\($0)m" } ?? "—",
                                unit: "last \(summary.periodDays ?? 7)d",
                                color: .green,
                                icon: "figure.run"
                            )
                        }

                        if !vm.sampledGlucoseRecords.isEmpty {
                            ChartCard(title: "Glucose (mg/dL)") {
                                Chart {
                                    ForEach(vm.sampledGlucoseRecords.sorted { $0.date < $1.date }) { r in
                                        LineMark(
                                            x: .value("Time", r.date),
                                            y: .value("mg/dL", r.value)
                                        )
                                        .foregroundStyle(.blue)
                                        .interpolationMethod(.catmullRom)
                                    }
                                    RuleMark(y: .value("Target Low", 70))
                                        .foregroundStyle(.green.opacity(0.6))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    RuleMark(y: .value("Target High", 180))
                                        .foregroundStyle(.orange.opacity(0.6))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                                .chartYScale(domain: 40...350)
                            }
                        }
                    } else if vm.isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }


                    if let error = vm.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .refreshable { await vm.sync() }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.sync() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isSyncing)
                }
                ToolbarItem(placement: .bottomBar) {
                    if let summary = vm.summary, let start = summary.dataStart, let end = summary.dataEnd {
                        Text("Data: \(shortDate(start)) – \(shortDate(end))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                if !auth.isGuest {
                    await HealthKitService.shared.syncAll()
                }
                await vm.loadAll()
                if vm.errorMessage == nil, let hkErr = HealthKitService.shared.errorMessage {
                    vm.errorMessage = hkErr
                }
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: String(iso.prefix(19))) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private func glucoseColor(_ val: Double?) -> Color {
        guard let v = val else { return .blue }
        return v < 70 ? .red : v > 180 ? .orange : .blue
    }

    private func tirColor(_ val: Double?) -> Color {
        guard let v = val else { return .teal }
        return v >= 70 ? .green : v >= 50 ? .orange : .red
    }
}

// MARK: - Subviews

struct SummaryCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
                .frame(height: 180)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - ViewModel

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var summary: DashboardSummary?
    @Published var glucoseRecords: [GlucoseRecord] = [] { didSet { _sampledGlucoseCache = nil } }
    private var _sampledGlucoseCache: [GlucoseRecord]?

    // Sampled to ≤500 points for chart rendering — avoids hanging on 37K+ duplicate records
    var sampledGlucoseRecords: [GlucoseRecord] {
        if let c = _sampledGlucoseCache { return c }
        let stride = max(1, glucoseRecords.count / 500)
        let result = stride == 1 ? glucoseRecords : glucoseRecords.enumerated()
            .filter { $0.offset % stride == 0 }.map { $0.element }
        _sampledGlucoseCache = result
        return result
    }
    @Published var sleepRecords: [SleepRecord] = [] { didSet { _dailySleepCache = nil } }
    private var _dailySleepCache: [(Date, Double)]?
    private var lastFetchDate: Date?
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var errorMessage: String?

    // Aggregated sleep: best (highest, capped at 14h) per calendar day.
    var dailySleepHours: [(Date, Double)] {
        if let c = _dailySleepCache { return c }
        var bests: [String: (Date, Double)] = [:]
        for r in sleepRecords {
            let clamped = min(r.durationHours, 14)
            guard clamped > 0 else { continue }
            let current = bests[r.date]?.1 ?? 0
            if clamped > current {
                bests[r.date] = (r.parsedDate, clamped)
            }
        }
        let result = bests.values.sorted { $0.0 < $1.0 }
        _dailySleepCache = result
        return result
    }

    func loadAll(force: Bool = false) async {
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 300 { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let s  = APIService.shared.fetchDashboard()
            async let g  = APIService.shared.fetchGlucose()
            async let sl = APIService.shared.fetchSleep()
            let (summary, glucose, sleep) = try await (s, g, sl)
            self.summary = summary
            self.glucoseRecords = glucose
            self.sleepRecords = sleep
            lastFetchDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync() async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        await HealthKitService.shared.forceSyncAll()
        if let hkErr = HealthKitService.shared.errorMessage {
            errorMessage = hkErr
        }
        await loadAll(force: true)
    }
}
