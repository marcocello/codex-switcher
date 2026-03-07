import Foundation

public enum SwitchAccountOutcome: Equatable, Sendable {
    case switched
    case noChange
    case blockedByRunningCodex(processCount: Int)
    case cancelled
}
