import AppKit
import SwiftUI

extension AppDelegate: NSWindowDelegate {
    func toggleSearch() {
        if searchWindow?.isVisible == true { hideSearch(); return }
        guard !switching, !managingSpaces, recordingShortcut == nil else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        popover.performClose(nil)
        refresh()
        let session = SearchSession()
        searchSession = session
        let controller = NSHostingController(rootView: SearchPanelView(
            desktops: panelState, session: session,
            choose: { [weak self] id in self?.chooseSearchResult(id) }
        ))
        let panel = searchWindow ?? SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
                                                styleMask: [.borderless], backing: .buffered, defer: false)
        panel.dismiss = nil
        panel.title = "Search Desktops"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = controller
        controller.view.wantsLayer = true
        controller.view.layer?.cornerRadius = 18
        controller.view.layer?.masksToBounds = true
        panel.setContentSize(NSSize(width: 520, height: 450))
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - 260, y: visible.midY - 150))
        } else { panel.center() }
        searchWindow = panel
        panel.dismiss = { [weak self] in self?.hideSearch() }
        if let searchKeyMonitor { NSEvent.removeMonitor(searchKeyMonitor) }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, panel?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { self.hideSearch(); return nil }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let results = DesktopSearch.results(self.panelState.rows, query: session.query)
            switch event.keyCode {
            case 125:
                session.navigate(by: 1, count: results.count, pointer: NSEvent.mouseLocation)
                return nil
            case 126:
                session.navigate(by: -1, count: results.count, pointer: NSEvent.mouseLocation)
                return nil
            case 36, 76:
                if results.indices.contains(session.selection) { self.chooseSearchResult(results[session.selection].id) }
                return nil
            default: return event
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func hideSearch() {
        if let searchKeyMonitor { NSEvent.removeMonitor(searchKeyMonitor); self.searchKeyMonitor = nil }
        // Avoid a resignKey → orderOut → resignKey callback cycle.
        searchWindow?.dismiss = nil
        searchWindow?.orderOut(nil)
        searchSession = nil
    }
    func chooseSearchResult(_ id: UInt64) {
        hideSearch()
        switchDesktop(id)
    }

    func openSettings() {
        popover.performClose(nil)
        hideSearch()
        loginItemSettings.refresh()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: ShortcutSettingsView(
                model: shortcutSettings,
                creationModel: creationShortcutSettings,
                switcherModel: switcherShortcutSettings,
                loginItem: loginItemSettings,
                record: { [weak self] in self?.toggleShortcutRecording() },
                restoreDefault: { [weak self] in self?.applyShortcut(.standard) },
                recordCreation: { [weak self] in self?.toggleShortcutRecording(for: .createDesktop) },
                restoreCreationDefault: { [weak self] in self?.applyShortcut(.createDesktop, for: .createDesktop) },
                recordSwitcher: { [weak self] in self?.toggleShortcutRecording(for: .switcher) },
                restoreSwitcherDefault: { [weak self] in self?.applyShortcut(.desktopSwitcher, for: .switcher) }
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "DeskNames Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.collectionBehavior = [.moveToActiveSpace]
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func shortcutState(for action: ShortcutAction) -> ShortcutSettingsState {
        switch action {
        case .search: return shortcutSettings
        case .createDesktop: return creationShortcutSettings
        case .switcher: return switcherShortcutSettings
        }
    }
    func shortcutRegistrar(for action: ShortcutAction) -> GlobalShortcut {
        switch action {
        case .search: return globalShortcut
        case .createDesktop: return creationShortcut
        case .switcher: return switcherShortcut
        }
    }
    func toggleShortcutRecording(for action: ShortcutAction = .search) {
        if recordingShortcut == action { stopShortcutRecording(restore: true); return }
        stopShortcutRecording(restore: true)
        let state = shortcutState(for: action)
        state.message = nil
        state.recording = true
        recordingShortcut = action
        // Suspend all shortcuts so recording another action’s combination can be
        // detected and rejected, rather than swallowed by its global handler.
        globalShortcut.unregister()
        creationShortcut.unregister()
        switcherShortcut.unregister()
        shortcutRecorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.settingsWindow?.isKeyWindow == true else { return event }
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                self.stopShortcutRecording(restore: true)
                return nil
            }
            guard let spec = ShortcutSpec.capture(event) else {
                state.message = "Include ⌘, ⌥, or ⌃ with a letter, number, or another key."
                return nil
            }
            self.applyShortcut(spec, for: action)
            return nil
        }
    }
    func stopShortcutRecording(restore: Bool) {
        if let shortcutRecorder { NSEvent.removeMonitor(shortcutRecorder); self.shortcutRecorder = nil }
        guard let action = recordingShortcut else { return }
        recordingShortcut = nil
        let state = shortcutState(for: action)
        state.recording = false
        restoreShortcutRegistrations(excluding: restore ? nil : action)
    }
    func restoreShortcutRegistrations(excluding excluded: ShortcutAction? = nil) {
        for action in [ShortcutAction.search, .createDesktop, .switcher] where action != excluded {
            let registrar = shortcutRegistrar(for: action)
            let state = shortcutState(for: action)
            if !registrar.isRegistered && registrar.register(state.shortcut) != noErr {
                state.message = "Couldn’t restore this shortcut. Please choose another combination."
            }
        }
    }
    func applyShortcut(_ spec: ShortcutSpec, for action: ShortcutAction = .search) {
        guard spec.valid else { return }
        let state = shortcutState(for: action)
        let registrar = shortcutRegistrar(for: action)
        let bindings = action == .switcher ? [spec, spec.reversed] : [spec]
        let conflicts = [ShortcutAction.search, .createDesktop, .switcher].filter { $0 != action }.contains { other in
            let otherSpec = shortcutState(for: other).shortcut
            let otherBindings = other == .switcher ? [otherSpec, otherSpec.reversed] : [otherSpec]
            return bindings.contains { candidate in otherBindings.contains { candidate.hasSameBinding(as: $0) } }
        }
        guard !conflicts else {
            stopShortcutRecording(restore: true)
            state.message = "Each action needs a different shortcut. The switcher also reserves its Shift variant."
            return
        }
        if spec.hasSameBinding(as: state.shortcut) && !state.recording && registrar.isRegistered {
            state.message = nil
            return
        }
        let error = registrar.register(spec)
        if error == noErr {
            stopShortcutRecording(restore: false)
            state.save(spec)
            state.message = nil
            panelState.shortcutLabel = shortcutSettings.shortcut.display
            panelState.creationShortcutLabel = creationShortcutSettings.shortcut.display
        } else {
            stopShortcutRecording(restore: true)
            state.message = "That shortcut is unavailable or in use by another app. Try a different combination."
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !(sender === newDesktopWindow && creationSession?.busy == true)
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === newDesktopWindow {
            creationSession = nil
        }
        if let window = notification.object as? NSWindow, window === settingsWindow {
            stopShortcutRecording(restore: true)
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            stopShortcutRecording(restore: true)
        }
    }

    // Both the menu button and the global shortcut open the same creation form.
    func addDesktop() { openNewDesktopWindow() }
    func removeDesktop(_ id: UInt64) {
        guard !managingSpaces, !switching else { return }
        guard AXIsProcessTrusted() else { permissionHelp(); return }
        guard let snapshot = reader.snapshot(),
              let desktop = snapshot.desktops.first(where: { $0.id == id }),
              SpaceManagementPolicy.canRemove(id, from: snapshot.desktops) else {
            show("Keep one desktop", "The last regular desktop on a display cannot be removed. Full-screen app Spaces are managed by their apps.")
            return
        }
        popover.performClose(nil)
        hideSearch()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove “\(title(desktop))”?"
        alert.informativeText = "Its windows will move to another desktop. Your apps will stay open."
        alert.addButton(withTitle: "Remove Desktop")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].contentTintColor = .systemRed
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let latest = reader.snapshot(forDisplay: snapshot.displayIdentifier),
              SpaceManagementPolicy.canRemove(id, from: latest.desktops) else {
            show("Desktop changed", "The desktop list changed. Please try again."); return
        }
        managingSpaces = true
        refresh()
        if latest.active == id {
            guard let alternate = SpaceManagementPolicy.alternate(for: id, in: latest.desktops),
                  let number = alternate.shortcutNumber else {
                finishSpaceChange("Switch to another regular desktop before removing this one."); return
            }
            if let error = directSwitcher.jump(to: number) {
                finishSpaceChange(error); return
            }
            awaitRemovalDestination(id, key: desktop.key, display: snapshot.displayIdentifier, attempts: 35)
        } else {
            spaceManager.remove(id, on: latest) { [weak self] error in
                self?.finishSpaceChange(error, removedKey: error == nil ? desktop.key : nil)
            }
        }
    }
    private func awaitRemovalDestination(_ id: UInt64, key: String, display: String, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let snapshot = self.reader.snapshot(forDisplay: display),
                  SpaceManagementPolicy.canRemove(id, from: snapshot.desktops) else {
                self.finishSpaceChange("The desktop list changed. Please try again."); return
            }
            if snapshot.active != id {
                self.spaceManager.remove(id, on: snapshot) { [weak self] error in
                    self?.finishSpaceChange(error, removedKey: error == nil ? key : nil)
                }
            } else if attempts > 0 {
                self.awaitRemovalDestination(id, key: key, display: display, attempts: attempts - 1)
            } else { self.finishSpaceChange("macOS couldn’t switch away from the desktop. Switch manually, then remove it again.") }
        }
    }
    private func finishSpaceChange(_ error: String?, removedKey: String? = nil) {
        managingSpaces = false
        if let removedKey {
            names.removeValue(forKey: removedKey)
            appearances.removeValue(forKey: removedKey)
            UserDefaults.standard.set(names, forKey: "desktopNames")
            if let data = try? JSONEncoder().encode(appearances) { UserDefaults.standard.set(data, forKey: "desktopAppearances") }
        }
        refresh()
        if let error { show("Desktop change wasn’t completed", error) }
        else if !popover.isShown { togglePanel() }
    }
}
