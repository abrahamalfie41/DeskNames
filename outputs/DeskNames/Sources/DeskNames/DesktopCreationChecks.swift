import Foundation

enum DesktopCreationChecks {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { failures.append(name) }
        }
        let form = DesktopCreationSession(displayIdentifier: "display-A")
        check(!form.canSubmit, "A name is required before creating")
        form.name = " \n "
        check(!form.canSubmit, "Whitespace-only names are rejected")
        form.name = "  Design  "
        form.appearance = .init(icon: "paintpalette.fill", tint: "purple")
        check(form.canSubmit && form.normalizedName == "Design", "Creation name is trimmed")
        check(form.appearance.icon == "paintpalette.fill" && form.appearance.tint == "purple", "Chosen icon and color stay in the draft")
        form.busy = true
        check(!form.canSubmit, "Repeated submission is prevented while creating")
        form.busy = false
        form.name = String(repeating: "字", count: 90)
        check(form.normalizedName.count == 80, "Creation names use the same length limit as edits")
        check(form.displayIdentifier == "display-A", "The form keeps its original display")
        check(ShortcutSpec.createDesktop.valid && ShortcutSpec.createDesktop.display == "⇧⌘0", "New desktop default is Command-Shift-0")
        check(!ShortcutSpec.createDesktop.hasSameBinding(as: .standard), "Search and creation have different defaults")
        let differentLabel = ShortcutSpec(keyCode: ShortcutSpec.createDesktop.keyCode, modifiers: ShortcutSpec.createDesktop.modifiers, keyLabel: ")")
        check(differentLabel.hasSameBinding(as: .createDesktop), "Shortcut conflicts compare keys and modifiers, not display labels")
        if let data = try? JSONEncoder().encode(ShortcutSpec.createDesktop), let restored = try? JSONDecoder().decode(ShortcutSpec.self, from: data) {
            check(restored == .createDesktop, "Creation shortcut survives serialization")
        } else { failures.append("Creation shortcut serialization") }
        func desktop(_ id: UInt64, fullscreen: Bool = false) -> Desktop {
            Desktop(id: id, key: "uuid-\(id)", number: Int(id), fullscreen: fullscreen, shortcutNumber: fullscreen ? nil : Int(id))
        }
        let before = [desktop(1), desktop(2)]
        let added = desktop(5)
        check(SpaceManagementPolicy.createdDesktop(before: before, after: before + [added])?.key == "uuid-5", "Appearance attaches to the newly created identity")
        check(SpaceManagementPolicy.createdDesktop(before: before, after: [desktop(2), added, desktop(1)])?.id == 5, "Identification does not guess using desktop position")
        check(SpaceManagementPolicy.createdDesktop(before: before, after: before) == nil, "An unchanged list is not a successful creation")
        check(SpaceManagementPolicy.createdDesktop(before: before, after: before + [added, desktop(6)]) == nil, "Concurrent additions are ambiguous and not customized")
        check(SpaceManagementPolicy.createdDesktop(before: before, after: [desktop(1), added]) == nil, "Concurrent removal is rejected")
        check(SpaceManagementPolicy.createdDesktop(before: before, after: before + [desktop(7, fullscreen: true)]) == nil, "A full-screen Space is not treated as a new desktop")
        if failures.isEmpty {
            print("PASS: new-desktop draft validation, shortcut separation, and exact created-desktop identity. No Spaces created or preferences changed.")
            return true
        }
        for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
        return false
    }
}
