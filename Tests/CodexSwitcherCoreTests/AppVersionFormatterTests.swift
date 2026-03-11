import CodexSwitcherCore
import Testing

@Test("App version formatter builds a readable version label")
func appVersionFormatterBuildsReadableLabel() {
    #expect(AppVersionFormatter.displayText(infoDictionary: [
        "CodexBuildDate": "2026-03-11",
        "CodexBuildShortHash": "a31bf69"
    ]) == "2026-03-11 a31bf69")
}

@Test("App version formatter falls back to git metadata when bundle metadata is missing")
func appVersionFormatterFallsBackToGitMetadata() {
    #expect(
        AppVersionFormatter.displayText(
            infoDictionary: nil,
            gitMetadata: { .init(date: "2026-03-10", shortHash: "deadbee") }
        ) == "2026-03-10 deadbee"
    )
}

@Test("App version formatter builds tray label text with prefix")
func appVersionFormatterBuildsTrayLabelTextWithPrefix() {
    #expect(AppVersionFormatter.trayLabelText(infoDictionary: [
        "CodexBuildDate": "2026-03-11",
        "CodexBuildShortHash": "a31bf69"
    ]) == "Version: 2026-03-11 a31bf69")
}
