import Foundation
import Carbon

enum FeatureChecks {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if !condition() { failures.append(name) }
        }
        func row(_ id: UInt64, _ name: String, _ number: Int, switchable: Bool = true) -> DesktopPanelRow {
            DesktopPanelRow(id: id, key: "key-\(id)", title: name, customName: name,
                            subtitle: "Desktop \(number)", current: id == 1,
                            appearance: .initial(key: "key-\(id)", title: name),
                            switchable: switchable, removable: true)
        }
        let rows = [row(1, "Client Work", 1), row(2, "Work", 2), row(3, "Workshop", 3),
                    row(4, "Café & Notes", 4), row(5, "Study", 5), row(6, "Full-screen Work", 0, switchable: false)]
        check(DesktopSearch.results(rows, query: "work").map(\.id) == [2, 3, 1], "Exact names precede prefixes and substrings")
        check(DesktopSearch.results(rows, query: "  WORK ").map(\.id) == [2, 3, 1], "Case and surrounding whitespace")
        check(DesktopSearch.results(rows, query: "cafe").map(\.id) == [4], "Diacritic-insensitive names")
        check(DesktopSearch.results(rows, query: "client 1").map(\.id) == [1], "Multiple terms across name and desktop number")
        check(DesktopSearch.results(rows, query: "5").map(\.id) == [5], "Search by desktop number")
        check(DesktopSearch.results(rows, query: "").map(\.id) == [1, 2, 3, 4, 5], "Blank query excludes unsupported Spaces")
        check(DesktopSearch.results(rows, query: "missing").isEmpty, "No-match search")
        check(DesktopSearch.movedIndex(0, by: -1, count: 5) == 0, "Up at first result")
        check(DesktopSearch.movedIndex(4, by: 1, count: 5) == 4, "Down at last result")
        check(DesktopSearch.movedIndex(8, by: 0, count: 2) == 1, "Selection after results shrink")
        check(DesktopSearch.movedIndex(0, by: 1, count: 0) == 0, "Navigation without results")
        let session = SearchSession()
        session.selection = 4
        session.query = "work"
        check(session.selection == 0, "Typing resets selection to the first match")
        let pointer = CGPoint(x: 100, y: 100)
        session.navigate(by: 1, count: 5, pointer: pointer)
        session.hover(index: 4, pointer: pointer)
        check(session.selection == 1, "Stationary pointer cannot override arrow navigation")
        session.navigate(by: 1, count: 5, pointer: pointer)
        session.hover(index: 0, pointer: pointer)
        check(session.selection == 2, "Scrolling beneath the pointer preserves keyboard selection")
        session.hover(index: 3, pointer: CGPoint(x: 101, y: 100))
        check(session.selection == 3, "Actual mouse movement resumes pointer selection")
        session.navigate(by: -1, count: 5, pointer: CGPoint(x: 101, y: 100))
        session.hover(index: 4, pointer: CGPoint(x: 101, y: 100))
        check(session.selection == 2, "Arrow navigation takes priority again after mouse use")
        var recency = DesktopRecency()
        recency.visit("key-3")
        recency.visit("key-2")
        recency.visit("key-1")
        recency.visit("key-1")
        check(recency.keys == ["key-1", "key-2", "key-3"], "Recency deduplicates repeated observations")
        let ordered = recency.ordered(rows)
        check(ordered.map(\.id) == [1, 2, 3, 4, 5], "Current desktop first, then recency, excluding unsupported Spaces")
        let switcher = DesktopSwitcherSession(rows: ordered, reverse: false)
        check(switcher.selection == 1, "Quick switch selects the previous desktop")
        switcher.move(-2, pointer: pointer)
        check(switcher.selection == 4, "Desktop switcher wraps backward")
        switcher.move(1, pointer: pointer)
        check(switcher.selection == 0, "Desktop switcher wraps forward")
        switcher.hover(3, pointer: pointer)
        check(switcher.selection == 0, "Switcher ignores hover beneath a stationary pointer")
        switcher.hover(3, pointer: CGPoint(x: 101, y: 100))
        check(switcher.selection == 3, "Switcher permits mouse selection after movement")
        check(DesktopSwitcherSession(rows: ordered, reverse: true).selection == 4, "Reverse invocation starts at the last desktop")
        let noCurrent = DesktopSwitcherSession(rows: Array(ordered.dropFirst()), reverse: false)
        check(noCurrent.selection == 0, "Full-screen current Space does not skip the most recent regular desktop")
        let emptySwitcher = DesktopSwitcherSession(rows: [], reverse: false)
        emptySwitcher.move(1, pointer: pointer)
        check(emptySwitcher.selection == 0, "Empty switcher navigation is safe")
        check(ShortcutSpec.desktopSwitcher.display == "⌥Tab", "Default desktop switcher shortcut")
        check(ShortcutSpec.desktopSwitcher.reversed.display == "⌥⇧Tab", "Reverse cycling reserves Shift variant")
        check(ShortcutSpec.desktopSwitcher.reversed.reversed == .desktopSwitcher, "Reversing twice restores the binding")
        check(ShortcutSpec.standard.valid && ShortcutSpec.standard.display == "⌘0", "Default search shortcut")
        let custom = ShortcutSpec(keyCode: 40, modifiers: UInt32(controlKey | optionKey), keyLabel: "K")
        check(custom.valid && custom.display == "⌃⌥K", "Custom shortcut modifiers and label")
        check(!ShortcutSpec(keyCode: 40, modifiers: UInt32(shiftKey), keyLabel: "K").valid, "Typing shortcuts cannot use Shift alone")
        check(!ShortcutSpec(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "Command").valid, "Modifier-only shortcut rejected")
        if let encoded = try? JSONEncoder().encode(custom), let decoded = try? JSONDecoder().decode(ShortcutSpec.self, from: encoded) {
            check(decoded == custom, "Custom shortcut persistence")
        } else { failures.append("Custom shortcut persistence") }
        func desktop(_ id: UInt64, fullscreen: Bool = false) -> Desktop {
            Desktop(id: id, key: "key-\(id)", number: Int(id), fullscreen: fullscreen, shortcutNumber: fullscreen ? nil : Int(id))
        }
        let only = [desktop(1), desktop(9, fullscreen: true)]
        let multiple = [desktop(1), desktop(9, fullscreen: true), desktop(2), desktop(3)]
        check(!SpaceManagementPolicy.canRemove(1, from: only), "The last regular desktop is protected")
        check(!SpaceManagementPolicy.canRemove(9, from: multiple), "Full-screen app Spaces are protected")
        check(!SpaceManagementPolicy.canRemove(77, from: multiple), "A stale desktop target is rejected")
        check(SpaceManagementPolicy.canRemove(2, from: multiple), "Another regular desktop can be removed")
        check(SpaceManagementPolicy.alternate(for: 2, in: multiple)?.id == 3, "Switch away before removal, skipping full-screen Spaces")
        check(SpaceManagementPolicy.alternate(for: 1, in: only) == nil, "No alternate for the last desktop")
        if failures.isEmpty {
            guard LoginItemChecks.run(), DesktopCreationChecks.run() else { return false }
            print("PASS: search and desktop switcher navigation, recency, mouse priority, shortcut defaults/persistence, and removal safeguards. No global shortcuts registered and no Spaces changed.")
            return true
        }
        for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
        return false
    }
}
