import Foundation

@MainActor
final class APIClient: ObservableObject {
    @Published var isConnected = false
    @Published var timers: [TimerResponse] = []

    private let baseURL: String
    private let session: URLSession
    private var pollingTask: Task<Void, Never>?

    init(port: Int = 9746) {
        self.baseURL = "http://127.0.0.1:\(port)/api/v1"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    /// Start a single shared polling loop. Call once from the app entry point.
    func startPolling(interval: TimeInterval = 1) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let new = (try? await self.getStatus()) ?? []
                if new != self.timers { self.timers = new }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Force an immediate refresh (e.g. after start/stop/pause actions).
    func refreshTimers() async {
        let new = (try? await getStatus()) ?? []
        if new != timers { timers = new }
    }

    // MARK: - Health

    func ping() async -> Bool {
        guard let _: [String: Bool] = try? await get("/ping") else { return false }
        isConnected = true
        return true
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

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: baseURL + path)!
        let (data, response) = try await session.data(from: url)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "DELETE"
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
