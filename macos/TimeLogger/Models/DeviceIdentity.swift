import Foundation

/// Stable per-Mac identity. Generated once, persisted in UserDefaults, and
/// attached to every request so the server can distinguish each Mac when the
/// user runs the app on more than one machine.
@MainActor
final class DeviceIdentity: ObservableObject {
    static let shared = DeviceIdentity()

    @Published private(set) var deviceId: String
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Keys.displayName) }
    }

    let platform: String = "macOS"
    let hostname: String

    private enum Keys {
        static let deviceId = "tl.device.id"
        static let displayName = "tl.device.displayName"
    }

    private init() {
        let defaults = UserDefaults.standard

        if let existing = defaults.string(forKey: Keys.deviceId), !existing.isEmpty {
            self.deviceId = existing
        } else {
            let new = UUID().uuidString
            defaults.set(new, forKey: Keys.deviceId)
            self.deviceId = new
        }

        self.hostname = Host.current().localizedName ?? Host.current().name ?? "Mac"

        if let saved = defaults.string(forKey: Keys.displayName), !saved.isEmpty {
            self.displayName = saved
        } else {
            self.displayName = Host.current().localizedName ?? "Mac"
        }
    }

    /// A short identifier safe to show alongside a hostname (first 8 hex chars).
    var shortId: String { String(deviceId.prefix(8)) }

    /// Attach the standard identity headers to a request.
    func apply(to request: inout URLRequest) {
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(displayName, forHTTPHeaderField: "X-Device-Name")
        request.setValue(platform, forHTTPHeaderField: "X-Device-Platform")
    }
}
