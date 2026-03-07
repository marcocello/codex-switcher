@testable import CodexSwitcherCore
import Testing

@Test("Workspace identifier prefers default organization id")
func workspaceIdentifierPrefersDefaultOrganizationID() {
    let claims: [String: Any] = [
        "https://api.openai.com/auth": [
            "organizations": [
                ["id": "org_non_default", "title": "Personal", "is_default": false],
                ["id": "org_default", "title": "Team", "is_default": true]
            ]
        ]
    ]

    let workspaceID = BrowserOAuthService.extractWorkspaceIdentifier(from: claims)
    #expect(workspaceID == "org_default")
}

@Test("Workspace identifier falls back to first organization id")
func workspaceIdentifierFallsBackToFirstOrganizationID() {
    let claims: [String: Any] = [
        "https://api.openai.com/auth": [
            "organizations": [
                ["organization_id": "org_123", "title": "Personal"],
                ["id": "org_456", "title": "Backup"]
            ]
        ]
    ]

    let workspaceID = BrowserOAuthService.extractWorkspaceIdentifier(from: claims)
    #expect(workspaceID == "org_123")
}

@Test("Workspace identifier is nil when organizations have no id keys")
func workspaceIdentifierNilWhenNoIdentifierKeys() {
    let claims: [String: Any] = [
        "https://api.openai.com/auth": [
            "organizations": [
                ["title": "Personal", "is_default": true]
            ]
        ]
    ]

    let workspaceID = BrowserOAuthService.extractWorkspaceIdentifier(from: claims)
    #expect(workspaceID == nil)
}
