import AppKit
import SwiftUI

// Pure matching and ranking: testable without opening a window or changing Spaces.
enum DesktopSearch {
    static func results(_ rows: [DesktopPanelRow], query: String) -> [DesktopPanelRow] {
        let normalized = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let candidates = rows.filter(\.switchable)
        guard !normalized.isEmpty else { return candidates }
        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        return candidates.enumerated().compactMap { index, row -> (Int, Int, DesktopPanelRow)? in
            let name = fold(row.title)
            let searchable = name + " " + fold(row.subtitle)
            guard words.allSatisfy({ searchable.contains($0) }) else { return nil }
            let rank = name == normalized ? 0 : (name.hasPrefix(normalized) ? 1 : 2)
            return (rank, index, row)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { $0.2 }
    }
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func movedIndex(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }
}

final class SearchSession: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var selection = 0
    private var keyboardPointerLocation: NSPoint?

    func navigate(by delta: Int, count: Int, pointer: NSPoint) {
        // Scrolling can generate hover callbacks beneath a stationary pointer.
        keyboardPointerLocation = pointer
        selection = DesktopSearch.movedIndex(selection, by: delta, count: count)
    }

    func hover(index: Int, pointer: NSPoint) {
        if let locked = keyboardPointerLocation, locked == pointer { return }
        keyboardPointerLocation = nil
        selection = index
    }
}

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var dismiss: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func resignKey() { super.resignKey(); dismiss?() }
}

struct SearchPanelView: View {
    @ObservedObject var desktops: DesktopPanelState
    @ObservedObject var session: SearchSession
    let choose: (UInt64) -> Void
    @FocusState private var focused: Bool
    private var results: [DesktopPanelRow] { DesktopSearch.results(desktops.rows, query: session.query) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .medium)).foregroundStyle(.blue)
                TextField("Search desktops…", text: $session.query)
                    .textFieldStyle(.plain).font(.system(size: 22, weight: .medium, design: .rounded))
                    .focused($focused).accessibilityLabel("Search desktop names")
                if !session.query.isEmpty {
                    Button { session.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(.horizontal, 24).padding(.vertical, 23)
            Divider()
            if results.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("No desktops found").font(.system(size: 14, weight: .semibold))
                    Text("Try another name or desktop number.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 330)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                                Button { choose(row.id) } label: {
                                    HStack(spacing: 13) {
                                        DesktopBadge(appearance: row.appearance, size: 38)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(row.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                            Text(row.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if row.current { Text("Current").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                                        if session.selection == index {
                                            Image(systemName: "return").foregroundStyle(.blue).font(.system(size: 13, weight: .medium))
                                        }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                                    .background(session.selection == index ? Color.blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain).id(row.id)
                                .onContinuousHover { phase in
                                    if case .active = phase {
                                        session.hover(index: index, pointer: NSEvent.mouseLocation)
                                    }
                                }
                                .accessibilityLabel("Switch to \(row.title)\(row.current ? ", current desktop" : "")")
                            }
                        }.padding(10)
                    }
                    .frame(height: 330)
                    .onChange(of: session.selection) { index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id, anchor: .center) }
                    }
                }
            }
            Divider()
            HStack(spacing: 18) {
                Text("↑ ↓  Navigate")
                Text("↵  Switch")
                Spacer()
                Text("esc  Close")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 13)
        }
        .frame(width: 520).background(Color(nsColor: .windowBackgroundColor))
        .onAppear { focused = true }
        .onChange(of: desktops.rows) { _ in
            session.selection = DesktopSearch.movedIndex(session.selection, by: 0, count: results.count)
        }
    }
}
