import Foundation
import HealthKit

/// Requests HealthKit authorization, reads glucose / sleep / exercise data,
/// and POSTs it to the backend via APIService.
@MainActor
class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let glucose = HKObjectType.quantityType(forIdentifier: .bloodGlucose) { types.insert(glucose) }
        if let sleep   = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Full sync

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            async let glucose  = syncGlucose()
            async let sleep    = syncSleep()
            async let exercise = syncExercise()
            _ = try await (glucose, sleep, exercise)
            lastSyncDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Glucose

    private func syncGlucose() async throws {
        let type = HKQuantityType(.bloodGlucose)
        let unit = HKUnit(from: "mg/dL")
        let samples = try await fetchSamples(type: type, days: Config.healthSyncDays)

        let metrics = samples.map { s -> GlucoseIngestPayload.MetricData in
            GlucoseIngestPayload.MetricData(
                date: iso(s.startDate),
                qty: s.quantity.doubleValue(for: unit),
                unit: "mg/dL"
            )
        }
        guard !metrics.isEmpty else { return }
        let payload = GlucoseIngestPayload(
            data: .init(metrics: [.init(name: "blood_glucose", data: metrics)])
        )
        try await APIService.shared.ingestGlucose(payload)
    }

    // MARK: - Sleep

    private func syncSleep() async throws {
        let type = HKCategoryType(.sleepAnalysis)
        let samples = try await fetchCategorySamples(type: type, days: Config.healthSyncDays)

        // Group samples by calendar date (night of sleep)
        let cal = Calendar.current
        var grouped: [String: [HKCategorySample]] = [:]
        for s in samples {
            let key = dateString(s.startDate)
            grouped[key, default: []].append(s)
        }

        let items: [SleepIngestPayload.SleepItem] = grouped.map { (date, group) in
            let start = group.map(\.startDate).min()
            let end   = group.map(\.endDate).max()
            let totalMins = group.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60.0

            var deep: Double = 0; var core: Double = 0; var rem: Double = 0
            for s in group {
                let mins = s.endDate.timeIntervalSince(s.startDate) / 60.0
                switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
                case .asleepDeep:  deep += mins
                case .asleepCore:  core += mins
                case .asleepREM:   rem  += mins
                default: break
                }
            }
            return SleepIngestPayload.SleepItem(
                date: date,
                inBedStart: start.map(iso),
                inBedEnd: end.map(iso),
                totalSleep: totalMins,
                deep: deep > 0 ? deep : nil,
                core: core > 0 ? core : nil,
                rem: rem  > 0 ? rem  : nil
            )
        }
        guard !items.isEmpty else { return }
        let payload = SleepIngestPayload(
            data: .init(metrics: [.init(name: "sleep_analysis", data: items)])
        )
        try await APIService.shared.ingestSleep(payload)
    }

    // MARK: - Exercise

    private func syncExercise() async throws {
        let anchor = Calendar.current.date(byAdding: .day, value: -Config.healthSyncDays, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date())

        let workouts = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkout], Error>) in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        let items = workouts.map { w in
            ExerciseIngestPayload.Workout(
                start: iso(w.startDate),
                duration: w.duration / 60.0,
                workoutName: w.workoutActivityType.name
            )
        }
        guard !items.isEmpty else { return }
        let payload = ExerciseIngestPayload(data: .init(workouts: items))
        try await APIService.shared.ingestExercise(payload)
    }

    // MARK: - HK query helpers

    private func fetchSamples(type: HKQuantityType, days: Int) async throws -> [HKQuantitySample] {
        let anchor = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date())
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, days: Int) async throws -> [HKCategorySample] {
        let anchor = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: Date())
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - Date helpers

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - HKWorkoutActivityType name

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running:      return "Running"
        case .cycling:      return "Cycling"
        case .walking:      return "Walking"
        case .swimming:     return "Swimming"
        case .yoga:         return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        default:            return "Workout"
        }
    }
}
