import AppKit
import CodexMenubarCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: MenubarAppState
    let onQuit: () -> Void

    private var labelColor: Color {
        Color(nsColor: .labelColor)
    }

    private var secondaryColor: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    private var darkGreenUsageColor: Color {
        Color(nsColor: NSColor(srgbRed: 0.13, green: 0.43, blue: 0.19, alpha: 1))
    }

    private var darkYellowUsageColor: Color {
        Color(nsColor: NSColor(srgbRed: 0.60, green: 0.46, blue: 0.11, alpha: 1))
    }

    private var darkRedUsageColor: Color {
        Color(nsColor: NSColor(srgbRed: 0.63, green: 0.17, blue: 0.17, alpha: 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if appState.accounts.isEmpty {
                            Text("No accounts yet")
                                .foregroundColor(secondaryColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(Array(appState.accounts.enumerated()), id: \.element.id) { index, account in
                                accountBlock(account)
                                    .frame(width: proxy.size.width, alignment: .leading)
                                if index < appState.accounts.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 14)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .frame(width: proxy.size.width)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 430)

            Divider()

            if let lastErrorMessage = appState.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button("Add Account") {
                    Task {
                        await appState.addAccountViaOAuth()
                    }
                }
                .buttonStyle(.borderless)
                .hoverCursor(.pointingHand)

                Spacer()

                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.borderless)
                .hoverCursor(.pointingHand)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .environment(\.controlActiveState, .key)
    }

    @ViewBuilder
    private func accountBlock(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Button("Rename...") {
                        Task {
                            await promptRename(for: account)
                        }
                    }

                    Button("Delete Account", role: .destructive) {
                        Task {
                            await promptDelete(for: account)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(secondaryColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 16, alignment: .leading)
                .fixedSize()
                .hoverCursor(.pointingHand)

                Button {
                    Task {
                        await handleSwitch(accountID: account.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(secondaryColor)
                        Text(account.name)
                            .font(.headline.weight(account.isActive ? .semibold : .regular))
                            .foregroundColor(labelColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .hoverCursor(.pointingHand)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(accountMetadataLine(for: account))
                .font(.caption)
                .foregroundColor(secondaryColor)
                .lineLimit(1)
                .truncationMode(.tail)

            if let usage = appState.usageByAccountID[account.id], usage.error == nil {
                usageBarLine(
                    title: "5h",
                    usedPercent: Int(min(max(usage.primaryUsedPercent, 0), 100)),
                    resetAt: usage.primaryResetsAt,
                    tint: usageColor(forUsedPercent: usage.primaryUsedPercent)
                )
                .padding(.bottom, 10)

                usageBarLine(
                    title: "Weekly",
                    usedPercent: Int(min(max(usage.secondaryUsedPercent, 0), 100)),
                    resetAt: usage.secondaryResetsAt,
                    tint: usageColor(forUsedPercent: usage.secondaryUsedPercent)
                )
            } else {
                Text("Usage unavailable")
                    .font(.subheadline)
                    .foregroundColor(labelColor)

                if let error = appState.usageByAccountID[account.id]?.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(secondaryColor)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func usageBarLine(title: String, usedPercent: Int, resetAt: Date, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(labelColor)
            }

            ProgressView(value: Double(usedPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)

            HStack(spacing: 8) {
                Text("\(usedPercent)% used")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(labelColor)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("Resets in \(relativeResetText(to: resetAt))")
                    .font(.caption)
                    .foregroundColor(secondaryColor)
            }
        }
    }

    @MainActor
    private func handleSwitch(accountID: String) async {
        let outcome = await appState.requestSwitch(accountID: accountID)
        if case .blockedByRunningCodex(let processCount) = outcome {
            let shouldContinue = confirmSwitch(processCount: processCount)
            if shouldContinue {
                _ = await appState.continueSwitchAfterConfirmation(accountID: accountID)
            }
        }
    }

    @MainActor
    private func confirmSwitch(processCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Codex is currently running"
        alert.informativeText = "\(processCount) Codex process(es) are running. Continue to kill them, switch account, and relaunch Codex?"
        alert.icon = alertIcon()
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func promptRename(for account: Account) async {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename Account"
        alert.informativeText = "Set a local display name for this account."
        alert.icon = alertIcon()

        let input = NSTextField(string: account.name)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let nextName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextName.isEmpty else {
            appState.lastErrorMessage = "Name cannot be empty."
            return
        }
        guard nextName != account.name else {
            return
        }

        await appState.renameAccount(accountID: account.id, newName: nextName)
    }

    @MainActor
    private func promptDelete(for account: Account) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \"\(account.name)\"?"
        if account.isActive {
            alert.informativeText = "This account is active. Deleting it will clear active auth and cannot be undone."
        } else {
            alert.informativeText = "This cannot be undone."
        }
        alert.icon = alertIcon()
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        await appState.deleteAccount(accountID: account.id)
    }

    private func alertIcon() -> NSImage? {
        NSImage(systemSymbolName: "lightswitch.on", accessibilityDescription: "Codex Account Switcher")
    }

    private func accountMetadataLine(for account: Account) -> String {
        let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = account.planType?.trimmingCharacters(in: .whitespacesAndNewlines)

        let emailPart = (email?.isEmpty == false) ? email! : "No email"
        guard let plan, !plan.isEmpty else {
            return emailPart
        }

        let normalizedPlan = plan.prefix(1).uppercased() + plan.dropFirst().lowercased()
        return "\(emailPart) (\(normalizedPlan))"
    }

    private func relativeResetText(to date: Date) -> String {
        let now = Date()
        guard date > now else {
            return "soon"
        }

        let interval = Int(date.timeIntervalSince(now))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60

        if days > 0 {
            return "\(days)d \(max(hours, 0))h"
        }
        if hours > 0 {
            return "\(hours)h \(max(minutes, 0))m"
        }
        return "\(max(minutes, 1))m"
    }

    private func usageColor(forUsedPercent used: Double) -> Color {
        let clamped = min(max(used, 0), 100)
        if clamped >= 90 {
            return darkRedUsageColor
        }
        if clamped >= 70 {
            return darkYellowUsageColor
        }
        return darkGreenUsageColor
    }

}

private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
    }
}
