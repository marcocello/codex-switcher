import Foundation
import Testing

@Test("Project version is defined in root VERSION file")
func projectVersionIsDefinedInRootVersionFile() throws {
    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let versionFile = repoRoot.appendingPathComponent("VERSION")

    #expect(FileManager.default.fileExists(atPath: versionFile.path))

    let rawVersion = try String(contentsOf: versionFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(!rawVersion.isEmpty)
    #expect(rawVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
}
