import Foundation

public struct FilePaths: Sendable {
    public var accountsFileURL: URL
    public var authFileURL: URL

    public init(accountsFileURL: URL, authFileURL: URL) {
        self.accountsFileURL = accountsFileURL
        self.authFileURL = authFileURL
    }

    public static func `default`() -> FilePaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CodexMenubar", isDirectory: true)
        let codexDir = home
            .appendingPathComponent(".codex", isDirectory: true)
        return FilePaths(
            accountsFileURL: appSupport.appendingPathComponent("accounts.json"),
            authFileURL: codexDir.appendingPathComponent("auth.json")
        )
    }
}
