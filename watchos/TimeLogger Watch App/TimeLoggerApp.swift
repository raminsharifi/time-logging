import SwiftUI
import SwiftData

@main
struct TimeLoggerApp: App {
    let modelContainer: ModelContainer
    let apiClient: APIClient
    let serverDiscovery: ServerDiscovery
    let bleManager: BLEManager
    let syncEngine: SyncEngine

    init() {
        let schema = Schema([
            ActiveTimerLocal.self,
            TimeEntryLocal.self,
            TodoItemLocal.self,
            PendingDeletion.self,
            SyncMetadata.self,
        ])

        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            modelContainer = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }

        apiClient = APIClient()
        serverDiscovery = ServerDiscovery()
        bleManager = BLEManager()
        syncEngine = SyncEngine(apiClient: apiClient, bleManager: bleManager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                apiClient: apiClient,
                serverDiscovery: serverDiscovery,
                bleManager: bleManager,
                syncEngine: syncEngine
            )
        }
        .modelContainer(modelContainer)
    }
}
