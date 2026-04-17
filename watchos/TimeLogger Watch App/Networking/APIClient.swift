import Foundation

struct APITimerResponse: Codable {
    let id: Int
    let name: String
    let category: String
    let started_at: Int64
    let state: String
    let breaks: [APIBreak]
    let todo_id: Int?
    let last_modified: Int64
    let active_secs: Int64
    let break_secs: Int64
}

struct APIEntryResponse: Codable {
    let id: Int
    let name: String
    let category: String
    let started_at: Int64
    let ended_at: Int64
    let active_secs: Int64
    let break_secs: Int64
    let todo_id: Int?
    let last_modified: Int64
}

struct APITodoResponse: Codable {
    let id: Int
    let text: String
    let done: Bool
    let created_at: Int64
    let last_modified: Int64
    let total_secs: Int64
}

struct APIBreak: Codable {
    let start_ts: Int64
    let end_ts: Int64
}

struct APISuggestionsResponse: Codable {
    let names: [String]
    let categories: [String]
    let recent_todos: [APITodoResponse]?
}

// MARK: - Analytics

struct APIDayBucket: Codable {
    let date: String
    let secs: Int64
}

struct APICategoryBucket: Codable {
    let name: String
    let secs: Int64
}

struct APIAnalyticsResponse: Codable {
    let range: String
    let total_secs: Int64
    let by_day: [APIDayBucket]
    let by_category: [APICategoryBucket]
    let streak_days: Int
}

struct APISyncRequest: Codable {
    let client_id: String
    let last_sync_ts: Int64
    let changes: APISyncChanges
}

struct APISyncChanges: Codable {
    var active_timers: [APISyncTimer]
    var time_entries: [APISyncEntry]
    var todos: [APISyncTodo]
    var deletions: [APISyncDeletion]
}

struct APISyncTimer: Codable {
    let server_id: Int?
    let local_id: String
    let name: String
    let category: String
    let started_at: Int64
    let state: String
    let breaks: [APIBreak]
    let todo_id: Int?
    let last_modified: Int64
}

struct APISyncEntry: Codable {
    let server_id: Int?
    let local_id: String
    let name: String
    let category: String
    let started_at: Int64
    let ended_at: Int64
    let active_secs: Int64
    let breaks: [APIBreak]
    let todo_id: Int?
    let last_modified: Int64
}

struct APISyncTodo: Codable {
    let server_id: Int?
    let local_id: String
    let text: String
    let done: Bool
    let created_at: Int64
    let last_modified: Int64
}

struct APISyncDeletion: Codable {
    let table_name: String
    let record_id: Int
    let deleted_at: Int64
}

struct APISyncResponse: Codable {
    let server_changes: APISyncChanges
    let new_sync_ts: Int64
    let id_mappings: [APIIdMapping]
}

struct APIIdMapping: Codable {
    let table_name: String
    let local_id: String
    let server_id: Int
}

@Observable
final class APIClient {
    var baseURL: URL?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    func ping() async -> Bool {
        guard let url = baseURL?.appendingPathComponent("ping") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func getStatus() async throws -> [APITimerResponse] {
        try await get("status")
    }

    func startTimer(name: String, category: String, todoId: Int? = nil) async throws -> APITimerResponse {
        var body: [String: Any] = ["name": name, "category": category]
        if let tid = todoId { body["todo_id"] = tid }
        return try await post("timers/start", body: body)
    }

    func stopTimer(id: Int) async throws -> APIEntryResponse {
        try await post("timers/\(id)/stop")
    }

    func pauseTimer(id: Int) async throws -> APITimerResponse {
        try await post("timers/\(id)/pause")
    }

    func resumeTimer(id: Int) async throws -> APITimerResponse {
        try await post("timers/\(id)/resume")
    }

    func getTodos() async throws -> [APITodoResponse] {
        try await get("todos")
    }

    func addTodo(text: String) async throws -> APITodoResponse {
        try await post("todos", body: ["text": text])
    }

    func getEntries(today: Bool = false) async throws -> [APIEntryResponse] {
        let query = today ? "?today=true" : ""
        return try await get("entries\(query)")
    }

    func getSuggestions() async throws -> APISuggestionsResponse {
        try await get("suggestions")
    }

    func getAnalytics(range: String = "week") async throws -> APIAnalyticsResponse {
        try await get("analytics?range=\(range)")
    }

    func sync(_ request: APISyncRequest) async throws -> APISyncResponse {
        try await postCodable("sync", body: request)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = baseURL?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let url = baseURL?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postCodable<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        guard let url = baseURL?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
