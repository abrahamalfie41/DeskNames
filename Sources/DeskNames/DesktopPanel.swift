import AppKit
import SwiftUI

struct DesktopTint: Identifiable {
    let id: String
    let name: String
    let native: NSColor
    var color: Color { Color(nsColor: native) }
    static let all: [DesktopTint] = [
        .init(id: "blue", name: "Blue", native: .systemBlue),
        .init(id: "teal", name: "Teal", native: .systemTeal),
        .init(id: "green", name: "Green", native: .systemGreen),
        .init(id: "orange", name: "Orange", native: .systemOrange),
        .init(id: "pink", name: "Pink", native: .systemPink),
        .init(id: "purple", name: "Purple", native: .systemPurple),
        .init(id: "indigo", name: "Indigo", native: .systemIndigo),
        .init(id: "cyan", name: "Cyan", native: .systemCyan),
        .init(id: "mint", name: "Mint", native: .systemMint),
        .init(id: "red", name: "Red", native: .systemRed),
        .init(id: "brown", name: "Brown", native: .systemBrown),
        .init(id: "gray", name: "Graphite", native: .systemGray)
    ]
}

struct DesktopAppearance: Codable, Equatable {
    var icon: String
    var tint: String
    var palette: DesktopTint { DesktopTint.all.first { $0.id == tint } ?? DesktopTint.all[0] }
    static let icons: [(symbol: String, name: String)] = [
        ("display", "Desktop"), ("briefcase.fill", "Work"), ("house.fill", "Home"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("book.closed.fill", "Study"),
        ("paintpalette.fill", "Design"), ("bubble.left.and.bubble.right.fill", "Messages"),
        ("music.note", "Music"), ("safari.fill", "Browse"),
        ("gamecontroller.fill", "Games"), ("moon.fill", "Focus"), ("star.fill", "Favorite"),
        ("sum", "Summation"), ("function", "Function"), ("x.squareroot", "Square Root"),
        ("infinity", "Infinity"), ("divide", "Division"), ("plus.forwardslash.minus", "Plus / Minus"),
        ("equal", "Equality"), ("number", "Number Theory"), ("chart.xyaxis.line", "Graphs"),
        ("terminal.fill", "Terminal"), ("curlybraces", "Programming"), ("cpu", "Processor"),
        ("memorychip", "Memory"), ("network", "Networks"), ("externaldrive.fill", "Storage"),
        ("point.3.connected.trianglepath.dotted", "Algorithms"), ("lock.shield", "Security"),
        ("server.rack", "Servers")
    ]
    static func initial(key: String, title: String) -> DesktopAppearance {
        let checksum = key.utf8.reduce(0) { ($0 + Int($1)) % 997 }
        let title = title.lowercased()
        let symbol: String
        if title.contains("work") { symbol = "briefcase.fill" }
        else if title.contains("home") || title.contains("personal") { symbol = "house.fill" }
        else if title.contains("code") || title.contains("dev") { symbol = "chevron.left.forwardslash.chevron.right" }
        else if title.contains("study") || title.contains("read") { symbol = "book.closed.fill" }
        else if title.contains("design") { symbol = "paintpalette.fill" }
        else if title.contains("music") { symbol = "music.note" }
        else { symbol = "display" }
        return .init(icon: symbol, tint: DesktopTint.all[checksum % 6].id)
    }
}

struct DesktopPanelRow: Identifiable, Equatable {
    let id: UInt64
    let key: String
    let title: String
    let customName: String
    let subtitle: String
    let current: Bool
    let appearance: DesktopAppearance
    let switchable: Bool
    let removable: Bool
}

final class DesktopPanelState: ObservableObject {
    @Published var rows: [DesktopPanelRow] = []
    @Published var switching = false
    @Published var error: String?
    @Published var canAdd = true
    @Published var shortcutLabel = "⌘0"
    @Published var creationShortcutLabel = "⇧⌘0"
}

struct DesktopBadge: View {
    let appearance: DesktopAppearance
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: appearance.icon)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(appearance.palette.color)
            .frame(width: size, height: size)
            .background(appearance.palette.color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(appearance.palette.color.opacity(0.1)))
            .accessibilityHidden(true)
    }
}

