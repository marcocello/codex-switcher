import Foundation

public protocol UsageFetching: Sendable {
    func fetchUsage(for account: Account, credential: AuthCredential) async -> UsageSnapshot
}

public struct DefaultUsageFetcher: UsageFetching {
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

    private let load: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let now: @Sendable () -> Date

    public init(
        load: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.load = load
        self.now = now
    }

    public func fetchUsage(for account: Account, credential: AuthCredential) async -> UsageSnapshot {
        if credential.authMode == .apiKey {
            return errorUsage(
                accountID: account.id,
                planType: account.planType,
                error: "Usage info not available for API key accounts"
            )
        }

        guard
            let accessToken = credential.accessToken,
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return errorUsage(
                accountID: account.id,
                planType: account.planType,
                error: "Missing OAuth access token"
            )
        }

        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return errorUsage(
                accountID: account.id,
                planType: account.planType,
                error: "Usage endpoint URL is invalid"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("codex-cli/1.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let chatgptAccountID = credential.externalAccountID, !chatgptAccountID.isEmpty {
            request.setValue(chatgptAccountID, forHTTPHeaderField: "chatgpt-account-id")
        }

        do {
            let (data, response) = try await load(request)
            guard (200...299).contains(response.statusCode) else {
                return errorUsage(
                    accountID: account.id,
                    planType: account.planType,
                    error: "Usage API error: HTTP \(response.statusCode)"
                )
            }

            let payload = try JSONDecoder().decode(RateLimitStatusPayload.self, from: data)
            return mapPayload(payload, accountID: account.id, fallbackPlanType: account.planType)
        } catch {
            return errorUsage(
                accountID: account.id,
                planType: account.planType,
                error: "Usage fetch failed: \(error.localizedDescription)"
            )
        }
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
