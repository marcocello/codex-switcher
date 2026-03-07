import Foundation

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var email: String?
    public var workspaceName: String?
    public var planType: String?
    public var authMode: AuthMode
    public var isActive: Bool
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: String,
        name: String,
        email: String?,
        workspaceName: String?,
        planType: String?,
        authMode: AuthMode,
        isActive: Bool,
        createdAt: Date,
        lastUsedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.workspaceName = workspaceName
        self.planType = planType
        self.authMode = authMode
        self.isActive = isActive
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case workspaceName = "workspace_name"
        case planType = "plan_type"
        case authMode = "auth_mode"
        case isActive = "is_active"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}
