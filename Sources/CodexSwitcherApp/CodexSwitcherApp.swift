import AppKit
import CodexSwitcherCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppRuntime.shared.appState
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(appState: appState)
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let appState: SwitcherAppState

    private init() {
        let gateway = LocalCoreCommandGateway.defaultGateway()
        appState = SwitcherAppState(gateway: gateway)
    }
}

@main
struct CodexSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
