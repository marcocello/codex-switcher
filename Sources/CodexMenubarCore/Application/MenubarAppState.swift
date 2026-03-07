import Combine
import Foundation

@MainActor
public final class MenubarAppState: ObservableObject {
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var usageByAccountID: [String: UsageSnapshot] = [:]
    @Published public var lastErrorMessage: String?

    private let gateway: CoreCommandGateway

    public init(gateway: CoreCommandGateway) {
        self.gateway = gateway
    }

    public func reloadAccounts() async {
        do {
            accounts = try await gateway.list_accounts()
            let validIDs = Set(accounts.map(\.id))
            usageByAccountID = usageByAccountID.filter { validIDs.contains($0.key) }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func reloadAll() async {
        await reloadAccounts()
        await refreshUsage()
    }

    public func refreshUsage() async {
        do {
            let usage = try await gateway.refresh_all_accounts_usage()
            usageByAccountID = Dictionary(uniqueKeysWithValues: usage.map { ($0.accountID, $0) })
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func addAccountViaOAuth() async {
        do {
            _ = try await gateway.add_account_via_oauth()
            await reloadAccounts()
            Task {
                await self.refreshUsage()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func renameAccount(accountID: String, newName: String) async {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastErrorMessage = "Name cannot be empty."
            return
        }

        do {
            try await gateway.rename_account(accountID: accountID, newName: newName)
            accounts = try await gateway.list_accounts()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func deleteAccount(accountID: String) async {
        do {
            try await gateway.delete_account(accountID: accountID)
            await reloadAccounts()
            Task {
                await self.refreshUsage()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func requestSwitch(accountID: String) async -> SwitchAccountOutcome {
        do {
            let outcome = try await gateway.switch_account(accountID: accountID, killRunningCodex: false)
            if outcome == .switched || outcome == .noChange {
                await reloadAccounts()
                Task {
                    await self.refreshUsage()
                }
            }
            return outcome
        } catch {
            lastErrorMessage = error.localizedDescription
            return .cancelled
        }
    }

    public func continueSwitchAfterConfirmation(accountID: String) async -> SwitchAccountOutcome {
        do {
            let outcome = try await gateway.switch_account(accountID: accountID, killRunningCodex: true)
            if outcome == .switched || outcome == .noChange {
                await reloadAccounts()
                Task {
                    await self.refreshUsage()
                }
            }
            return outcome
        } catch {
            lastErrorMessage = error.localizedDescription
            return .cancelled
        }
    }
}
