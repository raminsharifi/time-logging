import Foundation
import Network

/// Browses the local network for other TimeLogger daemons (`_tl._tcp`) so the
/// user's other Macs (or iPhones) running `tl serve` show up automatically.
///
/// Discovered peers are resolved to host + port so the `APIClient` can target
/// any of them directly. The local machine's own daemon is filtered out.
@MainActor
final class PeerDiscovery: ObservableObject {
    struct Peer: Identifiable, Hashable {
        let name: String           // Bonjour service name (usually the hostname)
        let host: String           // IP or `.local` hostname
        let port: Int
        let isLocal: Bool          // points at this Mac's own daemon
        let lastSeen: Date

        var id: String { "\(name)@\(host):\(port)" }
        var urlString: String { "http://\(host):\(port)" }
    }

    @Published private(set) var peers: [Peer] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var lastError: String?

    private let serviceType = "_tl._tcp"
    private var browser: NWBrowser?
    private var connectionsByResult: [NWBrowser.Result: NWConnection] = [:]
    private let queue = DispatchQueue(label: "tl.peer-discovery")
    private let localHostnames: Set<String>

    init() {
        var names: Set<String> = []
        if let localized = Host.current().localizedName { names.insert(localized.lowercased()) }
        for n in Host.current().names { names.insert(n.lowercased()) }
        // Bonjour also appends `.local` — pre-compute that variant too.
        for n in Array(names) { names.insert("\(n).local") }
        self.localHostnames = names
    }

    func start() {
        guard browser == nil else { return }
        isBrowsing = true
        lastError = nil

        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .failed(let error):
                    self.lastError = error.localizedDescription
                    self.isBrowsing = false
                case .cancelled:
                    self.isBrowsing = false
                default: break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handle(results: results)
            }
        }

        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        for (_, conn) in connectionsByResult { conn.cancel() }
        connectionsByResult.removeAll()
        isBrowsing = false
    }

    func refresh() {
        stop()
        peers = []
        start()
    }

    private func handle(results: Set<NWBrowser.Result>) {
        let currentNames = Set(results.compactMap(serviceName))
        peers.removeAll { !currentNames.contains($0.name.lowercased()) }
        for result in results {
            resolve(result)
        }
    }

    private func serviceName(for result: NWBrowser.Result) -> String? {
        if case let .service(name, _, _, _) = result.endpoint {
            return name.lowercased()
        }
        return nil
    }

    private func resolve(_ result: NWBrowser.Result) {
        guard connectionsByResult[result] == nil else { return }

        let conn = NWConnection(to: result.endpoint, using: .tcp)
        connectionsByResult[result] = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let endpoint = conn.currentPath?.remoteEndpoint else {
                    conn.cancel()
                    return
                }
                let (host, port) = Self.hostPort(from: endpoint)
                let serviceName: String
                if case let .service(name, _, _, _) = result.endpoint {
                    serviceName = name
                } else {
                    serviceName = host
                }
                Task { @MainActor [weak self] in
                    self?.record(name: serviceName, host: host, port: port)
                    self?.connectionsByResult[result]?.cancel()
                    self?.connectionsByResult[result] = nil
                }
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.connectionsByResult[result] = nil
                }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    nonisolated private static func hostPort(from endpoint: NWEndpoint) -> (String, Int) {
        switch endpoint {
        case .hostPort(let host, let port):
            let hostStr: String
            switch host {
            case .name(let name, _): hostStr = name
            case .ipv4(let addr):    hostStr = "\(addr)"
            case .ipv6(let addr):    hostStr = "\(addr)"
            @unknown default:        hostStr = "\(host)"
            }
            return (hostStr, Int(port.rawValue))
        default:
            return ("\(endpoint)", 0)
        }
    }

    private func record(name: String, host: String, port: Int) {
        guard port > 0 else { return }
        let isLocal = localHostnames.contains(name.lowercased())
            || localHostnames.contains(host.lowercased())
            || host == "127.0.0.1" || host == "::1"

        let peer = Peer(name: name, host: host, port: port, isLocal: isLocal, lastSeen: Date())
        if let idx = peers.firstIndex(where: { $0.id.lowercased() == peer.id.lowercased() }) {
            peers[idx] = peer
        } else {
            peers.append(peer)
            peers.sort { lhs, rhs in
                if lhs.isLocal != rhs.isLocal { return lhs.isLocal }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
