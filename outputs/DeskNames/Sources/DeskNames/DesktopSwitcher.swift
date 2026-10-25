import AppKit
import Carbon
import SwiftUI

// Stable UUIDs keep recency independent of desktop numbering and reordering.
struct DesktopRecency {
    private(set) var keys: [String] = []
    mutating func visit(_ key: String) {
        guard keys.first != key else { return }
        keys.removeAll { $0 == key }
        keys.insert(key, at: 0)
        keys = Array(keys.prefix(256))
    }
    func ordered(_ rows: [DesktopPanelRow]) -> [DesktopPanelRow] {
        let candidates = rows.filter(\.switchable)
        return candidates.sorted { lhs, rhs in
            if lhs.current != rhs.current { return lhs.current }
            return (keys.firstIndex(of: lhs.key) ?? Int.max) < (keys.firstIndex(of: rhs.key) ?? Int.max)
        }
    }
}

final class DesktopSwitcherSession: ObservableObject {
    let rows: [DesktopPanelRow]
    @Published var selection: Int
    private var keyboardPointer: NSPoint?
    init(rows: [DesktopPanelRow], reverse: Bool, pointer: NSPoint = .zero) {
        self.rows = rows
        selection = rows.isEmpty ? 0 : (reverse ? rows.count - 1 : (rows.first?.current == true ? min(1, rows.count - 1) : 0))
        keyboardPointer = pointer
    }
    func move(_ delta: Int, pointer: NSPoint = NSEvent.mouseLocation) {
        guard !rows.isEmpty else { return }
        keyboardPointer = pointer
        selection = ((selection + delta) % rows.count + rows.count) % rows.count
    }
    func hover(_ index: Int, pointer: NSPoint = NSEvent.mouseLocation) {
        guard rows.indices.contains(index), keyboardPointer != pointer else { return }
        keyboardPointer = nil
        selection = index
    }
}

struct DesktopSwitcherView: View {
    @ObservedObject var session: DesktopSwitcherSession
    let choose: (Int) -> Void
    var body: some View {
        VStack(spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(session.rows.enumerated()), id: \.element.id) { index, row in
                            Button { choose(index) } label: {
                                VStack(spacing: 10) {
                                    DesktopBadge(appearance: row.appearance, size: 68)
                                    Text(row.title).font(.system(size: 12, weight: .semibold))
                                        .lineLimit(2).multilineTextAlignment(.center).frame(height: 32)
                                    Text(row.current ? "Current" : row.subtitle)
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .frame(width: 100).padding(.vertical, 14)
                                .background(session.selection == index ? Color.primary.opacity(0.1) : .clear,
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(session.selection == index ? row.appearance.palette.color.opacity(0.6) : .clear, lineWidth: 2))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(row.id)
                            .onContinuousHover { phase in
                                if case .active = phase { session.hover(index) }
                            }
                            .accessibilityLabel("Switch to \(row.title)")
                            .accessibilityValue(session.selection == index ? "Selected" : "")
                        }
                    }.padding(4)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: session.selection) { _ in scroll(proxy) }
            }
            Text("Tab / ⇧Tab or arrows to navigate · Release modifiers to switch · Esc to cancel")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(height: 252)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
    private func scroll(_ proxy: ScrollViewProxy) {
        if session.rows.indices.contains(session.selection) {
            proxy.scrollTo(session.rows[session.selection].id, anchor: .center)
        }
    }
}

final class DesktopSwitcherController {
    weak var app: AppDelegate?
    var recency = DesktopRecency()
    private var panel: SearchPanel?
    private var session: DesktopSwitcherSession?
    private var monitor: Any?
    private var releaseTimer: Timer?
    private var heldModifiers: CGEventFlags = []
    init(app: AppDelegate) { self.app = app }

    func invoke(reverse: Bool = false) {
        guard let app, !app.switching, !app.managingSpaces,
              app.recordingShortcut == nil, NSApp.modalWindow == nil else { return }
        if let session { session.move(reverse ? -1 : 1); return }
        app.popover.performClose(nil)
        app.hideSearch()
        app.hideNewDesktopPopup()
        app.refresh()
        let rows = recency.ordered(app.panelState.rows)
        guard !rows.isEmpty else { return }
        let session = DesktopSwitcherSession(rows: rows, reverse: reverse, pointer: NSEvent.mouseLocation)
        self.session = session
        let spec = app.switcherShortcutSettings.shortcut
        // Shift reverses cycling; releasing the primary modifiers commits.
        heldModifiers = []
        if spec.modifiers & UInt32(cmdKey) != 0 { heldModifiers.insert(.maskCommand) }
        if spec.modifiers & UInt32(optionKey) != 0 { heldModifiers.insert(.maskAlternate) }
        if spec.modifiers & UInt32(controlKey) != 0 { heldModifiers.insert(.maskControl) }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let width = min(CGFloat(rows.count) * 108 + 48, min(960, (screen?.visibleFrame.width ?? 960) - 48))
        let panel = self.panel ?? SearchPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.dismiss = nil
        panel.title = "Switch Desktop"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        let host = NSHostingController(rootView: DesktopSwitcherView(session: session, choose: { [weak self] index in
            self?.session?.selection = index
            self?.finish(commit: true)
        }))
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: max(420, width), height: 252))
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        } else { panel.center() }
        self.panel = panel
        panel.dismiss = { [weak self] in self?.finish(commit: false) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.session != nil else { return event }
            if event.type == .flagsChanged { self.checkRelease(); return event }
            switch event.keyCode {
            case 53: self.finish(commit: false)
            case 36, 76: self.finish(commit: true)
            case 123, 126: session.move(-1)
            case 124, 125: session.move(1)
            case UInt16(spec.keyCode): session.move(event.modifierFlags.contains(.shift) == (spec.modifiers & UInt32(shiftKey) != 0) ? 1 : -1)
            default: return event
            }
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Poll as well: a quick modifier release can precede panel activation.
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in self?.checkRelease() }
        checkRelease()
    }
    private func checkRelease() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if !flags.isSuperset(of: heldModifiers) { finish(commit: true) }
    }
    func finish(commit: Bool) {
        guard let session else { return }
        self.session = nil
        releaseTimer?.invalidate(); releaseTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        panel?.dismiss = nil
        panel?.orderOut(nil)
        if commit, session.rows.indices.contains(session.selection) {
            app?.switchDesktop(session.rows[session.selection].id)
        }
    }
}
