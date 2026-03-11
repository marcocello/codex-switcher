import CodexSwitcherCore
import Foundation
import Testing

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

    let usage = await fetcher.fetchUsage(for: account, credential: credential)

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

    let usage = await fetcher.fetchUsage(for: account, credential: credential)

    #expect(usage.error == "Usage info not available for API key accounts")
}

@Test("Empty usage snapshot defaults secondary reset to a two-week window")
func usageSnapshotEmptyDefaultsSecondaryResetToTwoWeeks() {
    let now = Date()
    let usage = UsageSnapshot.empty(accountID: "acc-3", planType: nil)
    let daysUntilSecondaryReset = usage.secondaryResetsAt.timeIntervalSince(now) / 86_400

    #expect(daysUntilSecondaryReset > 13)
    #expect(daysUntilSecondaryReset < 15)
}
