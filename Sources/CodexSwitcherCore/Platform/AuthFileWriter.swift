import Foundation

public protocol AuthWriting: Sendable {
    func writeAuth(_ credential: AuthCredential) throws
    func clearAuth() throws
}

public final class JSONAuthWriter: AuthWriting, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func writeAuth(_ credential: AuthCredential) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if let rawAuthJSON = credential.rawAuthJSON, !rawAuthJSON.isEmpty {
            try Data(rawAuthJSON.utf8).write(to: fileURL, options: [.atomic])
            return
        }

        if credential.authMode == .chatGPT, let accessToken = credential.accessToken {
            var tokens: [String: String] = ["access_token": accessToken]
            if let refreshToken = credential.refreshToken, !refreshToken.isEmpty {
                tokens["refresh_token"] = refreshToken
            }
            if let idToken = credential.idToken, !idToken.isEmpty {
                tokens["id_token"] = idToken
            }
            if let externalAccountID = credential.externalAccountID, !externalAccountID.isEmpty {
                tokens["account_id"] = externalAccountID
            }

            let payload: [String: Any] = [
                "tokens": tokens,
                "last_refresh": iso8601UTC(credential.refreshedAt)
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: [.atomic])
            return
        }

        let data = try encoder.encode(credential)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clearAuth() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    private func iso8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
