import AppKit
import ServiceManagement
import SwiftUI

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openApprovalSettings()
}

struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}

final class LoginItemSettingsState: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var updating = false
    @Published private(set) var errorMessage: String?
    private let service: LoginItemService

    init(service: LoginItemService = SystemLoginItemService()) {
        self.service = service
        refresh()
    }
    func refresh() {
        let status = service.status
        // Pending approval is registered, but clearly marked as not yet allowed to launch.
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
    func setEnabled(_ requested: Bool) {
        guard !updating else { return }
        refresh()
        errorMessage = nil
        guard requested != enabled else { return }
        updating = true
        defer { refresh(); updating = false }
        do {
            if requested { try service.register() }
            else { try service.unregister() }
        } catch {
            errorMessage = "Open at Login couldn’t be changed. \(error.localizedDescription)"
        }
    }
    func reviewApproval() { service.openApprovalSettings() }
}

struct LoginItemSettingView: View {
    @ObservedObject var model: LoginItemSettingsState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Open at Login").font(.system(size: 13, weight: .semibold))
                    Text("Start DeskNames automatically when you sign in.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).disabled(model.updating)
            .accessibilityHint(model.needsApproval ? "Registered, awaiting macOS approval" : "")
            if model.needsApproval {
                HStack(spacing: 8) {
                    Label("Waiting for macOS approval", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Review…", action: model.reviewApproval).controlSize(.small)
                }
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
