import Foundation

/// Which TimeLogger server the Mac app is pointed at. The default is the local
/// bundled daemon on 127.0.0.1:9746. When the user has multiple Macs, this can
/// be switched to follow a peer Mac discovered over Bonjour (or a custom host).
@MainActor
final class ServerSelection: ObservableObject {
    enum Endpoint: Equatable {
        case local(port: Int)
        case peer(name: String, host: String, port: Int)
        case custom(host: String, port: Int)

        var host: String {
            switch self {
            case .local: return "127.0.0.1"
            case .peer(_, let host, _): return host
            case .custom(let host, _): return host
            }
        }

        var port: Int {
            switch self {
            case .local(let port), .peer(_, _, let port), .custom(_, let port): return port
            }
        }

        var label: String {
            switch self {
            case .local: return "This Mac"
            case .peer(let name, _, _): return name
            case .custom(let host, _): return host
            }
        }

        var baseURL: String { "http://\(host):\(port)/api/v1" }

        var isLocal: Bool { if case .local = self { true } else { false } }
    }

    @Published private(set) var endpoint: Endpoint

    private enum Keys {
        static let kind = "tl.endpoint.kind"   // "local" | "peer" | "custom"
        static let name = "tl.endpoint.name"
        static let host = "tl.endpoint.host"
        static let port = "tl.endpoint.port"
    }

    nonisolated static let defaultPort = 9746

    init() {
        let defaults = UserDefaults.standard
        let kind = defaults.string(forKey: Keys.kind) ?? "local"
        let host = defaults.string(forKey: Keys.host) ?? "127.0.0.1"
        let name = defaults.string(forKey: Keys.name) ?? "This Mac"
        let port = defaults.object(forKey: Keys.port) as? Int ?? Self.defaultPort

        switch kind {
        case "peer":   self.endpoint = .peer(name: name, host: host, port: port)
        case "custom": self.endpoint = .custom(host: host, port: port)
        default:       self.endpoint = .local(port: port)
        }
    }

    func useLocal(port: Int = ServerSelection.defaultPort) {
        set(.local(port: port))
    }

    func usePeer(_ peer: PeerDiscovery.Peer) {
        if peer.isLocal {
            set(.local(port: peer.port))
        } else {
            set(.peer(name: peer.name, host: peer.host, port: peer.port))
        }
    }

    func useCustom(host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        set(.custom(host: trimmed, port: port))
    }

    private func set(_ new: Endpoint) {
        guard new != endpoint else { return }
        endpoint = new
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        switch endpoint {
        case .local(let port):
            defaults.set("local", forKey: Keys.kind)
            defaults.set("127.0.0.1", forKey: Keys.host)
            defaults.set("This Mac", forKey: Keys.name)
            defaults.set(port, forKey: Keys.port)
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
