import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var cloudKit: CloudKitManager
    @EnvironmentObject var syncEngine: SyncEngine

    private var transport: SyncTransport {
        if bleManager.isConnected { return .ble }
        if syncEngine.isOnline { return .wifi }
        return .offline
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TL.Space.m) {
                    transportCard
                    bluetoothCard
                    cloudCard
                    syncCard
                    aboutCard
                }
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.s)
                .padding(.bottom, TL.Space.xl)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(TL.TypeScale.headline)
                }
            }
        }
    }

    // MARK: - Transport hero

    @ViewBuilder
    private var transportCard: some View {
        VStack(alignment: .leading, spacing: TL.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRANSPORT")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                TransportBadge(transport: transport)
            }
            HStack(spacing: TL.Space.s) {
                transportDot(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "BLE",
                    active: bleManager.isConnected,
                    tint: TL.Palette.iris
                )
                transportDot(
                    icon: "wifi",
                    label: "Wi-Fi",
                    active: syncEngine.isOnline,
                    tint: TL.Palette.sky
                )
                transportDot(
                    icon: "icloud.fill",
                    label: "iCloud",
                    active: cloudKit.iCloudAvailable,
                    tint: TL.Palette.emerald
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tintForTransport, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    private var tintForTransport: Color {
        switch transport {
        case .ble: return TL.Palette.iris
        case .wifi: return TL.Palette.sky
        case .offline: return TL.Palette.ember
        }
    }

    private func transportDot(icon: String, label: String, active: Bool, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(active ? tint : .secondary)
            Text(label)
                .font(TL.TypeScale.caption2)
                .foregroundStyle(active ? .primary : .secondary)
            Circle()
                .fill(active ? tint : .secondary.opacity(0.3))
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
        }
    }

    // MARK: - Bluetooth

    @ViewBuilder
    private var bluetoothCard: some View {
        VStack(alignment: .leading, spacing: TL.Space.xs) {
            Text("BLUETOOTH")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: bleManager.isConnected
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(bleManager.isConnected ? TL.Palette.iris : .secondary)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bleManager.isConnected ? "Connected" : "Not connected")
                        .font(TL.TypeScale.callout)
                    if let name = bleManager.macName {
                        Text(name)
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Fast sync when Mac is nearby")
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if bleManager.isScanning {
                    ProgressView().controlSize(.small)
                }
            }

            if bleManager.isConnected {
                Button(role: .destructive) {
                    bleManager.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.ember))
            } else if !bleManager.isScanning {
                Button {
                    bleManager.startScanning()
                } label: {
                    Label("Scan for Mac", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.iris, prominent: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    // MARK: - iCloud

    @ViewBuilder
    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("iCLOUD")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: cloudKit.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                    .foregroundStyle(cloudKit.iCloudAvailable ? TL.Palette.emerald : .secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cloudKit.iCloudAvailable ? "iCloud Connected" : "iCloud Unavailable")
                        .font(TL.TypeScale.callout)
                    Text("Syncs automatically via your Apple ID")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.emerald, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    // MARK: - Sync

    @ViewBuilder
    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SYNC STATUS")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            if let date = syncEngine.lastSyncDate {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Last sync")
                    Spacer()
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .font(TL.TypeScale.callout)
            }

            if let error = syncEngine.syncError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TL.Palette.citrine)
                    Text(error)
                        .font(TL.TypeScale.caption)
                        .foregroundStyle(TL.Palette.ember)
                }
            }

            Button {
                Task { await syncEngine.performSync() }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: TL.Palette.citrine, prominent: true))
            .disabled(transport == .offline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.citrine, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    // MARK: - About

    @ViewBuilder
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ABOUT")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0").foregroundStyle(.secondary)
            }
            .font(TL.TypeScale.callout)
            Text("Run `tl serve --ble` on your Mac for instant sync.")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.mist, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }
}
