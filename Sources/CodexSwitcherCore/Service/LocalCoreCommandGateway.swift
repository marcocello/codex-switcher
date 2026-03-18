import Foundation

public final class LocalCoreCommandGateway: CoreCommandGateway, @unchecked Sendable {
    private let store: AccountsStoring
    private let oauth: OAuthAdding
    private let authWriter: AuthWriting
    private let processManager: CodexProcessManaging
    private let usageFetcher: UsageFetching
    private let now: @Sendable () -> Date

    public init(
        store: AccountsStoring,
        oauth: OAuthAdding,
        authWriter: AuthWriting,
        processManager: CodexProcessManaging,
        usageFetcher: UsageFetching,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.oauth = oauth
        self.authWriter = authWriter
        self.processManager = processManager
        self.usageFetcher = usageFetcher
        self.now = now
    }

    public static func defaultGateway(paths: FilePaths = .default()) -> LocalCoreCommandGateway {
        LocalCoreCommandGateway(
            store: JSONAccountsStore(fileURL: paths.accountsFileURL),
            oauth: BrowserOAuthService(),
            authWriter: JSONAuthWriter(fileURL: paths.authFileURL),
            processManager: ShellCodexProcessManager(),
            usageFetcher: DefaultUsageFetcher()
        )
    }

    public func list_accounts() async throws -> [Account] {
        let state = try loadStateEnsuringWorkspaceIDs()
        return hydrateAccounts(from: state)
    }

    public func refresh_all_accounts_usage() async throws -> [UsageSnapshot] {
        var state = try loadStateEnsuringWorkspaceIDs()
        var nextUsage = state.usageByAccountID

        for index in state.records.indices {
            let record = state.records[index]
            let result = await usageFetcher.fetchUsage(for: record.account, credential: record.credential)
            nextUsage[record.account.id] = result.usage
            if let updatedCredential = result.updatedCredential {
                state.records[index].credential = updatedCredential
            }
        }

        state.usageByAccountID = nextUsage
        try store.save(state)

        return hydrateUsage(from: state)
    }

    public func add_account_via_oauth() async throws -> Account {
        let oauthInfo = try await oauth.addAccountViaOAuth()
        var state = try loadStateEnsuringWorkspaceIDs()

        let accountID = UUID().uuidString
        let accountName = inferredName(from: oauthInfo.email, index: state.records.count + 1)
        let createdAt = now()

        let account = Account(
            id: accountID,
            name: accountName,
            email: oauthInfo.email,
            workspaceName: oauthInfo.workspaceName,
            planType: oauthInfo.planType,
            authMode: oauthInfo.authMode,
            isActive: false,
            createdAt: createdAt,
            lastUsedAt: nil
        )

        let credential = AuthCredential(
            accountID: accountID,
            authMode: oauthInfo.authMode,
            email: oauthInfo.email,
            workspaceName: oauthInfo.workspaceName,
            planType: oauthInfo.planType,
            accessToken: oauthInfo.accessToken,
            refreshToken: oauthInfo.refreshToken,
            idToken: oauthInfo.idToken,
            externalAccountID: oauthInfo.externalAccountID,
            apiKey: oauthInfo.apiKey,
            rawAuthJSON: oauthInfo.rawAuthJSON,
            refreshedAt: createdAt
        )

        state.records.append(AccountRecord(account: account, credential: credential))
        state.usageByAccountID[accountID] = UsageSnapshot.empty(accountID: accountID, planType: oauthInfo.planType)
        try store.save(state)

        return withDerivedActive(account: account, activeAccountID: state.activeAccountID)
    }

    public func rename_account(accountID: String, newName: String) async throws {
        var state = try loadStateEnsuringWorkspaceIDs()
        guard let index = state.records.firstIndex(where: { $0.account.id == accountID }) else {
            throw CoreGatewayError.accountNotFound
        }

        state.records[index].account.name = newName
        try store.save(state)
    }

