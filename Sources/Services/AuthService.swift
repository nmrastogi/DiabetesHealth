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
    private let accessKey   = "DiabetesHealth.accessToken"

    var idToken: String? { KeychainHelper.load(key: tokenKey) }
    var isAuthenticated: Bool { idToken != nil }

    // Decoded from the Cognito ID token JWT payload — no extra API call needed
    var userEmail: String? {
        guard let token = idToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else { return nil }
        return email
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

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

        let (data, response) = try await Self.session.data(for: req)
        try assertHTTP200(data: data, response: response)
    }

    // MARK: - Confirm Sign Up

    func confirmSignUp(email: String, code: String) async throws {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }

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

        let (data, response) = try await Self.session.data(for: req)
        try assertHTTP200(data: data, response: response)
    }

    // MARK: - Resend Confirmation Code

    func resendConfirmationCode(email: String) async throws {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }

        let url = cognitoURL()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.ResendConfirmationCode", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "ClientId": Config.cognitoClientID,
            "Username": email
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: req)
        try assertHTTP200(data: data, response: response)
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

        let (data, response) = try await Self.session.data(for: req)
        try assertHTTP200(data: data, response: response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let result = json?["AuthenticationResult"] as? [String: Any],
            let idToken = result["IdToken"] as? String,
            let refreshToken = result["RefreshToken"] as? String
        else { throw AuthError.message("Sign-in failed. Please try again.") }

        KeychainHelper.save(key: tokenKey,   value: idToken)
        KeychainHelper.save(key: refreshKey, value: refreshToken)
        if let accessToken = result["AccessToken"] as? String {
            KeychainHelper.save(key: accessKey, value: accessToken)
        }
        isSignedIn = true
    }

    // MARK: - Token Refresh

    func refreshTokens() async throws {
        guard let refreshToken = KeychainHelper.load(key: refreshKey) else {
            throw AuthError.message("Session expired. Please sign in again.")
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

        let (data, response) = try await Self.session.data(for: req)
        try assertHTTP200(data: data, response: response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let result = json?["AuthenticationResult"] as? [String: Any],
            let idToken = result["IdToken"] as? String
        else { throw AuthError.message("Session expired. Please sign in again.") }

        KeychainHelper.save(key: tokenKey, value: idToken)
        if let accessToken = result["AccessToken"] as? String {
            KeychainHelper.save(key: accessKey, value: accessToken)
        }
    }

    // MARK: - Change Password

    func changePassword(current: String, new: String) async throws {
        guard let accessToken = KeychainHelper.load(key: accessKey) else {
            throw AuthError.message("Session expired. Please sign out and sign back in.")
        }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }

        let url = cognitoURL()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        req.setValue("AWSCognitoIdentityProviderService.ChangePassword", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "AccessToken":      accessToken,
            "PreviousPassword": current,
            "ProposedPassword": new
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: req)
        try assertHTTP200(data: data, response: response)
    }

    // MARK: - Guest

    func continueAsGuest() {
        isGuest = true
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.delete(key: tokenKey)
        KeychainHelper.delete(key: refreshKey)
        KeychainHelper.delete(key: accessKey)
        isSignedIn = false
        isGuest = false
        HealthKitService.shared.resetAuthState()
    }

    // MARK: - Private helpers

    private func cognitoURL() -> URL {
        URL(string: "https://cognito-idp.\(Config.cognitoRegion).amazonaws.com/")!
    }

    private func assertHTTP200(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let type = json?["__type"] as? String ?? ""
            let rawMsg = json?["message"] as? String ?? "Unknown error"
            throw AuthError.message(userFacingMessage(cognitoType: type, fallback: rawMsg))
        }
    }

    private func userFacingMessage(cognitoType: String, fallback: String) -> String {
        switch cognitoType {
        case "NotAuthorizedException":
            return "Incorrect email or password."
        case "UserNotFoundException":
            return "No account found with this email."
        case "UserNotConfirmedException":
            return "Please verify your email first. Check your inbox for a confirmation code."
        case "CodeMismatchException":
            return "Invalid verification code. Please check and try again."
        case "ExpiredCodeException":
            return "That code has expired. Please request a new one."
        case "TooManyRequestsException", "LimitExceededException":
            return "Too many attempts. Please wait a few minutes and try again."
        case "InvalidPasswordException":
            return "Password must be at least 8 characters and include a number and symbol."
        case "UsernameExistsException":
            return "An account with this email already exists."
        case "InvalidParameterException":
            return "Please check your email and password and try again."
        default:
            return fallback
        }
    }
}

enum AuthError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
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
