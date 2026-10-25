import AppKit
import ApplicationServices
import SwiftUI

final class DesktopCreationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var dismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func resignKey() { super.resignKey(); dismiss?() }
}

final class DesktopCreationSession: ObservableObject {
    let displayIdentifier: String
    @Published var name = ""
    @Published var appearance = DesktopAppearance(icon: "display", tint: "blue")
    @Published var busy = false
    @Published var error: String?
    init(displayIdentifier: String) { self.displayIdentifier = displayIdentifier }
    var normalizedName: String { String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
    var canSubmit: Bool { !busy && !normalizedName.isEmpty }
}

struct NewDesktopView: View {
    @ObservedObject var session: DesktopCreationSession
    let create: () -> Void
    let cancel: () -> Void
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        DesktopBadge(appearance: session.appearance, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("New Desktop").font(.system(size: 21, weight: .semibold, design: .rounded))
                            Text("Choose a name, icon, and color.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Name").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("Work, Study, Personal…", text: $session.name)
                            .textFieldStyle(.roundedBorder).font(.system(size: 13))
                            .focused($nameFocused).accessibilityLabel("New desktop name")
                            .onSubmit { if session.canSubmit { create() } }
                    }
                    DesktopAppearanceControls(appearance: $session.appearance)
                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(24).disabled(session.busy)
            }
            Divider()
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).disabled(session.busy)
                Spacer()
                if session.busy { ProgressView().controlSize(.small) }
                Button(session.busy ? "Creating…" : "Create Desktop", action: create)
                    .buttonStyle(.borderedProminent).tint(session.appearance.palette.color)
                    .keyboardShortcut(.defaultAction).disabled(!session.canSubmit)
            }.padding(18)
        }
        .frame(width: 380, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { nameFocused = true }
    }
}

extension AppDelegate {
    func openNewDesktopWindow() {
        guard !switching, !managingSpaces, recordingShortcut == nil, NSApp.modalWindow == nil else { return }
        popover.performClose(nil)
        hideSearch()
        if newDesktopWindow?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            newDesktopWindow?.makeKeyAndOrderFront(nil)
            return
        }
        guard let snapshot = reader.snapshot() else {
            show("Desktop unavailable", "Please try again after reopening DeskNames."); return
        }
        guard snapshot.desktops.filter({ !$0.fullscreen }).count < 16 else {
            show("Desktop limit reached", "This display already has 16 regular desktops."); return
        }
        let session = DesktopCreationSession(displayIdentifier: snapshot.displayIdentifier)
        creationSession = session
        let controller = NSHostingController(rootView: NewDesktopView(
            session: session,
            create: { [weak self] in self?.createDesktopFromForm() },
            cancel: { [weak self] in self?.hideNewDesktopPopup() }
        ))
        let window = newDesktopWindow ?? DesktopCreationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.dismiss = nil
        window.contentViewController = controller
        window.title = "New Desktop"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        controller.view.wantsLayer = true
        controller.view.layer?.cornerRadius = 18
        controller.view.layer?.masksToBounds = true
        window.setContentSize(NSSize(width: 380, height: 540))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == snapshot.displayID
        }) {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else { window.center() }
        newDesktopWindow = window
        window.dismiss = { [weak self] in self?.hideNewDesktopPopup() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hideNewDesktopPopup() {
        guard creationSession?.busy != true else { return }
        newDesktopWindow?.dismiss = nil
        newDesktopWindow?.orderOut(nil)
        creationSession = nil
    }

    func createDesktopFromForm() {
        guard let session = creationSession, session.canSubmit, !managingSpaces, !switching else { return }
        guard AXIsProcessTrusted() else {
            // Keep the draft while the targeted permission dialog takes focus.
            newDesktopWindow?.dismiss = nil
            newDesktopWindow?.orderOut(nil)
            permissionHelp()
            newDesktopWindow?.dismiss = { [weak self] in self?.hideNewDesktopPopup() }
            NSApp.activate(ignoringOtherApps: true)
            newDesktopWindow?.makeKeyAndOrderFront(nil)
            return
        }
        guard let snapshot = reader.snapshot(forDisplay: session.displayIdentifier) else {
            session.error = "This display is no longer available. Dismiss this popup and open New Desktop again."; return
        }
        let name = session.normalizedName
        let appearance = session.appearance
        session.busy = true
        session.error = nil
        managingSpaces = true
        newDesktopWindow?.dismiss = nil
        newDesktopWindow?.orderOut(nil)
        refresh()
        spaceManager.add(on: snapshot) { [weak self] created, error in
            guard let self else { return }
            self.managingSpaces = false
            session.busy = false
            guard let created, error == nil else {
                session.error = error ?? "macOS didn’t create a desktop. Please try again."
                self.refresh()
                self.newDesktopWindow?.dismiss = { [weak self] in self?.hideNewDesktopPopup() }
                NSApp.activate(ignoringOtherApps: true)
                self.newDesktopWindow?.makeKeyAndOrderFront(nil)
                return
            }
            // The backend returns the one newly observed UUID; existing desktop
            // preferences are never used as a guessed destination for the draft.
            self.saveDesktop(key: created.key, name: name, appearance: appearance)
            self.hideNewDesktopPopup()
            self.refresh()
            if !self.popover.isShown { self.togglePanel() }
        }
    }
}
