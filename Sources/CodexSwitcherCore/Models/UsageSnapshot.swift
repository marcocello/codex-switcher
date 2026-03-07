import Foundation

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var accountID: String
    public var primaryUsedPercent: Double
    public var primaryResetsAt: Date
    public var secondaryUsedPercent: Double
    public var secondaryResetsAt: Date
    public var planType: String?
    public var error: String?

    public init(
        accountID: String,
        primaryUsedPercent: Double,
        primaryResetsAt: Date,
        secondaryUsedPercent: Double,
        secondaryResetsAt: Date,
        planType: String?,
        error: String?
    ) {
        self.accountID = accountID
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryResetsAt = secondaryResetsAt
        self.planType = planType
        self.error = error
    }

    public static func empty(accountID: String, planType: String?) -> UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            accountID: accountID,
            primaryUsedPercent: 0,
            primaryResetsAt: Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) ?? now,
            secondaryUsedPercent: 0,
            secondaryResetsAt: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now,
            planType: planType,
            error: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case primaryUsedPercent = "primary_used_percent"
        case primaryResetsAt = "primary_resets_at"
        case secondaryUsedPercent = "secondary_used_percent"
        case secondaryResetsAt = "secondary_resets_at"
        case planType = "plan_type"
        case error
    }
}
