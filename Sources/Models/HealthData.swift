import Foundation

// ISO8601 + fractional seconds + timezone  →  "2026-05-07T14:23:45.123456Z"
private let _isoFractionalFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
// ISO8601 + timezone, no fractional seconds  →  "2026-05-07T14:23:45Z"
private let _isoFormatter = ISO8601DateFormatter()
// ISO8601 no timezone, fractional seconds  →  "2026-05-07T14:23:45.123456" (Python isoformat() without tz)
private let _isoNoTZFractionalFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()
// ISO8601 no timezone  →  "2026-05-07T14:23:45"
private let _isoNoTZFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()
// MySQL DATETIME with microseconds  →  "2026-05-07 14:23:45.123456"
private let _mysqlFractionalFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()
// MySQL DATETIME  →  "2026-05-07 14:23:45"
private let _mysqlFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

private func parseHealthDate(_ string: String) -> Date {
    _isoFractionalFormatter.date(from: string)
        ?? _isoFormatter.date(from: string)
        ?? _isoNoTZFractionalFormatter.date(from: string)
        ?? _isoNoTZFormatter.date(from: string)
        ?? _mysqlFractionalFormatter.date(from: string)
        ?? _mysqlFormatter.date(from: string)
        ?? Date()
}

// MARK: - Glucose

struct GlucoseRecord: Codable, Identifiable {
    let id: Int
    let timestamp: String
    let value: Double
    let unit: String?

    var date: Date { parseHealthDate(timestamp) }
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

    var parsedDate: Date { SleepRecord.df.date(from: date) ?? Date() }
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
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

    var date: Date { parseHealthDate(timestamp) }
}

// MARK: - Dashboard Summary

struct DashboardSummary: Codable {
    let avgGlucose: Double?
    let timeInRange: Double?
    let avgSleepHours: Double?
    let totalExerciseMinutes: Int?
    let periodDays: Int?
    let dataStart: String?
    let dataEnd: String?

    enum CodingKeys: String, CodingKey {
        case avgGlucose           = "avg_glucose"
        case timeInRange          = "time_in_range"
        case avgSleepHours        = "avg_sleep_hours"
        case totalExerciseMinutes = "total_exercise_minutes"
        case periodDays           = "period_days"
        case dataStart            = "data_start"
        case dataEnd              = "data_end"
    }
}

// MARK: - AI Insight

struct AIInsight: Codable, Identifiable {
    let serverID: Int?
    let insightType: String
    let weekStart: String?
    let content: String
    let createdAt: String?

    // Always-unique ID for SwiftUI — avoids nil collision when serverID isn't present
    var id: String { serverID.map(String.init) ?? "\(insightType)-\(content.hashValue)" }

    enum CodingKeys: String, CodingKey {
        case serverID    = "id"
        case content
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
    let toolsUsed: [String]?
    let timestamp = Date()

    enum Role { case user, assistant }

    init(role: Role, content: String, toolsUsed: [String]? = nil) {
        self.role = role
        self.content = content
        self.toolsUsed = toolsUsed
    }
}

struct ChatRequest: Codable {
    let question: String
}

struct ChatResponse: Codable {
    let answer: String
    let status: String
    let toolsUsed: [String]?

    enum CodingKeys: String, CodingKey {
        case answer, status
        case toolsUsed = "tools_used"
    }
}

struct GenerateInsightsResponse: Codable {
    let status: String
    let generated: Int?
    let data: [AIInsight]
}

// MARK: - API response wrappers

struct ListResponse<T: Codable>: Codable {
    let status: String
    let total: Int?
    let data: [T]
}

struct SingleResponse<T: Codable>: Codable {
    let status: String
    let data: T
}

struct IngestResponse: Codable {
    let status: String
    let saved: Int?
    let message: String?
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
