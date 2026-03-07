import Foundation

public struct AccountRecord: Codable, Equatable, Sendable {
    public var account: Account
    public var credential: AuthCredential

    public init(account: Account, credential: AuthCredential) {
        self.account = account
        self.credential = credential
    }
}

public struct PersistedAccounts: Codable, Equatable, Sendable {
    public var records: [AccountRecord]
    public var activeAccountID: String?
    public var usageByAccountID: [String: UsageSnapshot]

    public init(records: [AccountRecord], activeAccountID: String?, usageByAccountID: [String: UsageSnapshot]) {
        self.records = records
        self.activeAccountID = activeAccountID
        self.usageByAccountID = usageByAccountID
    }

    public static var empty: PersistedAccounts {
        PersistedAccounts(records: [], activeAccountID: nil, usageByAccountID: [:])
    }

    enum CodingKeys: String, CodingKey {
        case records
        case activeAccountID = "active_account_id"
        case usageByAccountID = "usage_by_account_id"
    }
}
