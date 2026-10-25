import AppKit
import SwiftUI
import ApplicationServices
import Darwin

struct Desktop {
    let id: UInt64
    let key: String
    let number: Int
    let fullscreen: Bool
    let shortcutNumber: Int?
}

// Read-only private APIs are loaded dynamically so an OS change fails gracefully.
final class SpacesReader {
    typealias Connection = @convention(c) () -> Int32
    typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    typealias MenuDisplay = @convention(c) (Int32) -> Unmanaged<CFString>?
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
    func snapshot(forDisplay requestedDisplay: String? = nil) -> DesktopSnapshot? {
        guard let connection = symbol("CGSMainConnectionID", Connection.self),
              let copy = symbol("CGSCopyManagedDisplaySpaces", CopySpaces.self),
              let getActive = symbol("CGSGetActiveSpace", ActiveSpace.self),
              let raw = copy(connection())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let active = getActive(connection())
        let displayID = requestedDisplay ?? (symbol("CGSCopyActiveMenuBarDisplayIdentifier", MenuDisplay.self)?(connection())?.takeRetainedValue() as String?)
        if let requestedDisplay, !raw.contains(where: { ($0["Display Identifier"] as? String) == requestedDisplay }) { return nil }
        let display = raw.first { ($0["Display Identifier"] as? String) == displayID }
            ?? raw.first { (($0["Spaces"] as? [[String: Any]]) ?? []).contains { ($0["id64"] as? NSNumber)?.uint64Value == active } }
            ?? raw.first
        guard let display, let list = display["Spaces"] as? [[String: Any]], !list.isEmpty else { return nil }
        let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
        let desktops = Self.decodeSpaces(list, allDisplays: raw)
        let identifier = display["Display Identifier"] as? String ?? "Main"
        let numericDisplay: CGDirectDisplayID
        if identifier == "Main" { numericDisplay = CGMainDisplayID() }
        else if let uuid = CFUUIDCreateFromString(kCFAllocatorDefault, identifier as CFString) {
            numericDisplay = CGDisplayGetDisplayIDFromUUID(uuid)
        } else { return nil }
        return DesktopSnapshot(desktops: desktops, active: current?.uint64Value ?? active,
                               displayIdentifier: identifier, displayID: numericDisplay)
    }
    // Mission Control numbers regular desktops across displays, excluding full-screen Spaces.
    static func decodeSpaces(_ list: [[String: Any]], allDisplays: [[String: Any]]) -> [Desktop] {
        var numbers: [UInt64: Int] = [:]
        var next = 1
        for display in allDisplays {
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard (space["type"] as? NSNumber)?.intValue == 0,
                      let id = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                numbers[id] = next
                next += 1
            }
        }
        return list.compactMap { space in
            guard let id = (space["id64"] as? NSNumber)?.uint64Value else { return nil }
            let number = numbers[id]
            return Desktop(id: id, key: space["uuid"] as? String ?? "space-\(id)",
                           number: number ?? 0, fullscreen: number == nil, shortcutNumber: number)
        }
    }

}

