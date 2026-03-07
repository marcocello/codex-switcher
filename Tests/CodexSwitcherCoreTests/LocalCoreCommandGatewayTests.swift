import CodexSwitcherCore
import Foundation
import Testing

@Test("S1 add account does not change active account")
func addAccountDoesNotChangeActiveAccount() async throws {
    let existing = makeAccountRecord(id: "A", name: "alpha")
    let store = InMemoryStore(
        state: PersistedAccounts(records: [existing], activeAccountID: "A", usageByAccountID: [:])
    )
    let oauth = StubOAuth(info: OAuthAccountInfo(email: "b@example.com", workspaceName: "ws", planType: "plus", authMode: .chatGPT, accessToken: "tok", refreshToken: nil, idToken: nil, externalAccountID: nil, apiKey: nil, rawAuthJSON: nil))
    let gateway = makeGateway(store: store, oauth: oauth)

    _ = try await gateway.add_account_via_oauth()

    let accounts = try await gateway.list_accounts()
    #expect(accounts.count == 2)
    #expect(accounts.first(where: { $0.id == "A" })?.isActive == true)
    #expect(accounts.first(where: { $0.email == "b@example.com" })?.isActive == false)
}

@Test("S2 switch blocked when codex is running without confirmation")
func switchBlockedWhenCodexRunningWithoutConfirmation() async throws {
    let active = makeAccountRecord(id: "A", name: "alpha")
    let target = makeAccountRecord(id: "B", name: "beta")
    let store = InMemoryStore(
        state: PersistedAccounts(records: [active, target], activeAccountID: "A", usageByAccountID: [:])
    )
    let process = StubProcessManager(pids: [101, 202])
    let gateway = makeGateway(store: store, process: process)

    let outcome = try await gateway.switch_account(accountID: "B", killRunningCodex: false)

    #expect(outcome == .blockedByRunningCodex(processCount: 2))
    #expect(store.state.activeAccountID == "A")
    #expect(process.didKill == false)
    #expect(process.didRelaunch == false)
}

@Test("S3 confirmed switch kills and relaunches")
func confirmedSwitchKillsAndRelaunches() async throws {
    let active = makeAccountRecord(id: "A", name: "alpha")
    let target = makeAccountRecord(id: "B", name: "beta")
    let store = InMemoryStore(
        state: PersistedAccounts(records: [active, target], activeAccountID: "A", usageByAccountID: [:])
    )
    let process = StubProcessManager(pids: [42])
    let authWriter = StubAuthWriter()
    let gateway = makeGateway(store: store, authWriter: authWriter, process: process)

    let outcome = try await gateway.switch_account(accountID: "B", killRunningCodex: true)

    #expect(outcome == .switched)
    #expect(process.didKill == true)
    #expect(process.didRelaunch == true)
    #expect(store.state.activeAccountID == "B")
    #expect(authWriter.lastCredential?.accountID == "B")
}

@Test("Active account click is no-op")
func switchToActiveAccountIsNoop() async throws {
    let active = makeAccountRecord(id: "A", name: "alpha")
    let store = InMemoryStore(
        state: PersistedAccounts(records: [active], activeAccountID: "A", usageByAccountID: [:])
    )
    let process = StubProcessManager(pids: [999])
    let gateway = makeGateway(store: store, process: process)

    let outcome = try await gateway.switch_account(accountID: "A", killRunningCodex: true)

    #expect(outcome == .noChange)
    #expect(process.didKill == false)
    #expect(store.state.activeAccountID == "A")
}

@Test("Rename account updates local display name")
func renameAccountUpdatesDisplayName() async throws {
    let active = makeAccountRecord(id: "A", name: "alpha")
    let store = InMemoryStore(
        state: PersistedAccounts(records: [active], activeAccountID: "A", usageByAccountID: [:])
    )
    let gateway = makeGateway(store: store)

    try await gateway.rename_account(accountID: "A", newName: "team-main")

    #expect(store.state.records.first?.account.name == "team-main")
}

@Test("Delete active account clears auth and removes usage")
func deleteActiveAccountClearsAuthAndUsage() async throws {
    let active = makeAccountRecord(id: "A", name: "alpha")
    let other = makeAccountRecord(id: "B", name: "beta")
    let authWriter = StubAuthWriter()
    authWriter.lastCredential = active.credential

    let store = InMemoryStore(
        state: PersistedAccounts(
            records: [active, other],
            activeAccountID: "A",
            usageByAccountID: [
                "A": UsageSnapshot.empty(accountID: "A", planType: "plus"),
                "B": UsageSnapshot.empty(accountID: "B", planType: "plus")
            ]
        )
    )
    let gateway = makeGateway(store: store, authWriter: authWriter)

    try await gateway.delete_account(accountID: "A")

    #expect(store.state.records.count == 1)
    #expect(store.state.records.first?.account.id == "B")
    #expect(store.state.activeAccountID == nil)
    #expect(store.state.usageByAccountID["A"] == nil)
    #expect(authWriter.didClear == true)
}

