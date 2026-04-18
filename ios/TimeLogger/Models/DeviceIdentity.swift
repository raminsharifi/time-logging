import Foundation
import UIKit

/// Stable per-device identity. Generated once, persisted in UserDefaults, and
/// attached to every HTTP request so the server and peers can distinguish
/// each iPhone / iPad when the user runs the app on more than one device.
@MainActor
final class DeviceIdentity: ObservableObject {
    static let shared = DeviceIdentity()

    @Published private(set) var deviceId: String
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Keys.displayName) }
    }

    let platform: String
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
            // Prefer identifierForVendor so a fresh install keeps the same id
            // for the lifetime of the vendor install; fall back to a UUID.
            let new = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            defaults.set(new, forKey: Keys.deviceId)
            self.deviceId = new
        }

        let device = UIDevice.current
        self.hostname = device.name
        self.platform = device.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"

        if let saved = defaults.string(forKey: Keys.displayName), !saved.isEmpty {
            self.displayName = saved
        } else {
            self.displayName = device.name
        }
    }

    var shortId: String { String(deviceId.prefix(8)) }

    func apply(to request: inout URLRequest) {
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(displayName, forHTTPHeaderField: "X-Device-Name")
        request.setValue(platform, forHTTPHeaderField: "X-Device-Platform")
    }
}