    public func delete_account(accountID: String) async throws {
        var state = try loadStateEnsuringWorkspaceIDs()
        guard state.records.contains(where: { $0.account.id == accountID }) else {
            throw CoreGatewayError.accountNotFound
        }

        state.records.removeAll { $0.account.id == accountID }
        state.usageByAccountID.removeValue(forKey: accountID)

        if state.activeAccountID == accountID {
            state.activeAccountID = nil
            try authWriter.clearAuth()
        }

        try store.save(state)
    }

    public func switch_account(accountID: String, killRunningCodex: Bool) async throws -> SwitchAccountOutcome {
        var state = try loadStateEnsuringWorkspaceIDs()
        guard let targetIndex = state.records.firstIndex(where: { $0.account.id == accountID }) else {
            throw CoreGatewayError.accountNotFound
        }

        if state.activeAccountID == accountID {
            return .noChange
        }

        let pids = processManager.checkCodexProcesses()
        if !pids.isEmpty && !killRunningCodex {
            return .blockedByRunningCodex(processCount: pids.count)
        }

        if !pids.isEmpty && killRunningCodex {
            let killed = processManager.killProcesses(pids)
            if !killed {
                throw CoreGatewayError.failedToKillCodex
            }
        }

        state.activeAccountID = accountID
        state.records[targetIndex].account.lastUsedAt = now()
        try store.save(state)

        let targetCredential = state.records[targetIndex].credential
        try authWriter.writeAuth(targetCredential)

        if !pids.isEmpty && killRunningCodex {
            _ = processManager.relaunchCodex()
        }

        return .switched
    }

    public func check_codex_processes() async -> [Int] {
        processManager.checkCodexProcesses()
    }

    private func loadStateEnsuringWorkspaceIDs() throws -> PersistedAccounts {
        var state = try store.load()
        if normalizeWorkspaceIdentifiers(in: &state) {
            try store.save(state)
        }
        return state
    }

    private func normalizeWorkspaceIdentifiers(in state: inout PersistedAccounts) -> Bool {
        var didMutate = false

        for index in state.records.indices {
            guard state.records[index].credential.authMode == .chatGPT else {
                continue
            }

            let credential = state.records[index].credential
            let claims = decodedJWTClaims(from: credential.idToken)
                ?? decodedJWTClaims(from: credential.accessToken)
                ?? decodedJWTClaims(fromRawAuthJSON: credential.rawAuthJSON)
            let workspaceID = BrowserOAuthService.extractWorkspaceIdentifier(from: claims)

            if state.records[index].account.workspaceName != workspaceID {
                state.records[index].account.workspaceName = workspaceID
                didMutate = true
            }

            if state.records[index].credential.workspaceName != workspaceID {
                state.records[index].credential.workspaceName = workspaceID
                didMutate = true
            }
        }

        return didMutate
    }

    private func decodedJWTClaims(fromRawAuthJSON rawAuthJSON: String?) -> [String: Any]? {
        guard
            let rawAuthJSON,
            let data = rawAuthJSON.data(using: .utf8),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any]
        else {
            return nil
        }

        if let idToken = tokens["id_token"] as? String,
           let claims = decodedJWTClaims(from: idToken)
        {
            return claims
        }

        if let accessToken = tokens["access_token"] as? String,
           let claims = decodedJWTClaims(from: accessToken)
        {
            return claims
        }

        return nil
    }

    private func decodedJWTClaims(from token: String?) -> [String: Any]? {
        guard
            let token,
            !token.isEmpty
        else {
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

    private func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: base64)
    }

    private func hydrateAccounts(from state: PersistedAccounts) -> [Account] {
        state.records
            .map { withDerivedActive(account: $0.account, activeAccountID: state.activeAccountID) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func hydrateUsage(from state: PersistedAccounts) -> [UsageSnapshot] {
        state.records.compactMap { record in
            state.usageByAccountID[record.account.id]
        }
    }

    private func withDerivedActive(account: Account, activeAccountID: String?) -> Account {
        var copy = account
        copy.isActive = (copy.id == activeAccountID)
        return copy
    }

    private func inferredName(from email: String?, index: Int) -> String {
        guard
            let email,
            let localPart = email.split(separator: "@").first,
            !localPart.isEmpty
        else {
            return "Account \(index)"
        }

        return String(localPart)
    }
}
