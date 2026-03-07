import Foundation

public struct AuthCredential: Codable, Equatable, Sendable {
    public var accountID: String
    public var authMode: AuthMode
    public var email: String?
    public var workspaceName: String?
    public var planType: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var idToken: String?
    public var externalAccountID: String?
    public var apiKey: String?
    public var rawAuthJSON: String?
    public var refreshedAt: Date

    public init(
        accountID: String,
        authMode: AuthMode,
        email: String?,
        workspaceName: String?,
        planType: String?,
        accessToken: String?,
        refreshToken: String?,
        idToken: String?,
        externalAccountID: String?,
        apiKey: String?,
        rawAuthJSON: String?,
        refreshedAt: Date
    ) {
        self.accountID = accountID
        self.authMode = authMode
        self.email = email
        self.workspaceName = workspaceName
        self.planType = planType
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.externalAccountID = externalAccountID
        self.apiKey = apiKey
        self.rawAuthJSON = rawAuthJSON
        self.refreshedAt = refreshedAt
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case authMode = "auth_mode"
        case email
        case workspaceName = "workspace_name"
        case planType = "plan_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case externalAccountID = "external_account_id"
        case apiKey = "api_key"
        case rawAuthJSON = "raw_auth_json"
        case refreshedAt = "refreshed_at"
    }
}
