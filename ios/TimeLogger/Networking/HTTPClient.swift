import Foundation

/// Lightweight HTTP client used when the iOS app is pointed at a specific
/// Mac daemon on the LAN. BLE remains the default when nearby; this exists so
/// the phone can stay in sync with the chosen Mac over Wi-Fi when BLE can't
/// connect (e.g. phone on a desk, Mac in another room but on the same Wi-Fi).
@MainActor
final class HTTPClient: ObservableObject {
    @Published private(set) var baseURL: URL?
    @Published private(set) var isReachable = false

    private let identity: DeviceIdentity
    private let session: URLSession

    init() {
        self.identity = .shared
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    func configure(_ url: URL?) {
        guard baseURL != url else { return }
        baseURL = url
        isReachable = false
    }

    func ping() async -> Bool {
        guard let url = baseURL?.appendingPathComponent("ping") else {
            isReachable = false
            return false
        }
        var request = URLRequest(url: url)
        identity.apply(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            isReachable = ok
            return ok
        } catch {
            isReachable = false
            return false
        }
    }

    func pingEndpoint(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/ping") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        identity.apply(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func sync(_ payload: APISyncRequest) async throws -> APISyncResponse {
        guard let url = baseURL?.appendingPathComponent("sync") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        identity.apply(to: &request)
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw URLError(.badServerResponse)
        }
        isReachable = true
        return try JSONDecoder().decode(APISyncResponse.self, from: data)
    }
}
