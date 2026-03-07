import AppKit
import CodexMenubarCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let appState: MenubarAppState
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(appState: MenubarAppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        Task {
            await appState.reloadAll()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "lightswitch.on",
            accessibilityDescription: "Codex Account Switcher"
        )
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 280, height: 580)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                appState: appState,
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            closePopover()
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.makeFirstResponder(nil)

        Task { [weak self] in
            guard let self else { return }
            if appState.accounts.isEmpty {
                await appState.reloadAll()
            } else {
                await appState.refreshUsage()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
