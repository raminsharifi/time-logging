import CoreBluetooth
import Foundation
import Combine

/// BLE request wrapper — mirrors HTTP semantics over BLE.
/// Format matches `src/ble_peripheral.m` + `ios/TimeLogger/Networking/BLEManager.swift`.
struct BLERequest: Codable {
    let method: String
    let path: String
    let body: String? // JSON string
}

struct BLEResponse: Codable {
    let status: Int
    let body: String // JSON string
}

enum BLEError: LocalizedError {
    case notConnected
    case timeout
    case disconnected
    case invalidResponse
    case bluetoothOff

    var errorDescription: String? {
        switch self {
        case .notConnected:   "Not connected to Mac"
        case .timeout:        "Request timed out"
        case .disconnected:   "Disconnected from Mac"
        case .invalidResponse:"Invalid response"
        case .bluetoothOff:   "Bluetooth is off"
        }
    }
}

/// CoreBluetooth central that talks to the Mac's `tl serve` BLE peripheral.
/// This is the watchOS equivalent of `ios/TimeLogger/Networking/BLEManager.swift`,
/// reusing the same API DTOs already defined in APIClient.swift.
@MainActor
@Observable
final class BLEManager: NSObject {
    // Observable UI state
    var isConnected = false
    var isScanning = false
    var macName: String?
    var lastError: String?

    // Core Bluetooth
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

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Connection lifecycle

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

    // MARK: - API methods (mirror HTTP endpoints used by SyncEngine)

    func ping() async -> Bool {
        (try? await sendRequest(BLERequest(method: "GET", path: "/api/v1/ping", body: nil))) != nil
    }

    func getStatus() async throws -> [APITimerResponse] {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/status", body: nil))
        return try JSONDecoder().decode([APITimerResponse].self, from: data)
    }

    func startTimer(name: String, category: String, todoId: Int? = nil) async throws -> APITimerResponse {
        struct Req: Codable { let name: String; let category: String; let todo_id: Int? }
        let body = String(data: try JSONEncoder().encode(Req(name: name, category: category, todo_id: todoId)), encoding: .utf8)
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

    func getTodos() async throws -> [APITodoResponse] {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/todos", body: nil))
        return try JSONDecoder().decode([APITodoResponse].self, from: data)
    }

    func addTodo(text: String) async throws -> APITodoResponse {
        struct Req: Codable { let text: String }
        let body = String(data: try JSONEncoder().encode(Req(text: text)), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/todos", body: body))
        return try JSONDecoder().decode(APITodoResponse.self, from: data)
    }

    func editTodo(id: Int, done: Bool) async throws -> APITodoResponse {
        struct Req: Codable { let done: Bool }
        let body = String(data: try JSONEncoder().encode(Req(done: done)), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "PATCH", path: "/api/v1/todos/\(id)", body: body))
        return try JSONDecoder().decode(APITodoResponse.self, from: data)
    }

    func getEntries(today: Bool = false, week: Bool = false) async throws -> [APIEntryResponse] {
        var path = "/api/v1/entries"
        if today { path += "?today=true" }
        else if week { path += "?week=true" }
        let data = try await sendRequest(BLERequest(method: "GET", path: path, body: nil))
        return try JSONDecoder().decode([APIEntryResponse].self, from: data)
    }

    func getSuggestions() async throws -> APISuggestionsResponse {
        let data = try await sendRequest(BLERequest(method: "GET", path: "/api/v1/suggestions", body: nil))
        return try JSONDecoder().decode(APISuggestionsResponse.self, from: data)
    }

    func sync(_ request: APISyncRequest) async throws -> APISyncResponse {
        let body = String(data: try JSONEncoder().encode(request), encoding: .utf8)
        let data = try await sendRequest(BLERequest(method: "POST", path: "/api/v1/sync", body: body))
        return try JSONDecoder().decode(APISyncResponse.self, from: data)
    }

    // MARK: - Core BLE send/receive

    private func sendRequest(_ request: BLERequest) async throws -> Data {
        guard isConnected, let reqChar = requestChar else {
            throw BLEError.notConnected
        }
        let requestData = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            pendingCompletion = { result in
                continuation.resume(with: result)
            }

            // 10s timeout
            requestTimer?.invalidate()
            requestTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.pendingCompletion?(.failure(BLEError.timeout))
                    self?.pendingCompletion = nil
                }
            }

            writeQueue = Self.chunkData(requestData)
            writeNextChunk(to: reqChar)
        }
    }

    private func writeNextChunk(to characteristic: CBCharacteristic) {
        guard !writeQueue.isEmpty, let p = peripheral else { return }
        let chunk = writeQueue.removeFirst()
        p.writeValue(chunk, for: characteristic, type: .withResponse)
    }

    static func chunkData(_ data: Data) -> [Data] {
        let maxPayload = BLEConstants.maxChunkPayload

        // 4-byte length prefix (big-endian)
        var fullData = Data()
        var length = UInt32(data.count).bigEndian
        fullData.append(Data(bytes: &length, count: 4))
        fullData.append(data)

        let totalChunks = max(1, (fullData.count + maxPayload - 1) / maxPayload)

        var chunks: [Data] = []
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

        if flags & BLEConstants.chunkFirst != 0 {
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

            // Parse BLE response wrapper — peripheral wraps HTTP body in {status, body}.
            if let bleResponse = try? JSONDecoder().decode(BLEResponse.self, from: responseData),
               let bodyData = bleResponse.body.data(using: .utf8) {
                pendingCompletion?(.success(bodyData))
            } else {
                // Raw response (some endpoints return JSON directly).
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
            switch central.state {
            case .poweredOn:
                // Auto-start scanning once Bluetooth is available.
                startScanning()
            case .poweredOff:
                lastError = "Bluetooth is off"
                isConnected = false
            case .unauthorized:
                lastError = "Bluetooth permission denied"
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            self.peripheral = peripheral
            self.macName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Mac"
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

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            lastError = error?.localizedDescription ?? "Failed to connect"
            self.peripheral = nil
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
                lastError = nil
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                pendingCompletion?(.failure(error))
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
