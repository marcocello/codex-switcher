import AppKit
import CodexMenubarCore
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
    let appState: MenubarAppState

    private init() {
        let gateway = LocalCoreCommandGateway.defaultGateway()
        appState = MenubarAppState(gateway: gateway)
    }
}

@main
struct CodexMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
