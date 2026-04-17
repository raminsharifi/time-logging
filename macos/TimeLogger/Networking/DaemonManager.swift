import Foundation
import ServiceManagement
import os

/// Manages the bundled `tl serve --ble` LaunchAgent.
///
/// The plist lives at `Contents/Library/LaunchAgents/com.raminsharifi.timelogger.daemon.plist`
/// inside the app bundle. `SMAppService.agent(plistName:)` registers it with
/// launchd as a per-user agent so it runs at login, restarts on crash, and
/// keeps running when the app is closed.
@MainActor
final class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    static let plistName = "com.raminsharifi.timelogger.daemon.plist"

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?

    private let service: SMAppService
    private let log = Logger(subsystem: "com.raminsharifi.TimeLogger.mac", category: "DaemonManager")

    private init() {
        self.service = SMAppService.agent(plistName: Self.plistName)
        self.status = self.service.status
    }

    /// Idempotent: registers the agent if not already enabled.
    func registerIfNeeded() {
        refreshStatus()
        guard status != .enabled else { return }
        do {
            try service.register()
            lastError = nil
            log.info("Registered daemon LaunchAgent")
        } catch {
            lastError = error.localizedDescription
            log.error("Daemon register failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
    }

    func unregister() async {
        do {
            try await service.unregister()
            lastError = nil
            log.info("Unregistered daemon LaunchAgent")
        } catch {
            lastError = error.localizedDescription
            log.error("Daemon unregister failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
    }

    func refreshStatus() {
        status = service.status
    }

    /// Opens the Login Items pane so the user can flip it back on if they disabled it.
    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var statusText: String {
        switch status {
        case .notRegistered: return "Not registered"
        case .enabled:       return "Enabled"
        case .requiresApproval: return "Requires approval in System Settings"
        case .notFound:      return "Not found in bundle"
        @unknown default:    return "Unknown"
        }
    }
}
