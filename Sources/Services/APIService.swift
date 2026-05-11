import Foundation

/// Central API client. All requests attach the Cognito ID token as Bearer auth.
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Dashboard

    func fetchDashboard(days: Int = 7) async throws -> DashboardSummary {
        try await get("/dashboard?days=\(days)")
    }

    // MARK: - Glucose

    func fetchGlucose(days: Int = 7) async throws -> [GlucoseRecord] {
        let resp: ListResponse<GlucoseRecord> = try await get("/glucose?days=\(days)")
        return resp.data
    }

    func ingestGlucose(_ payload: GlucoseIngestPayload) async throws {
        do { let _: IngestResponse = try await post("/glucose/ingest", body: payload) }
        catch APIError.serverError(500, _) { /* IntegrityError: records already exist — non-fatal */ }
    }

    // MARK: - Sleep

    func fetchSleep(days: Int = 7) async throws -> [SleepRecord] {
        let resp: ListResponse<SleepRecord> = try await get("/sleep?days=\(days)")
        return resp.data
    }

    func ingestSleep(_ payload: SleepIngestPayload) async throws {
        do { let _: IngestResponse = try await post("/sleep/ingest", body: payload) }
        catch APIError.serverError(500, _) { /* IntegrityError: records already exist — non-fatal */ }
    }

    // MARK: - Exercise

    func fetchExercise(days: Int = 7) async throws -> [ExerciseRecord] {
        let resp: ListResponse<ExerciseRecord> = try await get("/exercise?days=\(days)")
        return resp.data
    }

    func ingestExercise(_ payload: ExerciseIngestPayload) async throws {
        do { let _: IngestResponse = try await post("/exercise/ingest", body: payload) }
        catch APIError.serverError(500, _) { /* IntegrityError: records already exist — non-fatal */ }
    }

    // MARK: - AI Insights

    func fetchInsights() async throws -> [AIInsight] {
        let resp: ListResponse<AIInsight> = try await get("/insights")
        return resp.data
    }

    // MARK: - Chat

    func sendChat(question: String, history: [[String: String]] = []) async throws -> ChatResponse {
        struct Body: Encodable { let question: String; let history: [[String: String]] }
        return try await post("/chat", body: Body(question: question, history: history))
    }

    // MARK: - Generate Insights

    func generateInsights() async throws -> GenerateInsightsResponse {
        struct EmptyBody: Encodable {}
        return try await post("/insights/generate", body: EmptyBody())
    }

    // MARK: - Generic helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: Config.apiBaseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        try attachAuth(&req)
        return try await execute(req)
    }

    @discardableResult
    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let url = URL(string: Config.apiBaseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        try attachAuth(&req)
        return try await execute(req)
    }

    private func attachAuth(_ req: inout URLRequest) throws {
        guard let token = AuthService.shared.idToken else {
            throw APIError.unauthenticated
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func execute<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            // Token expired — refresh and retry once
            do {
                try await AuthService.shared.refreshTokens()
            } catch {
                await AuthService.shared.signOut()
                throw APIError.unauthenticated
            }
            var retried = req
            try attachAuth(&retried)
            let (data2, response2) = try await URLSession.shared.data(for: retried)
            guard let http2 = response2 as? HTTPURLResponse, (200...299).contains(http2.statusCode) else {
                await AuthService.shared.signOut()
                throw APIError.unauthenticated
            }
            return try JSONDecoder().decode(T.self, from: data2) // retried after token refresh
        }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
            throw APIError.serverError(http.statusCode, message ?? "Unknown error")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodeError as DecodingError {
            let detail: String
            switch decodeError {
            case .keyNotFound(let key, _):   detail = "missing field '\(key.stringValue)'"
            case .typeMismatch(_, let ctx):  detail = "type mismatch at '\(ctx.codingPath.map(\.stringValue).joined(separator: "."))'"
            case .valueNotFound(_, let ctx): detail = "null value at '\(ctx.codingPath.map(\.stringValue).joined(separator: "."))'"
            default:                         detail = decodeError.localizedDescription
            }
            throw APIError.serverError(0, "Decode error: \(detail)")
        }
    }
}

enum APIError: LocalizedError {
    case unauthenticated
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:           return "Please sign in again."
        case .invalidResponse:           return "Invalid server response."
        case .serverError(let code, let msg): return "Error \(code): \(msg)"
        }
    }
}
