import SwiftUI
import SwiftData

@main
struct TimeLoggerApp: App {
    let modelContainer: ModelContainer
    let bleManager: BLEManager
    let cloudKit: CloudKitManager
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

        let ble = BLEManager()
        let ck = CloudKitManager()
        bleManager = ble
        cloudKit = ck
        syncEngine = SyncEngine(bleManager: ble, cloudKit: ck)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(cloudKit)
                .environmentObject(syncEngine)
                .onAppear {
                    syncEngine.setModelContext(modelContainer.mainContext)
                    // Setup iCloud first, then start BLE scanning as fallback
                    Task {
                        await cloudKit.setup()
                        await syncEngine.performSync()
                    }
                    bleManager.startScanning()
                }
        }
        .modelContainer(modelContainer)
    }
}
