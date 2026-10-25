import AppKit
import Carbon
import SwiftUI

struct ShortcutSpec: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    static let standard = ShortcutSpec(keyCode: 29, modifiers: UInt32(cmdKey), keyLabel: "0")
    static let createDesktop = ShortcutSpec(keyCode: 29, modifiers: UInt32(cmdKey | shiftKey), keyLabel: "0")
    static let desktopSwitcher = ShortcutSpec(keyCode: 48, modifiers: UInt32(optionKey), keyLabel: "Tab")
    var reversed: ShortcutSpec { ShortcutSpec(keyCode: keyCode, modifiers: modifiers ^ UInt32(shiftKey), keyLabel: keyLabel) }
    func hasSameBinding(as other: ShortcutSpec) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    var valid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return keyCode < 128 && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
            && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
            && modifiers & ~allowed == 0 && !keyLabel.isEmpty
    }
    var display: String {
        [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyLabel
    }
    static func capture(_ event: NSEvent) -> ShortcutSpec? {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let labels: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let label = labels[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        let spec = ShortcutSpec(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        return spec.valid ? spec : nil
    }
}

final class GlobalShortcut {
    private var keyRef: EventHotKeyRef?
    private var reverseKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var action: (() -> Void)?
    var reverseAction: (() -> Void)?
    private let signature: OSType = 0x444e414d // DNAM
    private let identifier: UInt32
    init(identifier: UInt32 = 1) {
        self.identifier = identifier
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let error = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard error == noErr, id.signature == owner.signature, (id.id == owner.identifier || id.id == owner.identifier + 100) else { return OSStatus(eventNotHandledErr) }
            let reverse = id.id == owner.identifier + 100
            DispatchQueue.main.async { [weak owner] in
                if reverse { owner?.reverseAction?() } else { owner?.action?() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
    func register(_ spec: ShortcutSpec) -> OSStatus {
        guard spec.valid, handlerRef != nil else { return OSStatus(paramErr) }
        var replacement: EventHotKeyRef?
        let error = RegisterEventHotKey(spec.keyCode, spec.modifiers, EventHotKeyID(signature: signature, id: identifier), GetApplicationEventTarget(), 0, &replacement)
        guard error == noErr else { return error }
        var reverseReplacement: EventHotKeyRef?
        if reverseAction != nil {
            let reverseError = RegisterEventHotKey(spec.reversed.keyCode, spec.reversed.modifiers,
                EventHotKeyID(signature: signature, id: identifier + 100), GetApplicationEventTarget(), 0, &reverseReplacement)
            guard reverseError == noErr else {
                if let replacement { UnregisterEventHotKey(replacement) }
                return reverseError
            }
        }
        unregister()
        keyRef = replacement
        reverseKeyRef = reverseReplacement
        return noErr
    }
    var isRegistered: Bool { keyRef != nil }
    func unregister() { if let keyRef { UnregisterEventHotKey(keyRef) }; keyRef = nil; if let reverseKeyRef { UnregisterEventHotKey(reverseKeyRef) }; reverseKeyRef = nil }
    deinit { unregister(); if let handlerRef { RemoveEventHandler(handlerRef) } }
}

enum ShortcutAction: Equatable { case search, createDesktop, switcher }

final class ShortcutSettingsState: ObservableObject {
    @Published var shortcut: ShortcutSpec
    @Published var recording = false
    @Published var message: String?
    private let preferenceKey: String
    init(preferenceKey: String = "searchShortcut", defaultShortcut: ShortcutSpec = .standard) {
        self.preferenceKey = preferenceKey
        if let data = UserDefaults.standard.data(forKey: preferenceKey),
           let saved = try? JSONDecoder().decode(ShortcutSpec.self, from: data), saved.valid {
            shortcut = saved
        } else { shortcut = defaultShortcut }
    }
    func save(_ spec: ShortcutSpec) {
        shortcut = spec
        if let data = try? JSONEncoder().encode(spec) { UserDefaults.standard.set(data, forKey: preferenceKey) }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsState
    @ObservedObject var creationModel: ShortcutSettingsState
    @ObservedObject var switcherModel: ShortcutSettingsState
    @ObservedObject var loginItem: LoginItemSettingsState
    let record: () -> Void
    let restoreDefault: () -> Void
    let recordCreation: () -> Void
    let restoreCreationDefault: () -> Void
    let recordSwitcher: () -> Void
    let restoreSwitcherDefault: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.fill").font(.system(size: 24)).foregroundStyle(.blue)
                        .frame(width: 48, height: 48).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DeskNames Settings").font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("Startup and keyboard shortcuts.").foregroundStyle(.secondary).font(.callout)
                    }
                }
                Divider()
                LoginItemSettingView(model: loginItem)
                Divider()
                ShortcutSettingRow(model: model, title: "Open search", detail: "Find a desktop by name.",
                                   defaultShortcut: .standard, otherRecording: creationModel.recording || switcherModel.recording,
                                   record: record, restoreDefault: restoreDefault)
                Divider()
                ShortcutSettingRow(model: creationModel, title: "New desktop", detail: "Choose its name, icon, and color.",
                                   defaultShortcut: .createDesktop, otherRecording: model.recording || switcherModel.recording,
                                   record: recordCreation, restoreDefault: restoreCreationDefault)
                Divider()
                ShortcutSettingRow(model: switcherModel, title: "Desktop switcher", detail: "Hold modifiers, cycle with Tab or arrows, then release to switch.",
                                   defaultShortcut: .desktopSwitcher, otherRecording: model.recording || creationModel.recording,
                                   record: recordSwitcher, restoreDefault: restoreSwitcherDefault)

            }.padding(26)
        }
        .frame(width: 440, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ShortcutSettingRow: View {
    @ObservedObject var model: ShortcutSettingsState
    let title: String
    let detail: String
    let defaultShortcut: ShortcutSpec
    let otherRecording: Bool
    let record: () -> Void
    let restoreDefault: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: record) {
                    Text(model.recording ? "Press shortcut…" : model.shortcut.display)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .frame(minWidth: 110, minHeight: 26)
                }
                .buttonStyle(.bordered).tint(model.recording ? .blue : nil)
                .disabled(otherRecording)
                .accessibilityLabel(model.recording ? "Recording shortcut. Escape cancels." : "Change \(title) shortcut, currently \(model.shortcut.display)")
            }
            Text(model.recording ? "Press a key with ⌘, ⌥, or ⌃. Press Escape to cancel." : "Click the shortcut to record a new combination.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button("Restore Default (\(defaultShortcut.display))", action: restoreDefault)
                .disabled(model.recording || otherRecording)
        }
    }
}
