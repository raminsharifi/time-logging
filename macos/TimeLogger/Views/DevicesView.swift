import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var identity: DeviceIdentity
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var daemon: DaemonManager
    @EnvironmentObject var peers: PeerDiscovery
    @EnvironmentObject var selection: ServerSelection

    @State private var devices: DevicesResponse?
    @State private var showCustomSheet = false

    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.m) {
                thisMacSection
                endpointSection
                daemonSection
                peersSection

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
                    Text("Each Mac runs its own daemon. Pick which one this window follows above. BLE and iCloud peers sync through the daemon on whichever Mac owns the data.")
                        .font(TL.TypeScale.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, TL.Space.m)
            }
            .padding(TL.Space.m)
        }
        .scrollContentBackground(.hidden)
        .task { await loadDevices() }
        .onReceive(refreshTimer) { _ in
            Task { await loadDevices() }
            daemon.refreshStatus()
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomHostSheet { host, port in
                selection.useCustom(host: host, port: port)
            }
        }
    }

    // MARK: - This Mac

    @ViewBuilder
    private var thisMacSection: some View {
        section(title: "THIS MAC", tint: TL.Palette.iris) {
            HStack(spacing: TL.Space.s) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(TL.Palette.iris)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Device name", text: Binding(
                        get: { identity.displayName },
                        set: { identity.displayName = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(TL.TypeScale.headline)
                    HStack(spacing: 6) {
                        Text(identity.hostname)
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("ID \(identity.shortId)")
                            .font(TL.TypeScale.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
        }
    }

    // MARK: - Active endpoint

    @ViewBuilder
    private var endpointSection: some View {
        section(title: "ACTIVE SERVER", tint: endpointTint) {
            HStack(spacing: TL.Space.s) {
                Image(systemName: endpointIcon)
                    .font(.title2)
                    .foregroundStyle(endpointTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.endpoint.label)
                        .font(TL.TypeScale.headline)
                    Text("\(selection.endpoint.host):\(selection.endpoint.port)")
                        .font(TL.TypeScale.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    PulsingDot(color: api.isConnected ? TL.Palette.emerald : TL.Palette.ember)
                    Text(api.isConnected ? "CONNECTED" : "OFFLINE")
                        .font(TL.TypeScale.caption2.weight(.semibold))
                        .foregroundStyle(api.isConnected ? TL.Palette.emerald : TL.Palette.ember)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))

            HStack(spacing: TL.Space.s) {
                Button {
                    selection.useLocal()
                } label: {
                    Label("Use This Mac", systemImage: "house.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selection.endpoint.isLocal)

                Button {
                    showCustomSheet = true
                } label: {
                    Label("Custom host…", systemImage: "network.badge.shield.half.filled")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
    }

    private var endpointIcon: String {
        switch selection.endpoint {
        case .local: "house.circle.fill"
        case .peer: "laptopcomputer.and.arrow.down"
        case .custom: "network"
        }
    }

    private var endpointTint: Color {
        selection.endpoint.isLocal ? TL.Palette.emerald : TL.Palette.sky
    }

    // MARK: - Daemon

    @ViewBuilder
    private var daemonSection: some View {
        let tint = daemonTint
        section(title: "BACKGROUND DAEMON", tint: tint) {
            HStack(spacing: TL.Space.s) {
                Image(systemName: daemonIcon)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tl serve --ble")
                        .font(TL.TypeScale.headline.monospaced())
                    Text(daemon.statusText)
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                    if let err = daemon.lastError {
                        Text(err)
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(TL.Palette.ember)
                            .lineLimit(2)
                    }
                }
                Spacer()
                daemonActionButton
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
        }
    }

    @ViewBuilder
    private var daemonActionButton: some View {
        switch daemon.status {
        case .enabled:
            Button("Disable") {
                Task { await daemon.unregister() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .requiresApproval:
            Button("Open Settings") { daemon.openLoginItems() }
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.citrine)
                .controlSize(.small)
        default:
            Button("Enable") { daemon.registerIfNeeded() }
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.emerald)
                .controlSize(.small)
        }
    }

    private var daemonTint: Color {
        switch daemon.status {
        case .enabled: TL.Palette.emerald
        case .requiresApproval: TL.Palette.citrine
        case .notFound: TL.Palette.ember
        default: TL.Palette.mist
        }
    }

    private var daemonIcon: String {
        switch daemon.status {
        case .enabled: "bolt.circle.fill"
        case .requiresApproval: "exclamationmark.triangle.fill"
        case .notFound: "xmark.octagon.fill"
        default: "power.circle"
        }
    }

    // MARK: - Peers on network

    @ViewBuilder
    private var peersSection: some View {
        section(title: "MACS ON WI-FI", tint: TL.Palette.sky) {
            if peers.peers.isEmpty {
                if peers.isBrowsing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Browsing for `_tl._tcp`…")
                            .font(TL.TypeScale.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    emptyInline(icon: "wifi.slash", text: "No peers discovered")
                }
            } else {
                VStack(spacing: TL.Space.s) {
                    ForEach(peers.peers) { peer in
                        peerCard(peer)
                    }
                }
            }

            HStack {
                Button {
                    peers.refresh()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if let err = peers.lastError {
                    Text(err)
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(TL.Palette.ember)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func peerCard(_ peer: PeerDiscovery.Peer) -> some View {
        let isActive = selection.endpoint.host == peer.host
            && selection.endpoint.port == peer.port
        HStack(spacing: TL.Space.s) {
            Image(systemName: peer.isLocal ? "laptopcomputer" : "laptopcomputer.and.arrow.down")
                .font(.title2)
                .foregroundStyle(peer.isLocal ? TL.Palette.iris : TL.Palette.sky)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(peer.name)
                        .font(TL.TypeScale.headline)
                    if peer.isLocal {
                        Text("THIS MAC")
                            .font(TL.TypeScale.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(TL.Palette.iris.opacity(0.2), in: Capsule())
                            .foregroundStyle(TL.Palette.iris)
                    }
                }
                Text("\(peer.host):\(peer.port)")
                    .font(TL.TypeScale.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                HStack(spacing: 4) {
                    PulsingDot(color: TL.Palette.emerald)
                    Text("ACTIVE")
                        .font(TL.TypeScale.caption2.weight(.semibold))
                        .foregroundStyle(TL.Palette.emerald)
                }
            } else {
                Button("Use") {
                    selection.usePeer(peer)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
    }

    // MARK: - Section chrome

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
        let isThisMac = client.client_id == identity.deviceId
        HStack(spacing: TL.Space.s) {
            Image(systemName: isThisMac ? "laptopcomputer" : "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(isThisMac ? TL.Palette.iris : TL.Palette.citrine)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isThisMac ? identity.displayName : "Client \(client.client_id.prefix(8))…")
                        .font(TL.TypeScale.subheadline.weight(.semibold))
                    if isThisMac {
                        Text("THIS MAC")
                            .font(TL.TypeScale.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(TL.Palette.iris.opacity(0.2), in: Capsule())
                            .foregroundStyle(TL.Palette.iris)
                    }
                }
                Text(client.client_id)
                    .font(TL.TypeScale.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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

// MARK: - Custom host sheet

private struct CustomHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: APIClient
    @State private var host = ""
    @State private var port = String(ServerSelection.defaultPort)
    @State private var probing = false
    @State private var probeResult: Bool?
    let onSubmit: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TL.Space.m) {
            Text("Point at another Mac")
                .font(TL.TypeScale.title3)
            Text("Enter the hostname (e.g. `minis-mbp.local`) or IP address of a Mac running `tl serve`.")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: TL.Space.s) {
                TextField("host", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            HStack {
                Button("Test") { Task { await probe() } }
                    .buttonStyle(.bordered)
                    .disabled(host.isEmpty || probing)

                if probing {
                    ProgressView().controlSize(.small)
                } else if let result = probeResult {
                    HStack(spacing: 4) {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? TL.Palette.emerald : TL.Palette.ember)
                        Text(result ? "Reachable" : "Unreachable")
                            .font(TL.TypeScale.caption)
                            .foregroundStyle(result ? TL.Palette.emerald : TL.Palette.ember)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Connect") {
                    let p = Int(port) ?? ServerSelection.defaultPort
                    onSubmit(host, p)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty)
            }
        }
        .padding(TL.Space.l)
        .frame(minWidth: 420)
    }

    private func probe() async {
        probing = true
        probeResult = nil
        let p = Int(port) ?? ServerSelection.defaultPort
        probeResult = await api.pingEndpoint(host: host, port: p)
        probing = false
    }
}
