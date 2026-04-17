import SwiftUI
import SwiftData

struct ContentView: View {
    let apiClient: APIClient
    let serverDiscovery: ServerDiscovery
    let bleManager: BLEManager
    let syncEngine: SyncEngine

    @Environment(\.modelContext) private var modelContext
    @AppStorage("serverHost") private var savedHost = ""
    @AppStorage("serverPort") private var savedPort = "9746"
    @State private var selectedTab = 0

    // For tinting the mesh background by the running timer's category.
    @Query(filter: #Predicate<ActiveTimerLocal> { $0.state == "running" })
    private var runningTimers: [ActiveTimerLocal]

    private var heroTint: Color {
        if let name = runningTimers.first?.category { return TL.categoryColor(name) }
        return TL.Palette.sky
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimerView(syncEngine: syncEngine, bleManager: bleManager)
                .tag(0)
                .containerBackground(for: .tabView) {
                    AnimatedMesh(tint: heroTint, animated: runningTimers.first != nil)
                        .ignoresSafeArea()
                }

            TodoListView(syncEngine: syncEngine)
                .tag(1)
                .containerBackground(for: .tabView) {
                    AnimatedMesh(tint: TL.Palette.emerald, animated: false)
                        .ignoresSafeArea()
                }

            BreaksView(syncEngine: syncEngine, bleManager: bleManager)
                .tag(2)
                .containerBackground(for: .tabView) {
                    AnimatedMesh(tint: TL.Palette.citrine, animated: false)
                        .ignoresSafeArea()
                }

            LogSummaryView(syncEngine: syncEngine)
                .tag(3)
                .containerBackground(for: .tabView) {
                    AnimatedMesh(tint: TL.Palette.iris, animated: false)
                        .ignoresSafeArea()
                }

            SettingsView(
                apiClient: apiClient,
                serverDiscovery: serverDiscovery,
                bleManager: bleManager,
                syncEngine: syncEngine
            )
            .tag(4)
            .containerBackground(for: .tabView) {
                AnimatedMesh(tint: TL.Palette.mist, animated: false)
                    .ignoresSafeArea()
            }
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            restoreSavedConnection()
            serverDiscovery.startBrowsing()
            bleManager.startScanning()
        }
        .onChange(of: serverDiscovery.serverURL) { _, newURL in
            guard let newURL else { return }
            apiClient.baseURL = newURL
            if let host = serverDiscovery.discoveredHost,
               let port = serverDiscovery.discoveredPort {
                savedHost = host
                savedPort = "\(port)"
            }
            Task {
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        }
        .onChange(of: bleManager.isConnected) { _, connected in
            if connected {
                Task { await syncEngine.syncIfReachable(modelContainer: modelContext.container) }
            }
        }
    }

    private func restoreSavedConnection() {
        if !savedHost.isEmpty, let port = UInt16(savedPort) {
            let cleanHost = savedHost.replacingOccurrences(of: "%.*", with: "", options: .regularExpression)
            let url = URL(string: "http://\(cleanHost):\(port)/api/v1/")
            apiClient.baseURL = url
            Task {
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        }
    }
}
