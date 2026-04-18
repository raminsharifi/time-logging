import SwiftUI
import WatchKit

struct SettingsView: View {
    let apiClient: APIClient
    let serverDiscovery: ServerDiscovery
    let bleManager: BLEManager
    let syncEngine: SyncEngine

    @Environment(\.modelContext) private var modelContext
    @AppStorage("serverHost") private var savedHost = ""
    @AppStorage("serverPort") private var savedPort = "9746"
    @State private var manualHost = ""
    @State private var manualPort = "9746"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.m) {
                header
                transportCard
                discoveryCard
                manualCard
                syncCard
                debugCard
            }
            .padding(.horizontal, TL.Space.s)
            .padding(.bottom, TL.Space.m)
        }
        .onAppear {
            if manualHost.isEmpty { manualHost = savedHost }
            if manualPort == "9746" && !savedPort.isEmpty { manualPort = savedPort }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(TL.TypeScale.title2)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Transport

    @ViewBuilder
    private var transportCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRANSPORT")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TransportBadge(transport: syncEngine.transport)
                Spacer()
                if syncEngine.transport == .ble, let name = bleManager.macName {
                    Text(name)
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let url = apiClient.baseURL {
                    Text(url.host ?? "")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !savedHost.isEmpty {
                HStack {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(savedHost):\(savedPort)")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(
            tint: tintForTransport,
            cornerRadius: TL.Radius.m,
            padding: TL.Space.s
        )
    }

    private var tintForTransport: Color {
        switch syncEngine.transport {
        case .ble: return TL.Palette.iris
        case .wifi: return TL.Palette.sky
        case .icloud: return TL.Palette.violet
        case .offline: return TL.Palette.ember
        }
    }

    // MARK: - Discovery

    @ViewBuilder
    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUTO DISCOVERY")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            Button {
                WKInterfaceDevice.current().play(.click)
                serverDiscovery.startBrowsing()
                bleManager.startScanning()
            } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Search for Mac")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: TL.Palette.sky))

            if serverDiscovery.isSearching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Searching Wi-Fi…")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let host = serverDiscovery.discoveredHost {
                HStack {
                    Image(systemName: "wifi")
                        .font(.system(size: 10))
                        .foregroundStyle(TL.Palette.sky)
                    Text("Wi-Fi: \(host)")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if bleManager.isConnected, let name = bleManager.macName {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(TL.Palette.iris)
                    Text("BLE: \(name)")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    // MARK: - Manual

    @ViewBuilder
    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MANUAL HOST")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            TextField("IP address", text: $manualHost)
                .textContentType(.URL)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                }

            TextField("Port", text: $manualPort)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                }

            Button {
                WKInterfaceDevice.current().play(.click)
                connectManual()
            } label: {
                Label("Connect & Save", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: TL.Palette.emerald, prominent: true))
            .disabled(manualHost.isEmpty)

            if !savedHost.isEmpty {
                Button(role: .destructive) {
                    WKInterfaceDevice.current().play(.click)
                    savedHost = ""
                    savedPort = "9746"
                    apiClient.baseURL = nil
                    syncEngine.isOnline = false
                    syncEngine.transport = .offline
                } label: {
                    Label("Clear Saved", systemImage: "xmark.circle")
                        .font(TL.TypeScale.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.ember))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.emerald, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    // MARK: - Sync

    @ViewBuilder
    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SYNC")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            Button {
                WKInterfaceDevice.current().play(.click)
                Task {
                    await syncEngine.syncIfReachable(modelContainer: modelContext.container)
                }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: TL.Palette.citrine))

            if let date = syncEngine.lastSyncDate {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Last: \(date.formatted(.relative(presentation: .named)))")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Never synced")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.citrine, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    // MARK: - Debug

    @ViewBuilder
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            if serverDiscovery.debugLog.isEmpty {
                Text("No log entries")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(serverDiscovery.debugLog.suffix(6), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let err = bleManager.lastError {
                Text("BLE: \(err)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(TL.Palette.ember)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.mist, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    // MARK: - Actions

    private func connectManual() {
        guard let port = UInt16(manualPort) else { return }
        let url = URL(string: "http://\(manualHost):\(port)/api/v1/")
        apiClient.baseURL = url
        Task {
            await syncEngine.checkConnection()
            if syncEngine.isOnline {
                savedHost = manualHost
                savedPort = manualPort
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        }
    }
}
