import Foundation

/// Which TimeLogger server the iOS app prefers to sync against over Wi-Fi.
/// If no peer is selected, the app falls back to BLE + iCloud via `SyncEngine`.
@MainActor
final class ServerSelection: ObservableObject {
    enum Endpoint: Equatable {
        case none                              // Wi-Fi sync disabled (BLE / iCloud only)
        case peer(name: String, host: String, port: Int)
        case custom(host: String, port: Int)

        var host: String? {
            switch self {
            case .none: return nil
            case .peer(_, let host, _): return host
            case .custom(let host, _): return host
            }
        }

        var port: Int? {
            switch self {
            case .none: return nil
            case .peer(_, _, let port), .custom(_, let port): return port
            }
        }

        var label: String {
            switch self {
            case .none: return "Auto (BLE + iCloud)"
            case .peer(let name, _, _): return name
            case .custom(let host, _): return host
            }
        }

        var baseURL: URL? {
            guard let host, let port else { return nil }
            return URL(string: "http://\(host):\(port)/api/v1/")
        }

        var isWiFi: Bool { self != .none }
    }

    @Published private(set) var endpoint: Endpoint

    private enum Keys {
        static let kind = "tl.endpoint.kind"
        static let name = "tl.endpoint.name"
        static let host = "tl.endpoint.host"
        static let port = "tl.endpoint.port"
    }

    nonisolated static let defaultPort = 9746

    init() {
        let defaults = UserDefaults.standard
        let kind = defaults.string(forKey: Keys.kind) ?? "none"
        let host = defaults.string(forKey: Keys.host) ?? ""
        let name = defaults.string(forKey: Keys.name) ?? ""
        let port = defaults.object(forKey: Keys.port) as? Int ?? Self.defaultPort

        switch kind {
        case "peer"   where !host.isEmpty: self.endpoint = .peer(name: name, host: host, port: port)
        case "custom" where !host.isEmpty: self.endpoint = .custom(host: host, port: port)
        default: self.endpoint = .none
        }
    }

    func usePeer(_ peer: PeerDiscovery.Peer) {
        set(.peer(name: peer.name, host: peer.host, port: peer.port))
    }

    func useCustom(host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        set(.custom(host: trimmed, port: port))
    }

    func clear() {
        set(.none)
    }

    private func set(_ new: Endpoint) {
        guard new != endpoint else { return }
        endpoint = new
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        switch endpoint {
        case .none:
            defaults.set("none", forKey: Keys.kind)
            defaults.removeObject(forKey: Keys.host)
            defaults.removeObject(forKey: Keys.name)
        case .peer(let name, let host, let port):
            defaults.set("peer", forKey: Keys.kind)
            defaults.set(host, forKey: Keys.host)
            defaults.set(name, forKey: Keys.name)
            defaults.set(port, forKey: Keys.port)
        case .custom(let host, let port):
            defaults.set("custom", forKey: Keys.kind)
            defaults.set(host, forKey: Keys.host)
            defaults.set(host, forKey: Keys.name)
            defaults.set(port, forKey: Keys.port)
        }
    }
}
