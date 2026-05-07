import Foundation
import Security

/// Handles sign-up, sign-in, and JWT token management via AWS Cognito.
/// Uses direct REST calls to the Cognito endpoint (no Amplify SDK dependency).
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isSignedIn: Bool = false
    @Published var isGuest: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let tokenKey    = "DiabetesHealth.idToken"
    private let refreshKey  = "DiabetesHealth.refreshToken"

    var idToken: String? { KeychainHelper.load(key: tokenKey) }
    var isAuthenticated: Bool { idToken != nil }

    private init() {
        isSignedIn = idToken != nil
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async throws {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }

        let url = cognitoURL()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.SignUp", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "ClientId": Config.cognitoClientID,
            "Username": email,
            "Password": password,
            "UserAttributes": [["Name": "email", "Value": email]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(data: data, response: response, context: "SignUp")
    }

    // MARK: - Confirm Sign Up

    func confirmSignUp(email: String, code: String) async throws {
        let url = cognitoURL()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.ConfirmSignUp", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "ClientId": Config.cognitoClientID,
            "Username": email,
            "ConfirmationCode": code
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(data: data, response: response, context: "ConfirmSignUp")
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }

        let url = cognitoURL()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": Config.cognitoClientID,
            "AuthParameters": ["USERNAME": email, "PASSWORD": password]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(data: data, response: response, context: "SignIn")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let result = json?["AuthenticationResult"] as? [String: Any],
            let idToken = result["IdToken"] as? String,
            let refreshToken = result["RefreshToken"] as? String
        else { throw AuthError.invalidResponse }

        KeychainHelper.save(key: tokenKey,   value: idToken)
        KeychainHelper.save(key: refreshKey, value: refreshToken)
        isSignedIn = true
    }

    // MARK: - Token Refresh

    func refreshTokens() async throws {
        guard let refreshToken = KeychainHelper.load(key: refreshKey) else {
            throw AuthError.serverError("No refresh token — please sign in again.")
        }

        let url = cognitoURL()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "ClientId": Config.cognitoClientID,
            "AuthParameters": ["REFRESH_TOKEN": refreshToken]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try assertHTTP200(data: data, response: response, context: "RefreshTokens")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let result = json?["AuthenticationResult"] as? [String: Any],
            let idToken = result["IdToken"] as? String
        else { throw AuthError.invalidResponse }

        KeychainHelper.save(key: tokenKey, value: idToken)
    }

    // MARK: - Guest

    func continueAsGuest() {
        isGuest = true
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.delete(key: tokenKey)
        KeychainHelper.delete(key: refreshKey)
        isSignedIn = false
        isGuest = false
    }

    // MARK: - Private helpers

    private func cognitoURL() -> URL {
        URL(string: "https://cognito-idp.\(Config.cognitoRegion).amazonaws.com/")!
    }

    private func assertHTTP200(data: Data, response: URLResponse, context: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw AuthError.serverError("\(context): \(msg)")
        }
    }
}

enum AuthError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:    return "Invalid server response"
        case .serverError(let m): return m
        }
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        SecItemDelete(query as CFDictionary)
    }
}
