import AppKit
import ApplicationServices

struct DesktopSnapshot {
    let desktops: [Desktop]
    let active: UInt64
    let displayIdentifier: String
    let displayID: CGDirectDisplayID
}

// These checks run both before opening Mission Control and again before its action.
enum SpaceManagementPolicy {
    static func canRemove(_ target: UInt64, from desktops: [Desktop]) -> Bool {
        desktops.contains { $0.id == target && !$0.fullscreen }
            && desktops.filter { !$0.fullscreen }.count > 1
    }
    static func createdDesktop(before: [Desktop], after: [Desktop]) -> Desktop? {
        let original = Set(before.map(\.id))
        let current = Set(after.map(\.id))
        let added = after.filter { !original.contains($0.id) }
        guard original.isSubset(of: current), added.count == 1, !added[0].fullscreen else { return nil }
        return added[0]
    }
    static func alternate(for target: UInt64, in desktops: [Desktop]) -> Desktop? {
        guard canRemove(target, from: desktops), let index = desktops.firstIndex(where: { $0.id == target }) else { return nil }
        return desktops.enumerated().filter { !$0.element.fullscreen && $0.element.id != target }
            .min { abs($0.offset - index) < abs($1.offset - index) }?.element
    }
}

// Use the Dock's own add/remove actions so macOS handles moving windows safely.
// Mission Control is visible briefly. No Dock injection or SIP changes are needed.
final class SpaceManager {
    private let reader: SpacesReader
    private let missionControlURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    private var ownsMissionControl = false
    private var inProgress = false
    private var controlsReadyAfter = Date.distantPast
    init(reader: SpacesReader) { self.reader = reader }

    func add(on snapshot: DesktopSnapshot, completion: @escaping (Desktop?, String?) -> Void) {
        perform(snapshot: snapshot, removing: nil) { [weak self] error in
            if let error { completion(nil, error); return }
            guard let latest = self?.reader.snapshot(forDisplay: snapshot.displayIdentifier),
                  let created = SpaceManagementPolicy.createdDesktop(before: snapshot.desktops, after: latest.desktops) else {
                completion(nil, "A desktop was added, but it couldn’t be identified safely. Check the desktop panel and customize it there before trying again.")
                return
            }
            completion(created, nil)
        }
    }
    func remove(_ target: UInt64, on snapshot: DesktopSnapshot, completion: @escaping (String?) -> Void) {
        guard SpaceManagementPolicy.canRemove(target, from: snapshot.desktops) else {
            completion("Keep at least one regular desktop on this display. Full-screen app Spaces are managed by their apps.")
            return
        }
        guard snapshot.active != target else {
            completion("Switch to another desktop before removing this one.")
            return
        }
        perform(snapshot: snapshot, removing: target, completion: completion)
    }
    private func perform(snapshot: DesktopSnapshot, removing target: UInt64?, completion: @escaping (String?) -> Void) {
        guard !inProgress else { completion("Another desktop change is still in progress."); return }
        guard AXIsProcessTrusted() else { completion("Enable Accessibility access for DeskNames first."); return }
        if target == nil && snapshot.desktops.filter({ !$0.fullscreen }).count >= 16 {
            completion("This display already has the maximum of 16 desktops."); return
        }
        inProgress = true
        ownsMissionControl = missionControl() == nil
        controlsReadyAfter = Date().addingTimeInterval(ownsMissionControl ? 0.45 : 0.15)
        if ownsMissionControl && !NSWorkspace.shared.open(missionControlURL) {
            finish("Mission Control could not be opened.", completion: completion); return
        }
        waitForControls(snapshot: snapshot, removing: target, attempts: 30, completion: completion)
    }
    private func waitForControls(snapshot: DesktopSnapshot, removing target: UInt64?, attempts: Int, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if Date() < self.controlsReadyAfter {
                self.waitForControls(snapshot: snapshot, removing: target, attempts: attempts, completion: completion)
                return
            }
            guard let group = self.missionControl(),
                  let display = self.children(group).first(where: {
                      self.string($0, "AXIdentifier") == "mc.display"
                          && (self.attribute($0, "AXDisplayID") as? NSNumber)?.uint32Value == snapshot.displayID
                  }),
                  let spaces = self.children(display).first(where: { self.string($0, "AXIdentifier") == "mc.spaces" }) else {
                if attempts > 0 {
                    self.waitForControls(snapshot: snapshot, removing: target, attempts: attempts - 1, completion: completion)
                } else { self.finish("macOS did not expose the Mission Control desktop controls. Try again after closing Mission Control.", completion: completion) }
                return
            }
            guard let latest = self.reader.snapshot(forDisplay: snapshot.displayIdentifier),
                  latest.desktops.map(\.id) == snapshot.desktops.map(\.id) else {
                self.finish("The desktop order changed. Please try again.", completion: completion); return
            }
            let control: AXUIElement
            let action: CFString
            if let target {
                guard latest.active != target,
                      SpaceManagementPolicy.canRemove(target, from: latest.desktops),
                      let list = self.children(spaces).first(where: { self.string($0, "AXIdentifier") == "mc.spaces.list" }),
                      let index = latest.desktops.firstIndex(where: { $0.id == target }) else {
                    self.finish("This desktop can’t be removed right now. Switch to another desktop and try again.", completion: completion); return
                }
                let buttons = self.children(list)
                guard buttons.count == latest.desktops.count, buttons.indices.contains(index) else {
                    self.finish("The Mission Control desktop list changed. Please try again.", completion: completion); return
                }
                control = buttons[index]
                action = "AXRemoveDesktop" as CFString
            } else {
                guard let add = self.children(spaces).first(where: { self.string($0, "AXIdentifier") == "mc.spaces.add" }) else {
                    self.finish("macOS’s Add Desktop button is unavailable.", completion: completion); return
                }
                control = add
                action = kAXPressAction as CFString
            }
            guard AXUIElementPerformAction(control, action) == .success else {
                self.finish("macOS didn’t accept the desktop change. Please try again.", completion: completion); return
            }
            self.verify(snapshot: snapshot, removing: target, attempts: 30, completion: completion)
        }
    }
    private func verify(snapshot: DesktopSnapshot, removing target: UInt64?, attempts: Int, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let latest = self.reader.snapshot(forDisplay: snapshot.displayIdentifier) {
                let changed = target.map { id in !latest.desktops.contains { $0.id == id } }
                    ?? latest.desktops.contains { desktop in !snapshot.desktops.contains { $0.id == desktop.id } }
                if changed { self.finish(nil, completion: completion); return }
            }
            if attempts > 0 { self.verify(snapshot: snapshot, removing: target, attempts: attempts - 1, completion: completion) }
            else { self.finish("The requested desktop change could not be verified. Check Mission Control before trying again.", completion: completion) }
        }
    }
    private func finish(_ error: String?, completion: @escaping (String?) -> Void) {
        if ownsMissionControl && missionControl() != nil { _ = NSWorkspace.shared.open(missionControlURL) }
        ownsMissionControl = false
        inProgress = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion(error) }
    }
    private func missionControl() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        return children(root).first { string($0, "AXIdentifier") == "mc" }
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
}
