import Foundation

@MainActor
final class APIClient: ObservableObject {
    @Published var isConnected = false
    @Published var timers: [TimerResponse] = []
    @Published private(set) var todos: [TodoResponse] = []
    @Published private(set) var todayEntries: [EntryResponse] = []
    @Published private(set) var baseURL: String

    private let identity: DeviceIdentity
    private let session: URLSession
    private var pollingTask: Task<Void, Never>?
    private var pokeContinuation: CheckedContinuation<Void, Never>?

    init(port: Int = 9746) {
        self.identity = .shared
        self.baseURL = "http://127.0.0.1:\(port)/api/v1"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    /// Point the client at a different server. Used when the user selects a
    /// peer Mac (or a custom host) in the Devices pane.
    func configure(endpoint: ServerSelection.Endpoint) {
        let newBase = endpoint.baseURL
        guard newBase != baseURL else { return }
        baseURL = newBase
        isConnected = false
        timers = []
        todos = []
        todayEntries = []
        Task { await pokeNow() }
    }

    /// Start a single shared polling loop. Call once from the app entry point.
    /// Refreshes timers, todos and today's entries together so every view
    /// that reads `api.*` stays in sync without having to fetch on its own.
    func startPolling(interval: TimeInterval = 1) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                // Either sleep for the interval or race a pokeNow() wake-up.
                await self.sleepUntilTickOrPoke(seconds: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        pokeContinuation?.resume()
        pokeContinuation = nil
    }

    /// Force an immediate refresh of everything the UI binds to. Use after a
    /// local mutation so the sheet you just dismissed sees the new state
    /// without waiting up to 1s for the next poll tick.
    func pokeNow() async {
        // Wake the polling loop if it's sleeping; otherwise just run a tick.
        if let cont = pokeContinuation {
            pokeContinuation = nil
            cont.resume()
        } else {
            await tick()
        }
    }

    /// Back-compat alias — some call sites pre-dated `pokeNow()`.
    func refreshTimers() async { await pokeNow() }

    private func tick() async {
        async let newTimers = (try? await getStatus()) ?? []
        async let newTodos = (try? await getTodos()) ?? []
        async let newEntries = (try? await getEntries(today: true)) ?? []
        let (t, td, e) = await (newTimers, newTodos, newEntries)
        if t != timers { timers = t }
        if td != todos { todos = td }
        if e != todayEntries { todayEntries = e }
    }

    private func sleepUntilTickOrPoke(seconds: TimeInterval) async {
        let sleeper = Task { try? await Task.sleep(for: .seconds(seconds)) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pokeContinuation = cont
            Task {
                await sleeper.value
                if let c = self.pokeContinuation {
                    self.pokeContinuation = nil
                    c.resume()
                }
            }
        }
        sleeper.cancel()
    }

    // MARK: - Health

    func ping() async -> Bool {
        guard let _: [String: Bool] = try? await get("/ping") else { return false }
        isConnected = true
        return true
    }

    /// Ping an arbitrary host:port (used when validating a peer before
    /// switching to it).
    func pingEndpoint(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/ping") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        identity.apply(to: &request)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode < 400
        } catch {
            return false
        }
    }

    // MARK: - Timers

    func getStatus() async throws -> [TimerResponse] {
        try await get("/status")
    }

    func startTimer(name: String, category: String, todoId: Int? = nil) async throws -> TimerResponse {
        try await post("/timers/start", body: StartTimerRequest(name: name, category: category, todo_id: todoId))
    }

    func stopTimer(id: Int) async throws -> EntryResponse {
        try await post("/timers/\(id)/stop")
    }

    func pauseTimer(id: Int) async throws -> TimerResponse {
        try await post("/timers/\(id)/pause")
    }

    func resumeTimer(id: Int) async throws -> TimerResponse {
        try await post("/timers/\(id)/resume")
    }

    // MARK: - Entries

    func getEntries(today: Bool = false, week: Bool = false) async throws -> [EntryResponse] {
        var path = "/entries"
        if today { path += "?today=true" }
        else if week { path += "?week=true" }
        return try await get(path)
    }

    func getEntry(id: Int) async throws -> EntryResponse {
        try await get("/entries/\(id)")
    }

    func editEntry(id: Int, request: EditEntryRequest) async throws -> EntryResponse {
        try await patch("/entries/\(id)", body: request)
    }

    func deleteEntry(id: Int) async throws {
        try await delete("/entries/\(id)")
    }

    // MARK: - Todos

    func getTodos() async throws -> [TodoResponse] {
        try await get("/todos")
    }

    func addTodo(text: String) async throws -> TodoResponse {
        try await post("/todos", body: AddTodoRequest(text: text))
    }

    func editTodo(id: Int, request: EditTodoRequest) async throws -> TodoResponse {
        try await patch("/todos/\(id)", body: request)
    }

    func deleteTodo(id: Int) async throws {
        try await delete("/todos/\(id)")
    }

    // MARK: - Suggestions

    func getSuggestions() async throws -> SuggestionsResponse {
        try await get("/suggestions")
    }

    // MARK: - Devices

    func getDevices() async throws -> DevicesResponse {
        try await get("/devices")
    }

    // MARK: - HTTP Helpers

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        identity.apply(to: &request)
        return request
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let request = makeRequest(path, method: "GET")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        let request = makeRequest(path, method: "POST")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var request = makeRequest(path, method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var request = makeRequest(path, method: "PATCH")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        let request = makeRequest(path, method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try checkResponse(response)
    }

    private func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode >= 400 {
            throw APIError.httpError(http.statusCode)
        }
        if !isConnected { isConnected = true }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from server"
        case .httpError(let code): "HTTP \(code)"
        }
    }
}
