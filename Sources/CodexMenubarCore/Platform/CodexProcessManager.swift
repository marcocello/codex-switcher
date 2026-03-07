import Foundation

public protocol CodexProcessManaging: Sendable {
    func checkCodexProcesses() -> [Int]
    func killProcesses(_ pids: [Int]) -> Bool
    func relaunchCodex() -> Bool
}

public final class ShellCodexProcessManager: CodexProcessManaging, @unchecked Sendable {
    private let currentPID = ProcessInfo.processInfo.processIdentifier

    public init() {}

    public func checkCodexProcesses() -> [Int] {
        let output = runShell("ps aux | grep Codex.app | grep -v grep | awk '{print $2}'")
        guard output.status == 0, !output.stdout.isEmpty else {
            return []
        }

        let pids = output.stdout
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 != currentPID }

        return pids.map(Int.init)
    }

    public func killProcesses(_ pids: [Int]) -> Bool {
        guard !pids.isEmpty else {
            return true
        }

        // Keep kill behavior aligned with requested shell flow.
        let forcedKill = runShell("ps aux | grep Codex.app | grep -v grep | awk '{print $2}' | xargs kill -9")
        if forcedKill.status == 0 {
            return true
        }

        let fallbackKill = runProcess(launchPath: "/bin/kill", arguments: ["-KILL"] + pids.map(String.init))
        return fallbackKill.status == 0
    }

    public func relaunchCodex() -> Bool {
        let codexPath = "/Applications/Codex.app"
        if FileManager.default.fileExists(atPath: codexPath) {
            let launchByPath = runProcess(launchPath: "/usr/bin/open", arguments: ["-n", codexPath])
            if launchByPath.status == 0 {
                return true
            }
        }

        let launchByName = runProcess(launchPath: "/usr/bin/open", arguments: ["-a", "Codex"])
        return launchByName.status == 0
    }

    private func runShell(_ command: String) -> (status: Int32, stdout: String, stderr: String) {
        runProcess(launchPath: "/bin/zsh", arguments: ["-lc", command])
    }

    private func runProcess(launchPath: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (status: 1, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
