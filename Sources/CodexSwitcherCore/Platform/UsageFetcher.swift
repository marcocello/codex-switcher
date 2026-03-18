import Foundation

public struct UsageFetchResult: Sendable {
    public var usage: UsageSnapshot
    public var updatedCredential: AuthCredential?

    public init(usage: UsageSnapshot, updatedCredential: AuthCredential? = nil) {
        self.usage = usage
        self.updatedCredential = updatedCredential
    }
}

public protocol UsageFetching: Sendable {
    func fetchUsage(for account: Account, credential: AuthCredential) async -> UsageFetchResult
}

public struct DefaultUsageFetcher: UsageFetching {
    private enum RefreshFailure: Error {
        case message(String)

        var userMessage: String {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    private struct OAuthRefreshRequest: Encodable {
        var clientID: String
        var grantType: String
        var refreshToken: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case grantType = "grant_type"
            case refreshToken = "refresh_token"
        }
    }

    private struct RateLimitStatusPayload: Decodable {
        var planType: String?
        var rateLimit: RateLimitDetails?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }
    }

    private struct RateLimitDetails: Decodable {
        var primaryWindow: RateLimitWindow?
        var secondaryWindow: RateLimitWindow?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct RateLimitWindow: Decodable {
        var usedPercent: Double
        var resetAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
        }
    }

