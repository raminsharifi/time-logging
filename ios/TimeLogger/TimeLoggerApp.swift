import SwiftUI
import SwiftData

@main
struct TimeLoggerApp: App {
    let modelContainer: ModelContainer
    let identity: DeviceIdentity
    let bleManager: BLEManager
    let cloudKit: CloudKitManager
    let http: HTTPClient
    let peers: PeerDiscovery
    let selection: ServerSelection
    let syncEngine: SyncEngine

    init() {
        let schema = Schema([
            ActiveTimerLocal.self,
            TimeEntryLocal.self,
            TodoItemLocal.self,
            PendingDeletion.self,
            SyncMetadata.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        identity = .shared
        let ble = BLEManager()
        let ck = CloudKitManager()
        let httpClient = HTTPClient()
        bleManager = ble
        cloudKit = ck
        http = httpClient
        peers = PeerDiscovery()
        selection = ServerSelection()
        syncEngine = SyncEngine(bleManager: ble, cloudKit: ck, http: httpClient)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(identity)
                .environmentObject(bleManager)
                .environmentObject(cloudKit)
                .environmentObject(syncEngine)
                .environmentObject(http)
                .environmentObject(peers)
                .environmentObject(selection)
                .onAppear {
                    syncEngine.setModelContext(modelContainer.mainContext)
                    http.configure(selection.endpoint.baseURL)
                    peers.start()
                    Task {
                        await cloudKit.setup()
                        if http.baseURL != nil { _ = await http.ping() }
                        await syncEngine.performSync()
                    }
                    bleManager.startScanning()
                }
                .onChange(of: selection.endpoint) { _, newValue in
                    http.configure(newValue.baseURL)
                    Task {
                        if http.baseURL != nil { _ = await http.ping() }
                        await syncEngine.performSync()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
