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
        // Disable SwiftData's auto-CloudKit sync: CloudKitManager owns the
        // iCloud.com.raminsharifi.TimeLogger container directly, and leaving
        // this on .automatic spawns redundant CoreData+CloudKit background
        // tasks against the same container (surfaces as BGTaskScheduler errors).
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
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
                    // Fold duplicates from the pre-fix era before the first
                    // sync runs, otherwise the BLE payload stays huge and
                    // every poll times out.
                    DedupeStore.run(context: modelContainer.mainContext)
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