    private struct OAuthRefreshPayload: Decodable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case accountID = "account_id"
        }
    }

    private let load: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let now: @Sendable () -> Date
    private let oauthTokenURL: String
    private let oauthClientID: String

    public init(
        load: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        },
        now: @escaping @Sendable () -> Date = Date.init,
        oauthTokenURL: String = ProcessInfo.processInfo.environment["CODEX_REFRESH_TOKEN_URL_OVERRIDE"]
            ?? ProcessInfo.processInfo.environment["CODEX_OAUTH_TOKEN_URL"]
            ?? "https://auth.openai.com/oauth/token",
        oauthClientID: String = ProcessInfo.processInfo.environment["CODEX_OAUTH_CLIENT_ID"] ?? "app_EMoamEEZ73f0CkXaXp7hrann"
    ) {
        self.load = load
        self.now = now
        self.oauthTokenURL = oauthTokenURL
        self.oauthClientID = oauthClientID
    }

    public func fetchUsage(for account: Account, credential: AuthCredential) async -> UsageFetchResult {
        if credential.authMode == .apiKey {
            return UsageFetchResult(
                usage: errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: "Usage info not available for API key accounts"
                )
            )
        }

        guard
            let accessToken = credential.accessToken,
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return UsageFetchResult(
                usage: errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: "Missing OAuth access token"
                )
            )
        }

        guard let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return UsageFetchResult(
                usage: errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: "Usage endpoint URL is invalid"
                )
            )
        }

        do {
            let (data, response) = try await load(
                usageRequest(
                    usageURL: usageURL,
                    accessToken: accessToken,
                    externalAccountID: credential.externalAccountID
                )
            )

            if response.statusCode == 401 {
                return await refreshThenRetryUsage(
                    account: account,
                    credential: credential,
                    usageURL: usageURL
                )
            }

            guard (200...299).contains(response.statusCode) else {
                return UsageFetchResult(
                    usage: errorUsage(
                        accountID: account.id,
                        planType: account.planType,
                        error: "Usage API error: HTTP \(response.statusCode)"
                    )
                )
            }

            let payload = try JSONDecoder().decode(RateLimitStatusPayload.self, from: data)
            return UsageFetchResult(
                usage: mapPayload(payload, accountID: account.id, fallbackPlanType: account.planType)
            )
        } catch {
            return UsageFetchResult(
                usage: errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: "Usage fetch failed: \(error.localizedDescription)"
                )
            )
        }
    }

    private func refreshThenRetryUsage(account: Account, credential: AuthCredential, usageURL: URL) async -> UsageFetchResult {
        guard
            let refreshToken = credential.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            !refreshToken.isEmpty
        else {
            return UsageFetchResult(
                usage: errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: "Usage API error: HTTP 401"
                )
            )
        }

        do {
            let refreshedCredential = try await refreshCredential(credential: credential, refreshToken: refreshToken)
            guard
                let refreshedAccessToken = refreshedCredential.accessToken,
                !refreshedAccessToken.isEmpty
            else {
                return UsageFetchResult(
                    usage: errorUsage(
                        accountID: account.id,
                        planType: account.planType,
                        error: "Usage API error: HTTP 401"
                    )
                )
            }

            let (retryData, retryResponse) = try await load(
                usageRequest(
                    usageURL: usageURL,
                    accessToken: refreshedAccessToken,
                    externalAccountID: refreshedCredential.externalAccountID
                )
            )

            guard (200...299).contains(retryResponse.statusCode) else {
                return UsageFetchResult(
                    usage: errorUsage(
                        accountID: account.id,
                        planType: account.planType,
                        error: "Usage API error: HTTP \(retryResponse.statusCode)"
                    ),
                    updatedCredential: refreshedCredential
                )
            }

            let payload = try JSONDecoder().decode(RateLimitStatusPayload.self, from: retryData)
            return UsageFetchResult(
                usage: mapPayload(payload, accountID: account.id, fallbackPlanType: account.planType),
                updatedCredential: refreshedCredential
            )
        } catch {
            return UsageFetchResult(
                usage: errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: (error as? RefreshFailure)?.userMessage ?? "Usage API error: HTTP 401 (token refresh failed)"
                )
            )
        }
    }

    private func refreshCredential(credential: AuthCredential, refreshToken: String) async throws -> AuthCredential {
        guard let tokenEndpoint = URL(string: oauthTokenURL) else {
            throw RefreshFailure.message("Usage API token refresh failed: invalid token endpoint URL")
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("codex-cli/1.0.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            OAuthRefreshRequest(
                clientID: oauthClientID,
                grantType: "refresh_token",
                refreshToken: refreshToken
            )
        )

        let (data, response) = try await load(request)
        guard (200...299).contains(response.statusCode) else {
            throw refreshFailure(forStatusCode: response.statusCode, body: data)
        }

        let payload = try JSONDecoder().decode(OAuthRefreshPayload.self, from: data)
        guard !payload.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RefreshFailure.message("Usage API token refresh failed: missing access token in response")
        }

        var updated = credential
        updated.accessToken = payload.accessToken
        if let nextRefreshToken = payload.refreshToken, !nextRefreshToken.isEmpty {
            updated.refreshToken = nextRefreshToken
        }
        if let nextIDToken = payload.idToken, !nextIDToken.isEmpty {
            updated.idToken = nextIDToken
        }
        if let accountID = payload.accountID, !accountID.isEmpty {
            updated.externalAccountID = accountID
        }
        updated.refreshedAt = now()
        return updated
    }

    private func refreshFailure(forStatusCode statusCode: Int, body: Data) -> RefreshFailure {
        let bodyText = String(data: body, encoding: .utf8) ?? ""
        if statusCode == 401 {
            let code = extractRefreshErrorCode(from: bodyText)?.lowercased()
            switch code {
            case "refresh_token_expired":
                return .message("Usage unavailable: refresh token expired. Re-add this account.")
            case "refresh_token_reused":
                return .message("Usage unavailable: refresh token already used. Re-add this account.")
            case "refresh_token_invalidated":
                return .message("Usage unavailable: refresh token revoked. Re-add this account.")
            default:
                return .message("Usage unavailable: token refresh unauthorized. Re-add this account.")
            }
        }

        let details = extractRefreshErrorCode(from: bodyText) ?? bodyText
        if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .message("Usage API token refresh failed: HTTP \(statusCode)")
        }
        return .message("Usage API token refresh failed: HTTP \(statusCode) (\(details))")
    }

    private func extractRefreshErrorCode(from body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }

        if let errorObject = root["error"] as? [String: Any], let code = errorObject["code"] as? String {
            return code
        }

        if let errorCode = root["error"] as? String {
            return errorCode
        }

        if let code = root["code"] as? String {
            return code
        }

        return nil
    }

    private func usageRequest(usageURL: URL, accessToken: String, externalAccountID: String?) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("codex-cli/1.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let externalAccountID, !externalAccountID.isEmpty {
            request.setValue(externalAccountID, forHTTPHeaderField: "chatgpt-account-id")
        }
        return request
    }

    private func mapPayload(_ payload: RateLimitStatusPayload, accountID: String, fallbackPlanType: String?) -> UsageSnapshot {
        let baseline = UsageSnapshot.empty(accountID: accountID, planType: payload.planType ?? fallbackPlanType)
        let primary = payload.rateLimit?.primaryWindow
        let secondary = payload.rateLimit?.secondaryWindow

        return UsageSnapshot(
            accountID: accountID,
            primaryUsedPercent: clamp(primary?.usedPercent ?? 0),
            primaryResetsAt: date(fromUnixSeconds: primary?.resetAt) ?? baseline.primaryResetsAt,
            secondaryUsedPercent: clamp(secondary?.usedPercent ?? 0),
            secondaryResetsAt: date(fromUnixSeconds: secondary?.resetAt) ?? baseline.secondaryResetsAt,
            planType: payload.planType ?? fallbackPlanType,
            error: nil
        )
    }

    private func errorUsage(accountID: String, planType: String?, error: String) -> UsageSnapshot {
        let baseline = UsageSnapshot.empty(accountID: accountID, planType: planType)
        return UsageSnapshot(
            accountID: accountID,
            primaryUsedPercent: baseline.primaryUsedPercent,
            primaryResetsAt: baseline.primaryResetsAt,
            secondaryUsedPercent: baseline.secondaryUsedPercent,
            secondaryResetsAt: baseline.secondaryResetsAt,
            planType: planType,
            error: error
        )
    }

    private func date(fromUnixSeconds timestamp: Int64?) -> Date? {
        guard let timestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
