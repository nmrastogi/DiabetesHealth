import Foundation

// MARK: - Glucose

struct GlucoseRecord: Codable, Identifiable {
    let id: Int
    let timestamp: String
    let value: Double
    let unit: String?

    var date: Date {
        ISO8601DateFormatter().date(from: timestamp) ?? Date()
    }
    var displayValue: String { String(format: "%.0f", value) }
}

// MARK: - Sleep

struct SleepRecord: Codable, Identifiable {
    let id: Int
    let date: String
    let bedtime: String?
    let wakeTime: String?
    let sleepDurationMinutes: Int?
    let deepSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let remSleepMinutes: Int?
    let sleepEfficiency: Double?

    enum CodingKeys: String, CodingKey {
        case id, date, bedtime
        case wakeTime            = "wake_time"
        case sleepDurationMinutes = "sleep_duration_minutes"
        case deepSleepMinutes    = "deep_sleep_minutes"
        case lightSleepMinutes   = "light_sleep_minutes"
        case remSleepMinutes     = "rem_sleep_minutes"
        case sleepEfficiency     = "sleep_efficiency"
    }

    var durationHours: Double { Double(sleepDurationMinutes ?? 0) / 60.0 }
}

// MARK: - Exercise

struct ExerciseRecord: Codable, Identifiable {
    let id: Int
    let timestamp: String
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case durationMinutes = "duration_minutes"
    }

    var date: Date {
        ISO8601DateFormatter().date(from: timestamp) ?? Date()
    }
}

// MARK: - Dashboard Summary

struct DashboardSummary: Codable {
    let avgGlucose: Double?
    let timeInRange: Double?         // percentage 70-180 mg/dL
    let avgSleepHours: Double?
    let totalExerciseMinutes: Int?
    let periodDays: Int

    enum CodingKeys: String, CodingKey {
        case avgGlucose         = "avg_glucose"
        case timeInRange        = "time_in_range"
        case avgSleepHours      = "avg_sleep_hours"
        case totalExerciseMinutes = "total_exercise_minutes"
        case periodDays         = "period_days"
    }
}

// MARK: - AI Insight

struct AIInsight: Codable, Identifiable {
    let id: Int
    let insightType: String
    let weekStart: String?
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, content
        case insightType = "insight_type"
        case weekStart   = "week_start"
        case createdAt   = "created_at"
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()

    enum Role { case user, assistant }
}

struct ChatRequest: Codable {
    let question: String
}

struct ChatResponse: Codable {
    let answer: String
    let status: String
}

// MARK: - API response wrappers

struct ListResponse<T: Codable>: Codable {
    let status: String
    let total: Int
    let data: [T]
}

struct SingleResponse<T: Codable>: Codable {
    let status: String
    let data: T
}

// MARK: - Ingest payloads (sent to backend from HealthKit)

struct GlucoseIngestPayload: Codable {
    struct MetricData: Codable {
        let date: String
        let qty: Double
        let unit: String
    }
    struct Metric: Codable {
        let name: String
        let data: [MetricData]
    }
    struct DataWrapper: Codable {
        let metrics: [Metric]
    }
    let data: DataWrapper
}

struct SleepIngestPayload: Codable {
    struct SleepItem: Codable {
        let date: String
        let inBedStart: String?
        let inBedEnd: String?
        let totalSleep: Double?
        let deep: Double?
        let core: Double?
        let rem: Double?
    }
    struct Metric: Codable {
        let name: String
        let data: [SleepItem]
    }
    struct DataWrapper: Codable {
        let metrics: [Metric]
    }
    let data: DataWrapper
}

struct ExerciseIngestPayload: Codable {
    struct Workout: Codable {
        let start: String
        let duration: Double?
        let workoutName: String?
    }
    struct DataWrapper: Codable {
        let workouts: [Workout]
    }
    let data: DataWrapper
}
