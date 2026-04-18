import Foundation
import WatchKit

/// Stable identity for this Apple Watch so the Mac daemon (and other peers)
/// can recognize it in the device mesh.
@MainActor
final class DeviceIdentity: ObservableObject {
    static let shared = DeviceIdentity()

    @Published private(set) var deviceId: String
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Keys.displayName) }
    }

    let platform: String = "watchOS"
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
            let new = WKInterfaceDevice.current().identifierForVendor?.uuidString ?? UUID().uuidString
            defaults.set(new, forKey: Keys.deviceId)
            self.deviceId = new
        }

        self.hostname = WKInterfaceDevice.current().name

        if let saved = defaults.string(forKey: Keys.displayName), !saved.isEmpty {
            self.displayName = saved
        } else {
            self.displayName = WKInterfaceDevice.current().name
        }
    }

    var shortId: String { String(deviceId.prefix(8)) }

    func apply(to request: inout URLRequest) {
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(displayName, forHTTPHeaderField: "X-Device-Name")
        request.setValue(platform, forHTTPHeaderField: "X-Device-Platform")
    }
}
