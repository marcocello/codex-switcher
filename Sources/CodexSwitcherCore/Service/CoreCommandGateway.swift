import Foundation

public enum CoreGatewayError: LocalizedError {
    case accountNotFound
    case failedToKillCodex

    public var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return "Selected account was not found."
        case .failedToKillCodex:
            return "Failed to terminate running Codex processes."
        }
    }
}

public protocol CoreCommandGateway: Sendable {
    func list_accounts() async throws -> [Account]
    func refresh_all_accounts_usage() async throws -> [UsageSnapshot]
    func add_account_via_oauth() async throws -> Account
    func rename_account(accountID: String, newName: String) async throws
    func delete_account(accountID: String) async throws
    func switch_account(accountID: String, killRunningCodex: Bool) async throws -> SwitchAccountOutcome
    func check_codex_processes() async -> [Int]
}
