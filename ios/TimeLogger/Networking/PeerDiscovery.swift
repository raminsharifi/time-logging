import Foundation
import Network

/// Browses the local network for TimeLogger daemons (`_tl._tcp`) advertised by
/// the user's Macs (and other iOS devices running `tl serve`). Discovered
/// peers can be selected via `ServerSelection` so the app can sync over Wi-Fi
/// directly, without going through BLE or iCloud.
@MainActor
final class PeerDiscovery: ObservableObject {
    struct Peer: Identifiable, Hashable {
        let name: String
        let host: String
        let port: Int
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

    func start() {
        guard browser == nil else { return }
        isBrowsing = true
        lastError = nil

        let params = NWParameters()
        params.includePeerToPeer = true
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
        peers.removeAll { !currentNames.contains($0.name) }
        for result in results {
            resolve(result)
        }
    }

    private func serviceName(for result: NWBrowser.Result) -> String? {
        if case let .service(name, _, _, _) = result.endpoint { return name }
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
        let peer = Peer(name: name, host: host, port: port, lastSeen: Date())
        if let idx = peers.firstIndex(where: { $0.name == peer.name }) {
            peers[idx] = peer
        } else {
            peers.append(peer)
            peers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
