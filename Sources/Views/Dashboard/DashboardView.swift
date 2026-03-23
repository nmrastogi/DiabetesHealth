import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()

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
                                value: summary.avgSleepHours.map { String(format: "%.1fh", $0) } ?? "—",
                                unit: "per night",
                                color: .indigo,
                                icon: "moon.zzz.fill"
                            )
                            SummaryCard(
                                title: "Exercise",
                                value: summary.totalExerciseMinutes.map { "\($0)m" } ?? "—",
                                unit: "last \(summary.periodDays)d",
                                color: .green,
                                icon: "figure.run"
                            )
                        }
                    } else if vm.isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }

                    // Glucose chart
                    if !vm.glucoseRecords.isEmpty {
                        ChartCard(title: "Glucose (7 days)") {
                            Chart(vm.glucoseRecords) { record in
                                LineMark(
                                    x: .value("Time", record.date),
                                    y: .value("mg/dL", record.value)
                                )
                                .foregroundStyle(.blue)
                                PointMark(
                                    x: .value("Time", record.date),
                                    y: .value("mg/dL", record.value)
                                )
                                .foregroundStyle(.blue)
                            }
                            .chartYScale(domain: 60...300)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                                }
                            }
                            // Target range band
                            .chartBackground { proxy in
                                GeometryReader { geo in
                                    if let minY = proxy.position(forY: 180),
                                       let maxY = proxy.position(forY: 70) {
                                        Rectangle()
                                            .fill(Color.green.opacity(0.08))
                                            .frame(height: maxY - minY)
                                            .offset(y: minY)
                                    }
                                }
                            }
                        }
                    }

                    // Sleep chart
                    if !vm.sleepRecords.isEmpty {
                        ChartCard(title: "Sleep (7 days)") {
                            Chart(vm.sleepRecords) { record in
                                BarMark(
                                    x: .value("Date", record.date),
                                    y: .value("Hours", record.durationHours)
                                )
                                .foregroundStyle(record.durationHours >= 7 ? Color.indigo : Color.orange)
                                .cornerRadius(4)
                            }
                            .chartYScale(domain: 0...12)
                            .chartXAxis {
                                AxisMarks { _ in
                                    AxisValueLabel()
                                }
                            }
                        }
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
            }
            .task { await vm.loadAll() }
        }
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
    @Published var glucoseRecords: [GlucoseRecord] = []
    @Published var sleepRecords: [SleepRecord] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var errorMessage: String?

    func loadAll() async {
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        await HealthKitService.shared.syncAll()
        await loadAll()
    }
}
