import AppKit
import CryptoKit
import Foundation
import Network

public enum OAuthServiceError: LocalizedError {
    case invalidAuthorizeURL
    case invalidTokenURL
    case missingClientID
    case browserOpenFailed
    case callbackTimedOut
    case callbackServerFailed(String)
    case invalidCallbackRequest
    case stateMismatch
    case callbackReturnedError(String)
    case missingAuthorizationCode
    case tokenExchangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            return "OAuth authorize URL is invalid."
        case .invalidTokenURL:
            return "OAuth token URL is invalid."
        case .missingClientID:
            return "OAuth client_id is missing. Set CODEX_OAUTH_CLIENT_ID."
        case .browserOpenFailed:
            return "Unable to open browser for OAuth."
        case .callbackTimedOut:
            return "OAuth callback timed out."
        case .callbackServerFailed(let reason):
            return "OAuth callback server failed: \(reason)"
        case .invalidCallbackRequest:
            return "OAuth callback request was invalid."
        case .stateMismatch:
            return "OAuth callback state did not match request."
        case .callbackReturnedError(let details):
            return "OAuth provider returned an error: \(details)"
        case .missingAuthorizationCode:
            return "OAuth callback did not include an authorization code."
        case .tokenExchangeFailed(let details):
            return "OAuth token exchange failed: \(details)"
        }
    }
}

public protocol OAuthAdding: Sendable {
    func addAccountViaOAuth() async throws -> OAuthAccountInfo
}

