import Foundation

struct UserProfile: Codable, Identifiable {
    let id: Int
    let email: String
    let displayName: String?
    let timezone: String
    let syncToken: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, timezone
        case displayName = "display_name"
        case syncToken   = "sync_token"
        case createdAt   = "created_at"
    }
}
