import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var api: APIClient
    @State private var devices: DevicesResponse?

    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.m) {
                section(title: "BLE CONNECTED", tint: TL.Palette.sky) {
                    if let ble = devices?.ble_connected, !ble.isEmpty {
                        VStack(spacing: TL.Space.s) {
                            ForEach(ble) { deviceCard($0) }
                        }
                    } else {
                        emptyInline(icon: "wave.3.right.circle.fill", text: "No BLE devices connected")
                    }
                }

                section(title: "SYNC CLIENTS", tint: TL.Palette.citrine) {
                    if let clients = devices?.sync_clients, !clients.isEmpty {
                        VStack(spacing: TL.Space.s) {
                            ForEach(clients) { clientCard($0) }
                        }
                    } else {
                        emptyInline(icon: "person.slash", text: "No sync clients registered")
                    }
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Run `tl serve --ble` to enable BLE. Sync clients appear after the first sync from Watch or iPhone.")
                        .font(TL.TypeScale.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, TL.Space.m)
            }
            .padding(TL.Space.m)
        }
        .scrollContentBackground(.hidden)
        .task { await loadDevices() }
        .onReceive(refreshTimer) { _ in Task { await loadDevices() } }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TL.Space.s) {
            Text(title)
                .font(TL.TypeScale.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: TL.Radius.l, padding: TL.Space.m, elevation: 6)
    }

    @ViewBuilder
    private func deviceCard(_ device: BLEDevice) -> some View {
        HStack(spacing: TL.Space.s) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(TL.Palette.sky)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(TL.TypeScale.headline)
                Text("ID: \(device.identifier.prefix(8))…")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    PulsingDot(color: TL.Palette.emerald)
                    Text("CONNECTED")
                        .font(TL.TypeScale.caption2.weight(.semibold))
                        .foregroundStyle(TL.Palette.emerald)
                }
                Text(formatRelative(device.connected_at))
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
    }

    @ViewBuilder
    private func clientCard(_ client: SyncClient) -> some View {
        HStack(spacing: TL.Space.s) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(TL.Palette.citrine)
            VStack(alignment: .leading, spacing: 2) {
                Text("Client \(client.client_id.prefix(8))…")
                    .font(TL.TypeScale.subheadline.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Last sync")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Text(client.last_sync > 0 ? formatRelative(client.last_sync) : "Never")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
    }

    @ViewBuilder
    private func emptyInline(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .font(TL.TypeScale.caption)
        .padding(.vertical, 6)
    }

    private func loadDevices() async {
        devices = try? await api.getDevices()
    }
}
