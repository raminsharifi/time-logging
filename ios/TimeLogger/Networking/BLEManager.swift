import CoreBluetooth
import Foundation
import Combine

/// BLE request wrapper - mirrors HTTP semantics over BLE
struct BLERequest: Codable {
    let method: String
    let path: String
    let body: String? // JSON string
}

struct BLEResponse: Codable {
    let status: Int
    let body: String // JSON string
}

@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var macName: String?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var requestChar: CBCharacteristic?
    private var responseChar: CBCharacteristic?

    // Chunked receive buffer
    private var receiveBuffer = Data()
    private var expectedLength: UInt32 = 0
    private var isReceiving = false

    // Pending request completion
    private var pendingCompletion: ((Result<Data, Error>) -> Void)?
    private var requestTimer: Timer?

    // Write queue for chunked sends
    private var writeQueue: [Data] = []
    private var isWriting = false

    /// Fired when the peripheral pushes a "change" event notification. Higher
    /// layers (SyncEngine) should kick off a sync when this fires so Mac →
    /// iPhone mutations propagate without waiting for the polling interval.
    var onServerEvent: (@MainActor () -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func disconnect() {
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheral = nil
        requestChar = nil
        responseChar = nil
        isConnected = false
        macName = nil
    }

    // MARK: - API Methods (mirror HTTP endpoints)

    func ping() async -> Bool {
        guard let data = try? await sendRequest(BLERequest(method: "GET", path: "/api/v1/ping", body: nil)) else {
            return false
        }
        return data.count > 0
    }

    func getStatus() async throws -> [APITimerResponse] {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/status", body: nil))
        return try JSONDecoder().decode([APITimerResponse].self, from: data)
    }

    func startTimer(name: String, category: String, todoId: Int? = nil) async throws -> APITimerResponse {
        let req = StartTimerReq(name: name, category: category, todo_id: todoId)
        let body = String(data: try JSONEncoder().encode(req), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/timers/start", body: body))
        return try JSONDecoder().decode(APITimerResponse.self, from: data)
    }

    func stopTimer(id: Int) async throws -> APIEntryResponse {
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/timers/\(id)/stop", body: nil))
        return try JSONDecoder().decode(APIEntryResponse.self, from: data)
    }

    func pauseTimer(id: Int) async throws -> APITimerResponse {
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/timers/\(id)/pause", body: nil))
        return try JSONDecoder().decode(APITimerResponse.self, from: data)
    }

    func resumeTimer(id: Int) async throws -> APITimerResponse {
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/timers/\(id)/resume", body: nil))
        return try JSONDecoder().decode(APITimerResponse.self, from: data)
    }

    func getEntries(today: Bool = false, week: Bool = false) async throws -> [APIEntryResponse] {
        var path = "/api/v1/entries"
        if today { path += "?today=true" }
        else if week { path += "?week=true" }
        let data = try await sendRequest(BLERequest(method: "GET", path: path, body: nil))
        return try JSONDecoder().decode([APIEntryResponse].self, from: data)
    }

    func editEntry(id: Int, name: String? = nil, category: String? = nil, addMins: Int? = nil, subMins: Int? = nil) async throws -> APIEntryResponse {
        let req = EditEntryReq(name: name, category: category, add_mins: addMins, sub_mins: subMins)
        let body = String(data: try JSONEncoder().encode(req), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "PATCH", path: "/api/v1/entries/\(id)", body: body))
        return try JSONDecoder().decode(APIEntryResponse.self, from: data)
    }

    func deleteEntry(id: Int) async throws {
        _ = try await sendRequest(BLERequest(method: "DELETE", path: "/api/v1/entries/\(id)", body: nil))
    }

    func getTodos() async throws -> [APITodoResponse] {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/todos", body: nil))
        return try JSONDecoder().decode([APITodoResponse].self, from: data)
    }

    func addTodo(text: String) async throws -> APITodoResponse {
        let req = AddTodoReq(text: text)
        let body = String(data: try JSONEncoder().encode(req), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/todos", body: body))
        return try JSONDecoder().decode(APITodoResponse.self, from: data)
    }

    func editTodo(id: Int, text: String? = nil, done: Bool? = nil) async throws -> APITodoResponse {
        let req = EditTodoReq(text: text, done: done)
        let body = String(data: try JSONEncoder().encode(req), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "PATCH", path: "/api/v1/todos/\(id)", body: body))
        return try JSONDecoder().decode(APITodoResponse.self, from: data)
    }

    func deleteTodo(id: Int) async throws {
        _ = try await sendRequest(BLERequest(method: "DELETE", path: "/api/v1/todos/\(id)", body: nil))
    }

    func getSuggestions() async throws -> APISuggestionsResponse {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/suggestions", body: nil))
        return try JSONDecoder().decode(APISuggestionsResponse.self, from: data)
    }

    func getAnalytics(range: String) async throws -> APIAnalyticsResponse {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/analytics?range=\(range)", body: nil))
        return try JSONDecoder().decode(APIAnalyticsResponse.self, from: data)
    }

    func sync(request: APISyncRequest) async throws -> APISyncResponse {
        let body = String(data: try JSONEncoder().encode(request), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/sync", body: body))
        return try JSONDecoder().decode(APISyncResponse.self, from: data)
    }

    // MARK: - Core BLE Send/Receive

    private func sendRequest(_ request: BLERequest) async throws -> Data {
        guard isConnected, let reqChar = requestChar, let p = peripheral else {
            throw BLEError.notConnected
        }
        // A previous request is still awaiting its response. Overwriting
        // pendingCompletion here would orphan its continuation (Swift prints
        // "CONTINUATION MISUSE: sendRequest leaked its continuation"). Bail
        // fast — the caller (SyncEngine polling loop) will retry on the next
        // tick once the in-flight request resolves or times out.
        guard pendingCompletion == nil else {
            throw BLEError.busy
        }

        let requestData = try JSONEncoder().encode(request)

        // Query negotiated MTU at send time; subtract 1 for the flag byte.
        // Fallback to legacy BLE 4.0 minimum if no MTU is available yet.
        let maxWrite = p.maximumWriteValueLength(for: .withResponse)
        let maxPayload = max(19, maxWrite - 1)

        return try await withCheckedThrowingContinuation { continuation in
            pendingCompletion = { result in
                continuation.resume(with: result)
            }

            // 10 second timeout
            requestTimer?.invalidate()
            requestTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                self?.pendingCompletion?(.failure(BLEError.timeout))
                self?.pendingCompletion = nil
            }

            // Chunk and send
            let chunks = Self.chunkData(requestData, maxPayload: maxPayload)
            writeQueue = chunks
            isWriting = false
            writeNextChunk(to: reqChar)
        }
    }

    private func writeNextChunk(to characteristic: CBCharacteristic) {
        guard !writeQueue.isEmpty, let p = peripheral else { return }
        isWriting = true
        let chunk = writeQueue.removeFirst()
        p.writeValue(chunk, for: characteristic, type: .withResponse)
    }

    static func chunkData(_ data: Data, maxPayload: Int = BLEConstants.maxChunkPayload) -> [Data] {
        var chunks: [Data] = []

        // Prepend 4-byte length
        var fullData = Data()
        var length = UInt32(data.count).bigEndian
        fullData.append(Data(bytes: &length, count: 4))
        fullData.append(data)

        let totalChunks = (fullData.count + maxPayload - 1) / maxPayload

        for i in 0..<totalChunks {
            let start = i * maxPayload
            let end = min(start + maxPayload, fullData.count)
            let payload = fullData[start..<end]

            var chunk = Data()
            var flags: UInt8 = 0
            if i == 0 { flags |= BLEConstants.chunkFirst }
            if i == totalChunks - 1 { flags |= BLEConstants.chunkLast }
            chunk.append(flags)
            chunk.append(payload)
            chunks.append(chunk)
        }

        return chunks
    }

    private func handleReceivedChunk(_ data: Data) {
        guard data.count >= 1 else { return }
        let flags = data[0]
        let payload = data.subdata(in: 1..<data.count)

        // Server push: peripheral telling us "something changed". There's no
        // pending request to match this to — just fan out to the sync layer.
        if flags & BLEConstants.chunkEvent != 0 && payload.isEmpty {
            let handler = onServerEvent
            Task { @MainActor in handler?() }
            return
        }

        if flags & BLEConstants.chunkFirst != 0 {
            // First chunk: read 4-byte length header
            guard payload.count >= 4 else { return }
            expectedLength = payload.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            receiveBuffer = Data()
            receiveBuffer.append(payload.subdata(in: 4..<payload.count))
            isReceiving = true
        } else if isReceiving {
            receiveBuffer.append(payload)
        }

        if flags & BLEConstants.chunkLast != 0, isReceiving {
            isReceiving = false
            let responseData = receiveBuffer
            receiveBuffer = Data()

            requestTimer?.invalidate()
            requestTimer = nil

            // Parse BLE response wrapper
            if let bleResponse = try? JSONDecoder().decode(BLEResponse.self, from: responseData),
               let bodyData = bleResponse.body.data(using: .utf8) {
                pendingCompletion?(.success(bodyData))
            } else {
                // Raw response (from sync endpoint etc.)
                pendingCompletion?(.success(responseData))
            }
            pendingCompletion = nil
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn && isScanning {
                startScanning()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            self.peripheral = peripheral
            self.macName = peripheral.name ?? "Mac"
            central.stopScan()
            isScanning = false
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices([BLEConstants.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnected = false
            macName = nil
            self.peripheral = nil
            requestChar = nil
            responseChar = nil
            pendingCompletion?(.failure(BLEError.disconnected))
            pendingCompletion = nil
            // Auto-reconnect
            startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else { return }
            peripheral.discoverCharacteristics(
                [BLEConstants.requestCharUUID, BLEConstants.responseCharUUID],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let chars = service.characteristics else { return }
            for char in chars {
                if char.uuid == BLEConstants.requestCharUUID {
                    requestChar = char
                }
                if char.uuid == BLEConstants.responseCharUUID {
                    responseChar = char
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            if requestChar != nil && responseChar != nil {
                isConnected = true
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if error != nil {
                pendingCompletion?(.failure(error!))
                pendingCompletion = nil
                writeQueue.removeAll()
                return
            }
            if !writeQueue.isEmpty {
                writeNextChunk(to: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == BLEConstants.responseCharUUID,
                  let data = characteristic.value else { return }
            handleReceivedChunk(data)
        }
    }
}

// MARK: - API DTOs

struct APITimerResponse: Codable {
    let id: Int
    let name: String
    let category: String
    let started_at: Int64
    let state: String
    let breaks: [APIBreakPeriod]
    let todo_id: Int?
    let last_modified: Int64
    let active_secs: Int64
    let break_secs: Int64
}

struct APIBreakPeriod: Codable {
    let start_ts: Int64
    let end_ts: Int64
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
    let color: String
}

struct APIAnalyticsResponse: Codable {
    let range: String
    let total_secs: Int64
    let by_day: [APIDayBucket]
    let by_category: [APICategoryBucket]
    let streak_days: UInt32
}

struct StartTimerReq: Codable {
    let name: String
    let category: String
    let todo_id: Int?
}

struct EditEntryReq: Codable {
    let name: String?
    let category: String?
    let add_mins: Int?
    let sub_mins: Int?
}

struct AddTodoReq: Codable {
    let text: String
}

struct EditTodoReq: Codable {
    let text: String?
    let done: Bool?
}

// MARK: - Sync DTOs

struct APISyncRequest: Codable {
    let client_id: String
    let last_sync_ts: Int64
    let changes: APISyncChanges
}

struct APISyncChanges: Codable {
    var active_timers: [APISyncTimerData]
    var time_entries: [APISyncEntryData]
    var todos: [APISyncTodoData]
    var deletions: [APISyncDeletion]
}

struct APISyncTimerData: Codable {
    let server_id: Int?
    let local_id: String
    let name: String
    let category: String
    let started_at: Int64
    let state: String
    let breaks: [APIBreakPeriod]
    let todo_id: Int?
    let last_modified: Int64
}

struct APISyncEntryData: Codable {
    let server_id: Int?
    let local_id: String
    let name: String
    let category: String
    let started_at: Int64
    let ended_at: Int64
    let active_secs: Int64
    let breaks: [APIBreakPeriod]
    let todo_id: Int?
    let last_modified: Int64
}

struct APISyncTodoData: Codable {
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

struct APISyncIdMapping: Codable {
    let table_name: String
    let local_id: String
    let server_id: Int
}

struct APISyncResponse: Codable {
    let server_changes: APISyncChanges
    let new_sync_ts: Int64
    let id_mappings: [APISyncIdMapping]
}

// MARK: - Errors

enum BLEError: LocalizedError {
    case notConnected
    case timeout
    case disconnected
    case invalidResponse
    case busy

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to Mac"
        case .timeout: "Request timed out"
        case .disconnected: "Disconnected from Mac"
        case .invalidResponse: "Invalid response"
        case .busy: "BLE request already in flight"
        }
    }
}
