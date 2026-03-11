import Foundation

public enum AppVersionFormatter {
    public struct BuildMetadata: Sendable {
        public var date: String?
        public var shortHash: String?

        public init(date: String?, shortHash: String?) {
            self.date = date
            self.shortHash = shortHash
        }
    }

    public static func displayText(
        infoDictionary: [String: Any]?,
        gitMetadata: (() -> BuildMetadata)? = nil
    ) -> String {
        let infoMetadata = BuildMetadata(
            date: sanitizedString(infoDictionary?["CodexBuildDate"]),
            shortHash: sanitizedString(infoDictionary?["CodexBuildShortHash"])
        )

        let fallbackGitMetadata = gitMetadata?() ?? cachedGitMetadata
        let resolvedDate = infoMetadata.date ?? fallbackGitMetadata?.date
        let resolvedHash = infoMetadata.shortHash ?? fallbackGitMetadata?.shortHash

        if let resolvedDate, let resolvedHash {
            return "\(resolvedDate) \(resolvedHash)"
        }

        if let resolvedDate {
            return resolvedDate
        }

        if let resolvedHash {
            return resolvedHash
        }

        return "dev"
    }

    public static func trayLabelText(
        infoDictionary: [String: Any]?,
        gitMetadata: (() -> BuildMetadata)? = nil
    ) -> String {
        "Version: \(displayText(infoDictionary: infoDictionary, gitMetadata: gitMetadata))"
    }

    private static let cachedGitMetadata: BuildMetadata? = loadGitMetadata()

    private static func loadGitMetadata() -> BuildMetadata? {
        let hash = runCommand("/usr/bin/env", arguments: ["git", "rev-parse", "--short=7", "HEAD"])
        let date = runCommand("/usr/bin/env", arguments: ["git", "show", "-s", "--date=format:%Y-%m-%d", "--format=%cd", "HEAD"])

        if hash == nil, date == nil {
            return nil
        }

        return BuildMetadata(date: date, shortHash: hash)
    }

    private static func runCommand(_ launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return sanitizedString(output)
    }

    private static func sanitizedString(_ value: Any?) -> String? {
        guard
            let raw = value as? String,
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