@Test("Workspace label is normalized to workspace ID from token claims")
func workspaceNameIsNormalizedFromTokenClaims() async throws {
    var legacy = makeAccountRecord(id: "A", name: "alpha")
    legacy.account.workspaceName = "Personal"
    legacy.credential.workspaceName = "Personal"
    legacy.credential.idToken = makeUnsignedJWT(payload: [
        "https://api.openai.com/auth": [
            "organizations": [
                [
                    "id": "org_abc123",
                    "is_default": true
                ]
            ]
        ]
    ])

    let store = InMemoryStore(
        state: PersistedAccounts(records: [legacy], activeAccountID: nil, usageByAccountID: [:])
    )
    let gateway = makeGateway(store: store)

    let accounts = try await gateway.list_accounts()

    #expect(accounts.first?.workspaceName == "org_abc123")
    #expect(store.state.records.first?.account.workspaceName == "org_abc123")
    #expect(store.state.records.first?.credential.workspaceName == "org_abc123")
}

@Test("Workspace label is cleared when token has no workspace identifier")
func workspaceNameIsClearedWhenIdentifierMissing() async throws {
    var legacy = makeAccountRecord(id: "A", name: "alpha")
    legacy.account.workspaceName = "Personal"
    legacy.credential.workspaceName = "Personal"
    legacy.credential.idToken = makeUnsignedJWT(payload: [
        "https://api.openai.com/auth": [
            "organizations": [
                [
                    "title": "Personal",
                    "is_default": true
                ]
            ]
        ]
    ])

    let store = InMemoryStore(
        state: PersistedAccounts(records: [legacy], activeAccountID: nil, usageByAccountID: [:])
    )
    let gateway = makeGateway(store: store)

    let accounts = try await gateway.list_accounts()

    #expect(accounts.first?.workspaceName == nil)
    #expect(store.state.records.first?.account.workspaceName == nil)
    #expect(store.state.records.first?.credential.workspaceName == nil)
}

private func makeGateway(
    store: InMemoryStore,
    oauth: StubOAuth = StubOAuth(info: OAuthAccountInfo(email: nil, workspaceName: nil, planType: nil, authMode: .chatGPT, accessToken: nil, refreshToken: nil, idToken: nil, externalAccountID: nil, apiKey: nil, rawAuthJSON: nil)),
    authWriter: StubAuthWriter = StubAuthWriter(),
    process: StubProcessManager = StubProcessManager(pids: []),
    usage: StubUsageFetcher = StubUsageFetcher()
) -> LocalCoreCommandGateway {
    LocalCoreCommandGateway(
        store: store,
        oauth: oauth,
        authWriter: authWriter,
        processManager: process,
        usageFetcher: usage,
        now: { Date(timeIntervalSince1970: 10) }
    )
}

private func makeAccountRecord(id: String, name: String) -> AccountRecord {
    let account = Account(
        id: id,
        name: name,
        email: "\(name)@example.com",
        workspaceName: "team-\(name)",
        planType: "plus",
        authMode: .chatGPT,
        isActive: false,
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil
    )

    let credential = AuthCredential(
        accountID: id,
        authMode: .chatGPT,
        email: account.email,
        workspaceName: account.workspaceName,
        planType: account.planType,
        accessToken: "token-\(name)",
        refreshToken: nil,
        idToken: nil,
        externalAccountID: nil,
        apiKey: nil,
        rawAuthJSON: nil,
        refreshedAt: Date(timeIntervalSince1970: 0)
    )

    return AccountRecord(account: account, credential: credential)
}

private final class InMemoryStore: AccountsStoring, @unchecked Sendable {
    var state: PersistedAccounts

    init(state: PersistedAccounts) {
        self.state = state
    }

    func load() throws -> PersistedAccounts { state }

    func save(_ state: PersistedAccounts) throws {
        self.state = state
    }
}

private struct StubOAuth: OAuthAdding {
    let info: OAuthAccountInfo

    func addAccountViaOAuth() async throws -> OAuthAccountInfo {
        info
    }
}

private final class StubAuthWriter: AuthWriting, @unchecked Sendable {
    var lastCredential: AuthCredential?
    var didClear = false

    func writeAuth(_ credential: AuthCredential) throws {
        lastCredential = credential
    }

    func clearAuth() throws {
        didClear = true
        lastCredential = nil
    }
}

private final class StubProcessManager: CodexProcessManaging, @unchecked Sendable {
    var pids: [Int]
    var didKill = false
    var didRelaunch = false

    init(pids: [Int]) {
        self.pids = pids
    }

    func checkCodexProcesses() -> [Int] {
        pids
    }

    func killProcesses(_ pids: [Int]) -> Bool {
        didKill = true
        self.pids = []
        return true
    }

    func relaunchCodex() -> Bool {
        didRelaunch = true
        return true
    }
}

private struct StubUsageFetcher: UsageFetching {
    func fetchUsage(for account: Account, credential: AuthCredential) async -> UsageSnapshot {
        UsageSnapshot.empty(accountID: account.id, planType: account.planType)
    }
}

private func makeUnsignedJWT(payload: [String: Any]) -> String {
    let header: [String: Any] = ["alg": "none", "typ": "JWT"]
    let headerData = try! JSONSerialization.data(withJSONObject: header, options: [])
    let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
    let headerPart = base64URLEncode(headerData)
    let payloadPart = base64URLEncode(payloadData)
    return "\(headerPart).\(payloadPart)."
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
