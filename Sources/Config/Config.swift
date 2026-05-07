import Foundation

enum Config {
    // MARK: - AWS Cognito (non-secret)
    static let cognitoRegion = "us-west-2"

    // MARK: - HealthKit sync
    static let healthSyncDays = 14

    // Secrets (apiBaseURL, cognitoUserPoolID, cognitoClientID) are in
    // Config.private.swift — gitignored, never committed.
    // Copy Config.private.swift.template → Config.private.swift and fill in your values.
}
