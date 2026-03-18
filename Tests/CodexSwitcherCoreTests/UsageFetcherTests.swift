import CodexSwitcherCore
import Foundation
import Testing

private actor SequencedUsageLoader {
    private var requests: [URLRequest] = []
    private var callCount = 0

    func load(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        callCount += 1
        requests.append(request)

        switch callCount {
        case 1:
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        case 2:
            let json = """
            {
              "access_token": "token-refreshed",
              "refresh_token": "refresh-rotated"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(json.utf8), response)
        default:
            let json = """
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 12.5,
                  "reset_at": 2000000000
                },
                "secondary_window": {
                  "used_percent": 48.0,
                  "reset_at": 2000600000
                }
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(json.utf8), response)
        }
    }

    func snapshotRequests() -> [URLRequest] {
        requests
    }
}

private actor StrictRefreshJSONLoader {
    private var requests: [URLRequest] = []
    private var callCount = 0

    func load(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        callCount += 1
        requests.append(request)

        switch callCount {
        case 1:
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        case 2:
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let isJSON = contentType.lowercased().contains("application/json")
                && body.contains("\"grant_type\":\"refresh_token\"")
                && body.contains("\"client_id\":")
                && body.contains("\"refresh_token\":\"refresh-original\"")

            if isJSON {
                let json = """
                {
                  "access_token": "token-refreshed",
                  "refresh_token": "refresh-rotated"
                }
                """
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(json.utf8), response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("{\"error\":\"invalid_request\"}".utf8), response)
        default:
            let json = """
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 12.5,
                  "reset_at": 2000000000
                },
                "secondary_window": {
                  "used_percent": 48.0,
                  "reset_at": 2000600000
                }
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(json.utf8), response)
        }
    }
}

private actor RefreshInvalidatedLoader {
    func load(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        if request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage" {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        let payload = """
        {
          "error": {
            "code": "refresh_token_invalidated"
          }
        }
        """
        return (Data(payload.utf8), response)
    }
}

@Test("Usage fetcher maps ChatGPT usage payload to primary and secondary fields")
func usageFetcherMapsPayload() async {
    let json = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": {
          "used_percent": 34.5,
          "reset_at": 2000000000
        },
        "secondary_window": {
          "used_percent": 72.0,
          "reset_at": 2000600000
        }
      }
    }
    """

    let fetcher = DefaultUsageFetcher(load: { _ in
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    })

    let account = Account(
        id: "acc-1",
        name: "main",
        email: "user@example.com",
        workspaceName: nil,
        planType: nil,
        authMode: .chatGPT,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: "acc-1",
        authMode: .chatGPT,
        email: account.email,
        workspaceName: nil,
        planType: nil,
        accessToken: "token",
        refreshToken: nil,
        idToken: nil,
        externalAccountID: "chatgpt-account-id",
        apiKey: nil,
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    let result = await fetcher.fetchUsage(for: account, credential: credential)
    let usage = result.usage

    #expect(usage.error == nil)
    #expect(usage.planType == "pro")
    #expect(usage.primaryUsedPercent == 34.5)
    #expect(usage.secondaryUsedPercent == 72.0)
    #expect(Int(usage.primaryResetsAt.timeIntervalSince1970) == 2000000000)
    #expect(Int(usage.secondaryResetsAt.timeIntervalSince1970) == 2000600000)
}

@Test("Usage fetcher reports unsupported stats for API key account")
func usageFetcherRejectsAPIKeyStats() async {
    let fetcher = DefaultUsageFetcher()
    let account = Account(
        id: "acc-2",
        name: "api",
        email: nil,
        workspaceName: nil,
        planType: nil,
        authMode: .apiKey,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: "acc-2",
        authMode: .apiKey,
        email: nil,
        workspaceName: nil,
        planType: nil,
        accessToken: nil,
        refreshToken: nil,
        idToken: nil,
        externalAccountID: nil,
        apiKey: "sk-test",
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    let result = await fetcher.fetchUsage(for: account, credential: credential)
    let usage = result.usage

    #expect(usage.error == "Usage info not available for API key accounts")
}

@Test("Usage fetcher refreshes OAuth token after usage 401 and retries once")
func usageFetcherRefreshesTokenOn401AndRetries() async {
    let loader = SequencedUsageLoader()
    let fixedNow = Date(timeIntervalSince1970: 1_710_000_000)
    let fetcher = DefaultUsageFetcher(
        load: { request in
            await loader.load(request)
        },
        now: { fixedNow }
    )

    let account = Account(
        id: "acc-refresh",
        name: "main",
        email: "user@example.com",
        workspaceName: nil,
        planType: nil,
        authMode: .chatGPT,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: "acc-refresh",
        authMode: .chatGPT,
        email: account.email,
        workspaceName: nil,
        planType: nil,
        accessToken: "token-expired",
        refreshToken: "refresh-original",
        idToken: nil,
        externalAccountID: "chatgpt-account-id",
        apiKey: nil,
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    let result = await fetcher.fetchUsage(for: account, credential: credential)
    let usage = result.usage
    let requests = await loader.snapshotRequests()

    #expect(usage.error == nil)
    #expect(usage.primaryUsedPercent == 12.5)
    #expect(result.updatedCredential?.accessToken == "token-refreshed")
    #expect(result.updatedCredential?.refreshToken == "refresh-rotated")
    #expect(result.updatedCredential?.refreshedAt == fixedNow)
    #expect(requests.count == 3)
    if requests.count == 3 {
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer token-expired")
        #expect(requests[1].url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer token-refreshed")
    }
}

@Test("Usage fetcher sends JSON refresh payload expected by OAuth token endpoint")
func usageFetcherUsesJSONRefreshPayload() async {
    let loader = StrictRefreshJSONLoader()
    let fetcher = DefaultUsageFetcher(
        load: { request in
            await loader.load(request)
        }
    )

    let account = Account(
        id: "acc-json-refresh",
        name: "main",
        email: "user@example.com",
        workspaceName: nil,
        planType: nil,
        authMode: .chatGPT,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: "acc-json-refresh",
        authMode: .chatGPT,
        email: account.email,
        workspaceName: nil,
        planType: nil,
        accessToken: "token-expired",
        refreshToken: "refresh-original",
        idToken: nil,
        externalAccountID: "chatgpt-account-id",
        apiKey: nil,
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    let result = await fetcher.fetchUsage(for: account, credential: credential)

    #expect(result.usage.error == nil)
    #expect(result.updatedCredential?.accessToken == "token-refreshed")
}

@Test("Usage fetcher keeps 401 error when refresh token is missing")
func usageFetcherReturns401WhenRefreshTokenMissing() async {
    let loader = SequencedUsageLoader()
    let fetcher = DefaultUsageFetcher(
        load: { request in
            await loader.load(request)
        }
    )

    let account = Account(
        id: "acc-no-refresh",
        name: "main",
        email: "user@example.com",
        workspaceName: nil,
        planType: nil,
        authMode: .chatGPT,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: "acc-no-refresh",
        authMode: .chatGPT,
        email: account.email,
        workspaceName: nil,
        planType: nil,
        accessToken: "token-expired",
        refreshToken: nil,
        idToken: nil,
        externalAccountID: "chatgpt-account-id",
        apiKey: nil,
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    let result = await fetcher.fetchUsage(for: account, credential: credential)
    let usage = result.usage
    let requests = await loader.snapshotRequests()

    #expect(usage.error == "Usage API error: HTTP 401")
    #expect(result.updatedCredential == nil)
    #expect(requests.count == 1)
}

@Test("Usage fetcher maps refresh_token_invalidated to actionable re-auth error")
func usageFetcherMapsInvalidatedRefreshToken() async {
    let loader = RefreshInvalidatedLoader()
    let fetcher = DefaultUsageFetcher(
        load: { request in
            await loader.load(request)
        }
    )

    let account = Account(
        id: "acc-refresh-invalidated",
        name: "main",
        email: "user@example.com",
        workspaceName: nil,
        planType: nil,
        authMode: .chatGPT,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: "acc-refresh-invalidated",
        authMode: .chatGPT,
        email: account.email,
        workspaceName: nil,
        planType: nil,
        accessToken: "token-expired",
        refreshToken: "refresh-invalidated",
        idToken: nil,
        externalAccountID: "chatgpt-account-id",
        apiKey: nil,
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    let result = await fetcher.fetchUsage(for: account, credential: credential)

    #expect(result.updatedCredential == nil)
    #expect(result.usage.error == "Usage unavailable: refresh token revoked. Re-add this account.")
}

@Test("Empty usage snapshot defaults secondary reset to a two-week window")
func usageSnapshotEmptyDefaultsSecondaryResetToTwoWeeks() {
    let now = Date()
    let usage = UsageSnapshot.empty(accountID: "acc-3", planType: nil)
    let daysUntilSecondaryReset = usage.secondaryResetsAt.timeIntervalSince(now) / 86_400

    #expect(daysUntilSecondaryReset > 13)
    #expect(daysUntilSecondaryReset < 15)
}
