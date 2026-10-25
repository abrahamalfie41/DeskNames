import AppKit
import SwiftUI

struct DeskNamesHelpView: View {
    @ObservedObject var shortcuts: ShortcutSettingsState
    @ObservedObject var creationShortcuts: ShortcutSettingsState
    @ObservedObject var switcherShortcuts: ShortcutSettingsState
    let openShortcutSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DeskNames").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Name, find, and switch desktops.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text(version).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Enable desktop control", icon: "hand.raised") {
                        instruction("1", "Open System Settings → Privacy & Security → Accessibility.")
                        instruction("2", "Enable DeskNames. If you don't see it in the list, click the + button to add it manually.")
                        Text("If access is already enabled, quit and reopen DeskNames.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    section("Check direct switching", icon: "arrow.up.forward") {
                        Text("System Settings → Keyboard → Keyboard Shortcuts → Mission Control")
                            .foregroundStyle(.secondary)
                        Text("If a desktop’s shortcut is missing, assign a key to “Switch to Desktop N”.")
                        Text("Custom assignments are respected. Disabled shortcuts are enabled briefly for a jump, then restored.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    section("Find a desktop", icon: "magnifyingglass") {
                        Text("Press \(shortcuts.shortcut.display), type a desktop name, then press Return.")
                        Text("↑ / ↓ selects a result. Escape closes search.").foregroundStyle(.secondary)
                        Button("Change Search Shortcut…", action: openShortcutSettings).buttonStyle(.link)
                    }
                    section("Desktop switcher", icon: "rectangle.stack") {
                        Text("Press \(switcherShortcuts.shortcut.display) and keep its Command, Option, or Control modifiers held to open the desktop strip.")
                        Text("Press the shortcut again to cycle forward, or add Shift to cycle backward. Arrow keys also move the selection.")
                        Text("Release a held modifier to switch to the highlighted desktop. Return also confirms; Escape or clicking outside cancels.")
                        Text("Move the mouse to highlight a desktop, or click one to switch immediately. A stationary pointer won’t override keyboard navigation.")
                        Text("The current desktop appears first, followed by recently used desktops. A quick press and release returns to the previous desktop.")
                            .foregroundStyle(.secondary)
                        Button("Change Switcher Shortcut…", action: openShortcutSettings).buttonStyle(.link)
                    }
                    section("Organize your spaces", icon: "square.stack.3d.up") {
                        Text("Press \(creationShortcuts.shortcut.display) or choose New Desktop to name a new space and choose its icon and color before creating it.")
                        Text("The pencil edits an existing desktop and offers Remove Desktop.")
                        Text("Names appear in DeskNames, not in Mission Control. Direct jumps support regular desktops 1–16; full-screen apps use Mission Control.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("With multiple displays, keep the pointer on the display you want to switch.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }
            Divider()
            HStack {
                Text("Keep this window open while you set up.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("System Settings…") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }.padding(16)
        }
        .frame(minWidth: 440, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 7, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 22)
        }
    }
    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.blue).frame(width: 18, height: 18)
                .background(.blue.opacity(0.08), in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