// Use the target desktop's symbolic hotkey, not repeated left/right keystrokes.
// Private APIs are resolved at runtime and unavailability is reported to the user.
final class DirectDesktopSwitcher {
    typealias ReadKey = @convention(c) (UInt32, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias IsEnabled = @convention(c) (UInt32) -> Bool
    typealias SetEnabled = @convention(c) (UInt32, Bool) -> Int32
    let reader: SpacesReader
    var restorePending: (() -> Void)?
    init(reader: SpacesReader) { self.reader = reader }

    static func hotKeyID(for number: Int) -> UInt32? {
        guard (1...16).contains(number) else { return nil }
        return UInt32(117 + number)
    }
    func restore() { restorePending?(); restorePending = nil }

    // Returns a setup explanation on failure. A successful call sends exactly one key pair.
    func jump(to number: Int) -> String? {
        restore()
        guard let hotKey = Self.hotKeyID(for: number),
              let read = reader.symbol("CGSGetSymbolicHotKeyValue", ReadKey.self),
              let enabled = reader.symbol("CGSIsSymbolicHotKeyEnabled", IsEnabled.self),
              let setEnabled = reader.symbol("CGSSetSymbolicHotKeyEnabled", SetEnabled.self) else {
            return "macOS’s direct desktop command is unavailable. Direct jumps support regular desktops 1–16."
        }
        var character: UInt16 = 0xffff
        var key: UInt16 = 0xffff
        var modifiers: UInt32 = 0
        guard read(hotKey, &character, &key, &modifiers) == 0,
              key != 0xffff, !(key == 0 && character == 0xffff), key < 128 else {
            return "Assign a shortcut to Switch to Desktop \(number) in System Settings → Keyboard → Keyboard Shortcuts → Mission Control, then try again."
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return "macOS could not create the direct desktop shortcut."
        }
        let wasEnabled = enabled(hotKey)
        if !wasEnabled {
            guard setEnabled(hotKey, true) == 0 else {
                return "Enable Switch to Desktop \(number) in Keyboard → Keyboard Shortcuts → Mission Control."
            }
            // Every lease is restored once, including on app quit. Old timers cannot
            // disable the hotkey belonging to a later jump.
            var restored = false
            let cleanup = {
                guard !restored else { return }
                restored = true
                _ = setEnabled(hotKey, false)
            }
            restorePending = cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: cleanup)
        }
        down.flags = CGEventFlags(rawValue: UInt64(modifiers))
        // Number keys do not have the arrow-specific Fn flag.
        up.flags = []
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { up.post(tap: .cghidEventTap) }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let reader = SpacesReader()
    lazy var directSwitcher = DirectDesktopSwitcher(reader: reader)
    lazy var spaceManager = SpaceManager(reader: reader)
    let globalShortcut = GlobalShortcut()
    lazy var desktopSwitcher = DesktopSwitcherController(app: self)
    let switcherShortcut = GlobalShortcut(identifier: 3)
    let switcherShortcutSettings = ShortcutSettingsState(preferenceKey: "desktopSwitcherShortcut", defaultShortcut: .desktopSwitcher)
    let creationShortcut = GlobalShortcut(identifier: 2)
    let shortcutSettings = ShortcutSettingsState()
    let creationShortcutSettings = ShortcutSettingsState(preferenceKey: "createDesktopShortcut", defaultShortcut: .createDesktop)
    var recordingShortcut: ShortcutAction?
    var newDesktopWindow: DesktopCreationPanel?
    var creationSession: DesktopCreationSession?
    let loginItemSettings = LoginItemSettingsState()
    var settingsWindow: NSWindow?
    var helpWindow: NSWindow?
    var searchWindow: SearchPanel?
    var searchSession: SearchSession?
    var searchKeyMonitor: Any?
    var shortcutRecorder: Any?
    var managingSpaces = false
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var desktops: [Desktop] = []
    var active: UInt64 = 0
    var names = UserDefaults.standard.dictionary(forKey: "desktopNames") as? [String: String] ?? [:]
    var timer: Timer?
    var switching = false
    let popover = NSPopover()
    let panelState = DesktopPanelState()
    var appearances: [String: DesktopAppearance] = {
        guard let data = UserDefaults.standard.data(forKey: "desktopAppearances"),
              let value = try? JSONDecoder().decode([String: DesktopAppearance].self, from: data) else { return [:] }
        return value
    }()
    var statusAppearance: DesktopAppearance?
    var didRequestAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status.button?.imagePosition = .imageLeading
        status.button?.font = .systemFont(ofSize: 12, weight: .medium)
        status.button?.target = self
        status.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: DesktopPanelView(
            model: panelState,
            select: { [weak self] id in self?.popover.performClose(nil); self?.switchDesktop(id) },
            save: { [weak self] key, name, appearance in self?.saveDesktop(key: key, name: name, appearance: appearance) },
            help: { [weak self] in self?.help() },
            permissions: { [weak self] in self?.accessibility() },
            search: { [weak self] in self?.toggleSearch() },
            settings: { [weak self] in self?.openSettings() },
            add: { [weak self] in self?.addDesktop() },
            remove: { [weak self] id in self?.removeDesktop(id) },
            quit: { [weak self] in self?.quit() }
        ))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        globalShortcut.action = { [weak self] in self?.toggleSearch() }
        if globalShortcut.register(shortcutSettings.shortcut) != noErr {
            shortcutSettings.message = "The search shortcut is unavailable. Choose another combination."
        }
        creationShortcut.action = { [weak self] in self?.addDesktop() }
        if creationShortcut.register(creationShortcutSettings.shortcut) != noErr {
            creationShortcutSettings.message = "The new desktop shortcut is unavailable. Choose another combination."
        }
        switcherShortcut.action = { [weak self] in self?.desktopSwitcher.invoke() }
        switcherShortcut.reverseAction = { [weak self] in self?.desktopSwitcher.invoke(reverse: true) }
        if switcherShortcut.register(switcherShortcutSettings.shortcut) != noErr {
            switcherShortcutSettings.message = "The desktop switcher shortcut is unavailable. Choose another combination."
        }
        panelState.creationShortcutLabel = creationShortcutSettings.shortcut.display
        panelState.shortcutLabel = shortcutSettings.shortcut.display
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func title(_ desktop: Desktop) -> String {
        names[desktop.key] ?? (desktop.fullscreen ? "Full-screen app" : "Desktop \(desktop.number)")
    }
    @objc func spaceChanged() { refresh() }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        refresh()
        guard let button = status.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func appearance(for desktop: Desktop) -> DesktopAppearance {
        appearances[desktop.key] ?? DesktopAppearance.initial(key: desktop.key, title: title(desktop))
    }
    func refresh() {
        panelState.switching = switching || managingSpaces
        guard let snapshot = reader.snapshot() else {
            status.button?.title = " DeskNames"
            status.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Desktops")
            panelState.error = "Your desktops aren’t available right now. Try reopening DeskNames."
            panelState.rows = []
            panelState.canAdd = false
            statusAppearance = nil
            return
        }
        panelState.error = nil
        desktops = snapshot.desktops
        active = snapshot.active
        let currentDesktop = desktops.first { $0.id == active }
        if let currentDesktop { desktopSwitcher.recency.visit(currentDesktop.key) }
        let current = currentDesktop.map(title) ?? "DeskNames"
        status.button?.title = " " + (current.count > 28 ? String(current.prefix(27)) + "…" : current)
        status.button?.toolTip = current
        if let desktop = currentDesktop {
            let style = appearance(for: desktop)
            if statusAppearance != style {
                let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                    .applying(.init(paletteColors: [style.palette.native]))
                let image = NSImage(systemSymbolName: style.icon, accessibilityDescription: current)?
                    .withSymbolConfiguration(configuration)
                image?.isTemplate = false
                status.button?.image = image
                statusAppearance = style
            }
        }
        let rows = desktops.map { desktop in
            DesktopPanelRow(id: desktop.id, key: desktop.key, title: title(desktop),
                            customName: names[desktop.key] ?? "",
                            subtitle: desktop.fullscreen ? "Full-screen app" : "Desktop \(desktop.number)",
                            current: desktop.id == active, appearance: appearance(for: desktop),
                            switchable: desktop.shortcutNumber.map { (1...16).contains($0) } ?? false,
                            removable: SpaceManagementPolicy.canRemove(desktop.id, from: desktops))
        }
        if panelState.rows != rows { panelState.rows = rows }
        panelState.canAdd = !managingSpaces && !switching && desktops.filter { !$0.fullscreen }.count < 16
    }
    func saveDesktop(key: String, name: String, appearance: DesktopAppearance) {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        names[key] = value.isEmpty ? nil : value
        appearances[key] = appearance
        UserDefaults.standard.set(names, forKey: "desktopNames")
        if let data = try? JSONEncoder().encode(appearances) {
            UserDefaults.standard.set(data, forKey: "desktopAppearances")
        }
        refresh()
    }
    @objc func accessibility() {
        popover.performClose(nil)
        if !didRequestAccessibility && !AXIsProcessTrusted() {
            didRequestAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func permissionHelp() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DeskNames needs Accessibility access"
        alert.informativeText = "Open System Settings → Privacy & Security → Accessibility and enable DeskNames. If it isn’t listed, click + and select the app.\n\nIf access is already enabled, quit and reopen DeskNames. If the issue continues, remove DeskNames from the list with the minus button, then add it again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    func switchDesktop(_ target: UInt64) {
        guard !switching && !managingSpaces else { return }
        refresh()
        guard target != active, let desktop = desktops.first(where: { $0.id == target }) else { return }
        guard AXIsProcessTrusted() else { permissionHelp(); return }
        guard let number = desktop.shortcutNumber else {
            show("Full-screen Space", "Direct jumping currently supports regular desktops. Select this full-screen app through Mission Control.")
            return
        }
        switching = true
        panelState.switching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Resolve again after menu dismissal in case the desktop order changed.
            guard let latest = self.reader.snapshot(),
                  let destination = latest.desktops.first(where: { $0.id == target }),
                  destination.shortcutNumber == number else {
                self.failSwitch(); return
            }
            if let error = self.directSwitcher.jump(to: number) {
                self.finishSwitch()
                self.show("Direct desktop jump needs setup", error)
                return
            }
            self.awaitJump(target: target, attempts: 35)
        }
    }
    func awaitJump(target: UInt64, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.refresh()
            if self.active == target {
                self.finishSwitch()
            } else if attempts > 0 {
                self.awaitJump(target: target, attempts: attempts - 1)
            } else { self.failSwitch() }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        desktopSwitcher.finish(commit: false)
        switcherShortcut.unregister()
        directSwitcher.restore()
        globalShortcut.unregister()
        creationShortcut.unregister()
        if let shortcutRecorder { NSEvent.removeMonitor(shortcutRecorder) }
        if let searchKeyMonitor { NSEvent.removeMonitor(searchKeyMonitor) }
    }
    func finishSwitch() { switching = false; refresh() }
    func failSwitch() {
        finishSwitch()
        guard AXIsProcessTrusted() else { permissionHelp(); return }
        show("macOS didn’t complete the desktop switch", "Accessibility access is enabled for DeskNames. The shortcut was sent, but the expected desktop did not become active.\n\nCheck the target’s Switch to Desktop shortcut under System Settings → Keyboard → Keyboard Shortcuts → Mission Control. With multiple displays, keep the pointer on the display you want to switch.")
    }
    @objc func help() {
        popover.performClose(nil)
        hideSearch()
        if helpWindow == nil {
            let controller = NSHostingController(rootView: DeskNamesHelpView(
                shortcuts: shortcutSettings,
                creationShortcuts: creationShortcutSettings,
                switcherShortcuts: switcherShortcutSettings,
                openShortcutSettings: { [weak self] in self?.openSettings() }
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "DeskNames Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.setContentSize(NSSize(width: 480, height: 600))
            window.contentMinSize = NSSize(width: 440, height: 440)
            window.center()
            helpWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
    }
    func show(_ title: String, _ message: String) {
        popover.performClose(nil)
        hideSearch()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--check-features") {
    exit(FeatureChecks.run() ? 0 : 1)
} else if CommandLine.arguments.contains("--check-routing") {
    func space(_ id: UInt64, _ fullscreen: Bool = false) -> [String: Any] {
        ["id64": NSNumber(value: id), "uuid": "uuid-\(id)", "type": fullscreen ? 4 : 0]
    }
    let first = [space(10), space(99, true), space(20)]
    let second = [space(30), space(40), space(50)]
    let displays: [[String: Any]] = [["Spaces": first], ["Spaces": second]]
    let one = SpacesReader.decodeSpaces(first, allDisplays: displays)
    let two = SpacesReader.decodeSpaces(second, allDisplays: displays)
    guard one.map(\.shortcutNumber) == [1, nil, 2],
          two.map(\.shortcutNumber) == [3, 4, 5],
          two.last?.id == 50,
          two.last?.key == "uuid-50",
          DirectDesktopSwitcher.hotKeyID(for: two.last!.shortcutNumber!) == 122,
          DirectDesktopSwitcher.hotKeyID(for: 1) == 118,
          DirectDesktopSwitcher.hotKeyID(for: 16) == 133,
          DirectDesktopSwitcher.hotKeyID(for: 0) == nil,
          DirectDesktopSwitcher.hotKeyID(for: 17) == nil else {
        fputs("FAIL: direct desktop routing.\n", stderr); exit(1)
    }
    let reordered = [space(20), space(10)]
    let reorderedResult = SpacesReader.decodeSpaces(reordered, allDisplays: [["Spaces": reordered]])
    guard reorderedResult.first?.id == 20, reorderedResult.first?.shortcutNumber == 1,
          reorderedResult.last?.key == "uuid-10" else {
        fputs("FAIL: reordered desktop routing.\n", stderr); exit(1)
    }
    print("PASS: 1→5 targets hotkey 122 directly; global multi-display numbering, full-screen exclusion, reordering, identity, and desktop bounds verified. No events posted.")
} else if CommandLine.arguments.contains("--diagnose") {
    if let result = SpacesReader().snapshot() {
        print("Detected \(result.desktops.count) Spaces; active ID: \(result.active)")
        for desktop in result.desktops { print("\(desktop.id) | \(desktop.key) | desktop \(desktop.number) | fullscreen \(desktop.fullscreen)") }
    } else { fputs("Unable to read Spaces. Run outside a restricted shell in a logged-in macOS desktop session; macOS API compatibility may also affect access.\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
