import Foundation

enum Config {
    // MARK: - Backend API
    // Update this to your deployed backend URL
    static let apiBaseURL = "http://localhost:5001"  // dev; change to https://api.yourapp.com in prod

    // MARK: - AWS Cognito
    static let cognitoUserPoolID    = "us-west-2_XXXXXXXXX"   // replace after Cognito setup
    static let cognitoClientID      = "XXXXXXXXXXXXXXXXXXXXXXXXXX" // replace after Cognito setup
    static let cognitoRegion        = "us-west-2"

    // MARK: - HealthKit sync
    static let healthSyncDays = 30      // how many days back to sync on first launch
}
