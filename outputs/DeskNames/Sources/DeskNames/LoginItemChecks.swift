import Foundation
import ServiceManagement

// Verify the OS-service boundary without adding or removing any real login item.
enum LoginItemChecks {
    private final class MockService: LoginItemService {
        var status: SMAppService.Status = .notRegistered
        var registeredStatus: SMAppService.Status = .enabled
        var registrationFails = false
        var unregistrationFails = false
        var registrations = 0
        var unregistrations = 0
        var approvalRequests = 0
        func register() throws {
            registrations += 1
            if registrationFails { throw failure }
            status = registeredStatus
        }
        func unregister() throws {
            unregistrations += 1
            if unregistrationFails { throw failure }
            status = .notRegistered
        }
        func openApprovalSettings() { approvalRequests += 1 }
        private var failure: Error { NSError(domain: "DeskNames.Checks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test service denied the request."]) }
    }
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if !condition() { failures.append(name) }
        }
        let service = MockService()
        let model = LoginItemSettingsState(service: service)
        check(!model.enabled && service.registrations == 0, "Reading status does not register automatically")
        model.setEnabled(true)
        check(model.enabled && !model.needsApproval && service.registrations == 1, "Enabling registers the main app")
        model.setEnabled(true)
        check(service.registrations == 1, "Already enabled does not register twice")
        let reopened = LoginItemSettingsState(service: service)
        check(reopened.enabled, "Reopening reads the OS registration instead of a saved preference")
        service.unregistrationFails = true
        model.setEnabled(false)
        check(model.enabled && model.errorMessage != nil && !model.updating, "Unregister failure restores actual on state")
        service.unregistrationFails = false
        model.setEnabled(false)
        check(!model.enabled && model.errorMessage == nil && service.unregistrations == 2, "Disabling unregisters and clears the old error")
        service.registrationFails = true
        model.setEnabled(true)
        check(!model.enabled && model.errorMessage != nil && !model.updating, "Register failure restores actual off state")
        service.registrationFails = false
        service.registeredStatus = .requiresApproval
        model.setEnabled(true)
        check(model.enabled && model.needsApproval && model.errorMessage == nil, "Pending approval is reported distinctly")
        model.reviewApproval()
        check(service.approvalRequests == 1, "Review invokes the approval screen")
        model.setEnabled(false)
        check(!model.enabled && !model.needsApproval, "Pending registration can be cancelled")
        service.status = .enabled
        model.refresh()
        check(model.enabled && !model.needsApproval, "External approval is reflected")
        service.status = .notRegistered
        model.refresh()
        check(!model.enabled, "External removal is reflected")
        service.status = .notFound
        model.refresh()
        check(!model.enabled && !model.needsApproval, "An unavailable service is never shown as enabled")
        if failures.isEmpty {
            print("PASS: Open at Login registration, removal, failures, approval, and external status changes. No system login items changed.")
            return true
        }
        for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
        return false
    }
}