private struct DesktopRowView: View {
    let row: DesktopPanelRow
    let busy: Bool
    let select: () -> Void
    let edit: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 11) {
                    DesktopBadge(appearance: row.appearance)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(row.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if row.current {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(row.appearance.palette.color)
                            .accessibilityLabel("Current desktop")
                    }
                }
                .padding(.leading, 10).padding(.vertical, 10).padding(.trailing, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel("\(row.title), \(row.subtitle)\(row.current ? ", current desktop" : "")")
            .help(row.current ? "You’re here" : "Jump to \(row.title)")
            Button(action: edit) {
                Image(systemName: "pencil").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 30, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.trailing, 4)
            .disabled(busy)
            .help("Customize \(row.title)")
            .accessibilityLabel("Customize \(row.title)")
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(row.current ? row.appearance.palette.color.opacity(0.09) : (hovering ? Color.primary.opacity(0.045) : .clear))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(row.current ? row.appearance.palette.color.opacity(0.22) : .clear)
        }
        .onHover { hovering = $0 }
        .deskAnimation(value: hovering)
        .deskAnimation(value: row.current)
    }
}

struct DesktopPanelView: View {
    @ObservedObject var model: DesktopPanelState
    let select: (UInt64) -> Void
    let save: (String, String, DesktopAppearance) -> Void
    let help: () -> Void
    let permissions: () -> Void
    let search: () -> Void
    let settings: () -> Void
    let add: () -> Void
    let remove: (UInt64) -> Void
    let quit: () -> Void
    @State private var editing: DesktopPanelRow?

