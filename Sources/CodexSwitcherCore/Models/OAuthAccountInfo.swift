import Foundation

public struct OAuthAccountInfo: Equatable, Sendable {
    public var email: String?
    public var workspaceName: String?
    public var planType: String?
    public var authMode: AuthMode
    public var accessToken: String?
    public var refreshToken: String?
    public var idToken: String?
    public var externalAccountID: String?
    public var apiKey: String?
    public var rawAuthJSON: String?

    public init(
        email: String?,
        workspaceName: String?,
        planType: String?,
        authMode: AuthMode,
        accessToken: String?,
        refreshToken: String?,
        idToken: String?,
        externalAccountID: String?,
        apiKey: String?,
        rawAuthJSON: String?
    ) {
        self.email = email
        self.workspaceName = workspaceName
        self.planType = planType
        self.authMode = authMode
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.externalAccountID = externalAccountID
        self.apiKey = apiKey
        self.rawAuthJSON = rawAuthJSON
    }
}
