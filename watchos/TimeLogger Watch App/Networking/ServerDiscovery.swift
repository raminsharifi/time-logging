import Foundation
import Network

@Observable
final class ServerDiscovery {
    var discoveredHost: String?
    var discoveredPort: UInt16?
    var isSearching = false
    var debugLog: [String] = []

    private var browser: NWBrowser?
    private var resolveConnection: NWConnection?

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: .now, dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)"
        print("[ServerDiscovery] \(line)")
        DispatchQueue.main.async {
            self.debugLog.append(line)
            if self.debugLog.count > 50 { self.debugLog.removeFirst() }
        }
    }

    func startBrowsing() {
        stopBrowsing()
        isSearching = true
        log("Starting browse for _tl._tcp")

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_tl._tcp", domain: "local."), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log("Browser ready")
            case .failed(let error):
                self.log("Browser FAILED: \(error)")
                DispatchQueue.main.async { self.isSearching = false }
            case .cancelled:
                self.log("Browser cancelled")
                DispatchQueue.main.async { self.isSearching = false }
            case .waiting(let error):
                self.log("Browser waiting: \(error)")
            default:
                self.log("Browser state: \(state)")
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            self.log("Browse results changed: \(results.count) result(s)")
            for result in results {
                self.log("  endpoint: \(result.endpoint)")
                self.log("  interfaces: \(result.interfaces.map { $0.debugDescription })")
            }
            if let result = results.first {
                self.resolveEndpoint(result.endpoint)
            }
        }

        browser.start(queue: .global())
        self.browser = browser
        log("Browser started")
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        log("Resolving endpoint: \(endpoint)")

        resolveConnection?.cancel()

        let connection = NWConnection(to: endpoint, using: .tcp)
        resolveConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.log("Resolve connection state: \(state)")

            switch state {
            case .ready:
                if let path = connection.currentPath {
                    self.log("  path: \(path)")
                    if let remote = path.remoteEndpoint {
                        self.log("  remote endpoint: \(remote)")
                        if case let .hostPort(host: host, port: port) = remote {
                            let hostStr = "\(host)"
                            let portVal = port.rawValue
                            self.log("  resolved -> host=\(hostStr) port=\(portVal)")
                            DispatchQueue.main.async {
                                self.discoveredHost = hostStr
                                self.discoveredPort = portVal
                                self.isSearching = false
                            }
                        }
                    } else {
                        self.log("  no remote endpoint on path")
                    }
                } else {
                    self.log("  no current path")
                }
                connection.cancel()

            case .failed(let error):
                self.log("Resolve connection FAILED: \(error)")
                self.resolveConnection = nil

            case .cancelled:
                self.log("Resolve connection cancelled")
                self.resolveConnection = nil

            case .waiting(let error):
                self.log("Resolve connection waiting: \(error)")

            default:
                break
            }
        }

        connection.start(queue: .global())
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        resolveConnection?.cancel()
        resolveConnection = nil
        isSearching = false
        log("Stopped browsing")
    }

    var serverURL: URL? {
        guard let host = discoveredHost, let port = discoveredPort else { return nil }
        let cleanHost = host.replacingOccurrences(of: "%.*", with: "", options: .regularExpression)
        return URL(string: "http://\(cleanHost):\(port)/api/v1/")
    }
}