public final class BrowserOAuthService: OAuthAdding, @unchecked Sendable {
    private struct TokenBundle: Sendable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let accountID: String?
    }

    private let receiver: OAuthCallbackReceiver
    private let authorizeBaseURL: String
    private let tokenURL: String
    private let clientID: String
    private let scope: String
    private let timeoutSeconds: TimeInterval

    public init(
        receiver: OAuthCallbackReceiver = OAuthCallbackReceiver(),
        authorizeBaseURL: String = ProcessInfo.processInfo.environment["CODEX_OAUTH_AUTHORIZE_URL"] ?? "https://auth.openai.com/oauth/authorize",
        tokenURL: String = ProcessInfo.processInfo.environment["CODEX_OAUTH_TOKEN_URL"] ?? "https://auth.openai.com/oauth/token",
        clientID: String = ProcessInfo.processInfo.environment["CODEX_OAUTH_CLIENT_ID"] ?? "app_EMoamEEZ73f0CkXaXp7hrann",
        scope: String = ProcessInfo.processInfo.environment["CODEX_OAUTH_SCOPE"] ?? "openid profile email offline_access api.connectors.read api.connectors.invoke",
        timeoutSeconds: TimeInterval = 180
    ) {
        self.receiver = receiver
        self.authorizeBaseURL = authorizeBaseURL
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.scope = scope
        self.timeoutSeconds = timeoutSeconds
    }

    public func addAccountViaOAuth() async throws -> OAuthAccountInfo {
        if ProcessInfo.processInfo.environment["CODEX_FAKE_OAUTH"] == "1" {
            return OAuthAccountInfo(
                email: "demo@example.com",
                workspaceName: "Demo Workspace",
                planType: "plus",
                authMode: .chatGPT,
                accessToken: UUID().uuidString,
                refreshToken: nil,
                idToken: nil,
                externalAccountID: nil,
                apiKey: nil,
                rawAuthJSON: nil
            )
        }

        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthServiceError.missingClientID
        }

        let state = UUID().uuidString
        let callbackURL = "http://localhost:1455/auth/callback"
        let codeVerifier = randomCodeVerifier()
        let codeChallenge = codeChallenge(for: codeVerifier)

        guard var components = URLComponents(string: authorizeBaseURL) else {
            throw OAuthServiceError.invalidAuthorizeURL
        }

        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: callbackURL),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs")
        ])

        if let prompt = ProcessInfo.processInfo.environment["CODEX_OAUTH_PROMPT"], !prompt.isEmpty {
            items.append(URLQueryItem(name: "prompt", value: prompt))
        }

        components.queryItems = items

        guard let oauthURL = components.url else {
            throw OAuthServiceError.invalidAuthorizeURL
        }

        let opened = NSWorkspace.shared.open(oauthURL)
        guard opened else {
            throw OAuthServiceError.browserOpenFailed
        }

        let callback = try await receiver.waitForCallback(expectedState: state, timeoutSeconds: timeoutSeconds)

        if let error = callback.queryItems["error"], !error.isEmpty {
            let description = callback.queryItems["error_description"] ?? error
            throw OAuthServiceError.callbackReturnedError(description)
        }

        if callback.queryItems["api_key"]?.isEmpty == false {
            return OAuthAccountInfo(
                email: callback.queryItems["email"],
                workspaceName: callback.queryItems["workspace_name"],
                planType: callback.queryItems["plan_type"],
                authMode: .apiKey,
                accessToken: nil,
                refreshToken: nil,
                idToken: nil,
                externalAccountID: nil,
                apiKey: callback.queryItems["api_key"],
                rawAuthJSON: nil
            )
        }

        guard let code = callback.queryItems["code"], !code.isEmpty else {
            throw OAuthServiceError.missingAuthorizationCode
        }

        let tokenBundle = try await exchangeCodeForTokens(
            code: code,
            codeVerifier: codeVerifier,
            callbackURL: callbackURL
        )

        let claims = decodedJWTClaims(from: tokenBundle.idToken)
            ?? decodedJWTClaims(from: tokenBundle.accessToken)

        let email = profileEmail(from: claims)
        let planType = profilePlanType(from: claims)
        let workspaceName = profileWorkspaceName(from: claims)
        let externalAccountID = tokenBundle.accountID ?? profileAccountID(from: claims)

        return OAuthAccountInfo(
            email: email,
            workspaceName: workspaceName,
            planType: planType,
            authMode: .chatGPT,
            accessToken: tokenBundle.accessToken,
            refreshToken: tokenBundle.refreshToken,
            idToken: tokenBundle.idToken,
            externalAccountID: externalAccountID,
            apiKey: nil,
            rawAuthJSON: makeRawAuthJSON(from: tokenBundle, refreshedAt: Date())
        )
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String, callbackURL: String) async throws -> TokenBundle {
        guard let endpoint = URL(string: tokenURL) else {
            throw OAuthServiceError.invalidTokenURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = formURLEncoded([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("redirect_uri", callbackURL),
            ("code_verifier", codeVerifier)
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthServiceError.tokenExchangeFailed("non-http response")
        }

        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if !(200...299).contains(httpResponse.statusCode) {
            let errorDescription = payload?["error_description"] as? String
                ?? payload?["error"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "status=\(httpResponse.statusCode)"
            throw OAuthServiceError.tokenExchangeFailed(errorDescription)
        }

        guard let payload else {
            throw OAuthServiceError.tokenExchangeFailed("invalid json response")
        }

        guard let accessToken = payload["access_token"] as? String, !accessToken.isEmpty else {
            throw OAuthServiceError.tokenExchangeFailed("missing access_token")
        }

        return TokenBundle(
            accessToken: accessToken,
            refreshToken: payload["refresh_token"] as? String,
            idToken: payload["id_token"] as? String,
            accountID: payload["account_id"] as? String
        )
    }

    private func formURLEncoded(_ items: [(String, String)]) -> String {
        items
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;="))) ?? value
    }

    private func randomCodeVerifier(length: Int = 64) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            alphabet[Int.random(in: 0..<alphabet.count, using: &generator)]
        })
    }

    private func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodedJWTClaims(from token: String?) -> [String: Any]? {
        guard let token else {
            return nil
        }

        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        guard let payloadData = base64URLDecode(String(parts[1])) else {
            return nil
        }

        return (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any]
    }

    private func base64URLDecode(_ base64URL: String) -> Data? {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: base64)
    }

    private func profileEmail(from claims: [String: Any]?) -> String? {
        if let email = claims?["email"] as? String, !email.isEmpty {
            return email
        }

        if let profile = claims?["https://api.openai.com/profile"] as? [String: Any],
           let email = profile["email"] as? String,
           !email.isEmpty {
            return email
        }

        return nil
    }

    private func profilePlanType(from claims: [String: Any]?) -> String? {
        guard let auth = claims?["https://api.openai.com/auth"] as? [String: Any] else {
            return nil
        }

        return auth["chatgpt_plan_type"] as? String
    }

    static func extractWorkspaceIdentifier(from claims: [String: Any]?) -> String? {
        guard
            let auth = claims?["https://api.openai.com/auth"] as? [String: Any],
            let organizations = auth["organizations"] as? [[String: Any]],
            !organizations.isEmpty
        else {
            return nil
        }

        if
            let defaultOrg = organizations.first(where: { ($0["is_default"] as? Bool) == true }),
            let id = extractOrganizationID(from: defaultOrg)
        {
            return id
        }

        for organization in organizations {
            if let id = extractOrganizationID(from: organization) {
                return id
            }
        }

        return nil
    }

    private func profileWorkspaceName(from claims: [String: Any]?) -> String? {
        Self.extractWorkspaceIdentifier(from: claims)
    }

    private static func extractOrganizationID(from organization: [String: Any]) -> String? {
        for key in ["id", "organization_id", "workspace_id"] {
            if
                let id = organization[key] as? String,
                !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return id
            }
        }

        return nil
    }

    private func profileAccountID(from claims: [String: Any]?) -> String? {
        guard let auth = claims?["https://api.openai.com/auth"] as? [String: Any] else {
            return nil
        }

        return auth["chatgpt_account_id"] as? String ?? auth["account_id"] as? String
    }

    private func makeRawAuthJSON(from bundle: TokenBundle, refreshedAt: Date) -> String? {
        var tokens: [String: String] = ["access_token": bundle.accessToken]
        if let refreshToken = bundle.refreshToken, !refreshToken.isEmpty {
            tokens["refresh_token"] = refreshToken
        }
        if let idToken = bundle.idToken, !idToken.isEmpty {
            tokens["id_token"] = idToken
        }
        if let accountID = bundle.accountID, !accountID.isEmpty {
            tokens["account_id"] = accountID
        }

        let payload: [String: Any] = [
            "tokens": tokens,
            "last_refresh": iso8601UTC(refreshedAt)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func iso8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

public struct OAuthCallbackResult: Sendable {
    public var queryItems: [String: String]

    public init(queryItems: [String: String]) {
        self.queryItems = queryItems
    }
}

public actor OAuthCallbackReceiver {
    private let queue = DispatchQueue(label: "codex.oauth.callback", qos: .userInitiated)
    private var listener: NWListener?
    private var continuation: CheckedContinuation<OAuthCallbackResult, Error>?
    private var expectedState: String = ""
    private var resolved = false

    public init() {}

    public func waitForCallback(expectedState: String, timeoutSeconds: TimeInterval) async throws -> OAuthCallbackResult {
        self.expectedState = expectedState
        self.resolved = false

        do {
            try startListener()
        } catch {
            throw OAuthServiceError.callbackServerFailed(error.localizedDescription)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                Task {
                    await self?.resolve(with: .failure(OAuthServiceError.callbackTimedOut))
                }
            }
        }
    }

    private func startListener() throws {
        let listener = try NWListener(using: .tcp, on: 1455)
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                Task {
                    await self.handleIncoming(connection: connection, data: data)
                }
            }
        }

        listener.stateUpdateHandler = { state in
            guard case .failed(let error) = state else {
                return
            }
            Task {
                await self.resolve(with: .failure(OAuthServiceError.callbackServerFailed(error.localizedDescription)))
            }
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    private func handleIncoming(connection: NWConnection, data: Data?) async {
        defer {
            connection.cancel()
        }

        guard
            let data,
            let request = String(data: data, encoding: .utf8),
            let firstLine = request.split(separator: "\r\n").first,
            let path = firstLine.split(separator: " ").dropFirst().first
        else {
            sendHTTPResponse(to: connection, statusCode: 400, body: "Invalid callback request")
            resolve(with: .failure(OAuthServiceError.invalidCallbackRequest))
            return
        }

        guard let components = URLComponents(string: "http://127.0.0.1\(path)") else {
            sendHTTPResponse(to: connection, statusCode: 400, body: "Invalid callback URL")
            resolve(with: .failure(OAuthServiceError.invalidCallbackRequest))
            return
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        if let callbackState = queryItems["state"], callbackState != expectedState {
            sendHTTPResponse(to: connection, statusCode: 400, body: "State mismatch")
            resolve(with: .failure(OAuthServiceError.stateMismatch))
            return
        }

        if queryItems["error"] != nil {
            sendHTTPResponse(to: connection, statusCode: 400, body: "OAuth failed. You can close this tab.")
            resolve(with: .success(OAuthCallbackResult(queryItems: queryItems)))
            return
        }

        let hasCode = !(queryItems["code"] ?? "").isEmpty
        let hasAccessToken = !(queryItems["access_token"] ?? "").isEmpty
        let hasAPIKey = !(queryItems["api_key"] ?? "").isEmpty

        guard hasCode || hasAccessToken || hasAPIKey else {
            sendHTTPResponse(to: connection, statusCode: 400, body: "OAuth callback missing required fields")
            resolve(with: .failure(OAuthServiceError.invalidCallbackRequest))
            return
        }

        sendHTTPResponse(to: connection, statusCode: 200, body: "OAuth complete. You can close this tab.")
        resolve(with: .success(OAuthCallbackResult(queryItems: queryItems)))
    }

    private func sendHTTPResponse(to connection: NWConnection, statusCode: Int, body: String) {
        let payload = """
        HTTP/1.1 \(statusCode) OK\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
    }

    private func resolve(with result: Result<OAuthCallbackResult, Error>) {
        guard !resolved else {
            return
        }
        resolved = true

        listener?.cancel()
        listener = nil

        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