    var body: some View {
        Group {
            if let row = editing {
                DesktopEditor(row: row, save: { name, appearance in
                    save(row.key, name, appearance)
                    editing = nil
                }, cancel: { editing = nil }, remove: {
                    editing = nil
                    remove(row.id)
                })
                .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.blue.gradient)
                            .frame(width: 34, height: 34)
                            .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Desktops").font(.system(size: 19, weight: .semibold, design: .rounded))
                            Text("\(model.rows.count) spaces currently active")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Settings…", systemImage: "gearshape", action: settings)
                            Button("Search Desktops…", systemImage: "magnifyingglass", action: search)
                            Divider()
                            Button("DeskNames Help", systemImage: "questionmark.circle", action: help)
                            Button("Accessibility Settings", systemImage: "hand.raised", action: permissions)
                            Divider()
                            Button("Quit DeskNames", systemImage: "power", action: quit)
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("DeskNames options")
                    }
                    .padding(.horizontal, 5).padding(.top, 3)
                    HStack(spacing: 8) {
                        Button(action: search) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                Text("Search")
                                Spacer()
                                Text(model.shortcutLabel).foregroundStyle(.secondary)
                            }.font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 8)
                        }.buttonStyle(.plain)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        Button(action: add) {
                            Label("New Desktop", systemImage: "plus").font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 9).padding(.vertical, 8)
                        }.buttonStyle(.plain).foregroundStyle(.blue)
                            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .disabled(!model.canAdd || model.switching)
                            .help("New Desktop (\(model.creationShortcutLabel))")
                    }
                    if let error = model.error {
                        VStack(spacing: 8) {
                            Image(systemName: "display.trianglebadge.exclamationmark").font(.title).foregroundStyle(.orange)
                            Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 22)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(model.rows) { row in
                                    DesktopRowView(row: row, busy: model.switching,
                                                   select: { select(row.id) }, edit: { editing = row })
                                        .contextMenu {
                                            Button("Customize…", systemImage: "pencil") { editing = row }
                                            Button("Remove Desktop…", systemImage: "trash", role: .destructive) { remove(row.id) }
                                                .disabled(!row.removable || model.switching)
                                        }
                                }
                            }
                        }
                        .frame(height: min(CGFloat(model.rows.count) * 60, 420))
                    }
                    Divider().padding(.horizontal, 4)
                    HStack(spacing: 6) {
                        if model.switching {
                            ProgressView().controlSize(.mini)
                            Text("Switching desktop…")
                        } else {
                            Image(systemName: "arrow.up.forward")
                            Text("Click a desktop to jump directly")
                        }
                        Spacer(minLength: 0)
                        Text("DeskNames").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.bottom, 2)
                }
                .padding(14)
                .transition(.opacity)
            }
        }
        .deskAnimation(value: editing?.id)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DesktopEditor: View {
    let row: DesktopPanelRow
    let save: (String, DesktopAppearance) -> Void
    let cancel: () -> Void
    let remove: () -> Void
    @State private var name: String
    @State private var appearance: DesktopAppearance
    @FocusState private var nameFocused: Bool

    init(row: DesktopPanelRow, save: @escaping (String, DesktopAppearance) -> Void, cancel: @escaping () -> Void, remove: @escaping () -> Void) {
        self.row = row; self.save = save; self.cancel = cancel; self.remove = remove
        _name = State(initialValue: row.customName)
        _appearance = State(initialValue: row.appearance)
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                DesktopBadge(appearance: appearance, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Customize Desktop").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(row.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 7) {
                label("Name")
                TextField(row.subtitle, text: $name).textFieldStyle(.roundedBorder)
                    .font(.system(size: 13)).focused($nameFocused)
                    .accessibilityLabel("Desktop name")
                    .onSubmit { save(name, appearance) }
            }
            DesktopAppearanceControls(appearance: $appearance)
            if row.removable {
                Button(role: .destructive, action: remove) {
                    Label("Remove Desktop…", systemImage: "trash").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Changes") { save(name, appearance) }
                    .buttonStyle(.borderedProminent).tint(appearance.palette.color)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        }
        .frame(height: 580)
        .onAppear { nameFocused = true }
    }
    private func label(_ value: String) -> some View {
        Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
}

struct DesktopAppearanceControls: View {
    @Binding var appearance: DesktopAppearance
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                label("Color")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                    ForEach(DesktopTint.all) { tint in
                        Button { appearance.tint = tint.id } label: {
                            Circle().fill(tint.color).frame(width: 30, height: 30)
                                .overlay {
                                    if appearance.tint == tint.id {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                                .padding(3)
                                .overlay(Circle().strokeBorder(appearance.tint == tint.id ? tint.color : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain).help(tint.name)
                        .accessibilityLabel(tint.name)
                        .accessibilityValue(appearance.tint == tint.id ? "Selected" : "")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                label("Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(DesktopAppearance.icons, id: \.symbol) { icon in
                        Button { appearance.icon = icon.symbol } label: {
                            Image(systemName: icon.symbol).font(.system(size: 16, weight: .medium))
                                .foregroundStyle(appearance.icon == icon.symbol ? appearance.palette.color : .secondary)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .background(appearance.icon == icon.symbol ? appearance.palette.color.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(appearance.icon == icon.symbol ? appearance.palette.color.opacity(0.35) : .clear))
                        }
                        .buttonStyle(.plain).help(icon.name).accessibilityLabel(icon.name)
                        .accessibilityValue(appearance.icon == icon.symbol ? "Selected" : "")
                    }
                }
            }
        }
        .deskAnimation(value: appearance)
    }
    private func label(_ value: String) -> some View {
        Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
}

// Keep interface motion brief and honor the system accessibility preference.
private struct DeskAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: value)
    }
}

extension View {
    func deskAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(DeskAnimation(value: value))
    }
}
