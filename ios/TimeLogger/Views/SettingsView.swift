import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var identity: DeviceIdentity
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var cloudKit: CloudKitManager
    @EnvironmentObject var syncEngine: SyncEngine
    @EnvironmentObject var http: HTTPClient
    @EnvironmentObject var peers: PeerDiscovery
    @EnvironmentObject var selection: ServerSelection

    @State private var showCustomSheet = false

    private var transport: SyncTransport {
        if http.isReachable { return .wifi }
        if bleManager.isConnected { return .ble }
        if cloudKit.iCloudAvailable { return .icloud }
        return .offline
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    title: "Set",
                    caption: tlStatusCaption(),
                    right: { MonoLabel("v2.8", color: TL.Palette.ink) }
                )

                VStack(alignment: .leading, spacing: 24) {
                    transportStrip.padding(.top, 16)
                    group("Device") {
                        editableRow(label: "Device name", binding: $identity.displayName)
                        settingRow("ID",       value: identity.shortId, mono: true)
                        settingRow("Platform", value: identity.platform)
                    }
                    group("Peers on Wi-Fi") {
                        peersContent
                    }
                    group("Bluetooth") {
                        bleContent
                    }
                    group("iCloud") {
                        iCloudContent
                    }
                    group("Sync") {
                        syncContent
                    }
                    group("About") {
                        settingRow("Version", value: "1.0.0")
                        settingRow("Client",  value: "TimeLogger iOS")
                    }
                }
                .padding(.horizontal, TL.Space.l)
                .padding(.bottom, TL.Space.l)
            }
        }
        .background(TL.Palette.bg)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showCustomSheet) {
            CustomHostSheet { host, port in
                selection.useCustom(host: host, port: port)
            }
            .environmentObject(http)
        }
    }

    // MARK: - Transport strip

    private var transportStrip: some View {
        let cells: [(icon: String, label: String, active: Bool, tint: Color)] = [
            ("dot.radiowaves.left.and.right", "BLE",    bleManager.isConnected,    TL.Palette.sky),
            ("wifi",                           "Wi-Fi", http.isReachable,           TL.Palette.accent),
            ("icloud.fill",                    "iCloud",cloudKit.iCloudAvailable,   TL.Palette.violet),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                VStack(spacing: 6) {
                    Image(systemName: cell.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(cell.active ? cell.tint : TL.Palette.dim)
                    MonoLabel(cell.label, color: cell.active ? TL.Palette.ink : TL.Palette.dim)
                    Circle()
                        .fill(cell.active ? cell.tint : TL.Palette.dim.opacity(0.4))
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(alignment: .leading) {
                    if idx > 0 {
                        Rectangle().fill(TL.Palette.line).frame(width: 1)
                    }
                }
            }
        }
        .background(TL.Palette.surface)
        .overlay {
            Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
        }
    }

    // MARK: - Group scaffold

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(title)
            VStack(spacing: 0) { content() }
                .background(TL.Palette.surface)
                .overlay {
                    Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
                }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func settingRow(_ label: String,
                            value: String? = nil,
                            valueColor: Color = TL.Palette.mute,
                            mono: Bool = false,
                            hint: String? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(TL.Palette.dim)
                }
            }
            Spacer()
            if let value {
                if mono {
                    MonoNum(value, size: 12, color: valueColor)
                } else {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(valueColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private func editableRow(label: String, binding: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(TL.Palette.ink)
            Spacer()
            TextField("", text: binding)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(TL.Palette.mute)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private func toggleRow(_ label: String, hint: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(TL.Palette.dim)
                }
            }
            Spacer()
            squareToggle(isOn: isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private func squareToggle(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: TL.Radius.s)
                    .fill(isOn.wrappedValue ? TL.Palette.accent : TL.Palette.raised)
                    .frame(width: 38, height: 22)
                    .overlay {
                        RoundedRectangle(cornerRadius: TL.Radius.s)
                            .strokeBorder(isOn.wrappedValue ? TL.Palette.accent : TL.Palette.line, lineWidth: 1)
                    }
                RoundedRectangle(cornerRadius: TL.Radius.xs)
                    .fill(isOn.wrappedValue ? TL.Palette.bg : TL.Palette.mute)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Peers

    @ViewBuilder
    private var peersContent: some View {
        activeServerRow
        if peers.peers.isEmpty {
            HStack(spacing: 8) {
                if peers.isBrowsing { ProgressView().controlSize(.small) }
                Text(peers.isBrowsing ? "Browsing…" : "No peers discovered")
                    .font(.system(size: 13))
                    .foregroundStyle(TL.Palette.dim)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }
        } else {
            ForEach(peers.peers) { p in
                peerRow(p)
            }
        }
        HStack(spacing: 10) {
            Button { peers.refresh() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.tl(.secondary))
            Button { showCustomSheet = true } label: {
                Label("Custom host", systemImage: "network")
            }
            .buttonStyle(.tl(.ghost))
            if selection.endpoint.isWiFi {
                Button(role: .destructive) { selection.clear() } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(.tl(.danger))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    @ViewBuilder
    private var activeServerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: selection.endpoint.isWiFi ? "wifi" : "wifi.slash")
                .foregroundStyle(selection.endpoint.isWiFi ? TL.Palette.accent : TL.Palette.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.endpoint.label)
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                if let host = selection.endpoint.host, let port = selection.endpoint.port {
                    MonoNum("\(host):\(port)", size: 10, color: TL.Palette.dim)
                } else {
                    Text("Not using a Wi-Fi peer")
                        .font(.system(size: 11))
                        .foregroundStyle(TL.Palette.dim)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }
    }

    @ViewBuilder
    private func peerRow(_ p: PeerDiscovery.Peer) -> some View {
        let isActive = selection.endpoint.host == p.host && selection.endpoint.port == p.port
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer").foregroundStyle(TL.Palette.sky)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                MonoNum("\(p.host):\(p.port)", size: 10, color: TL.Palette.dim)
            }
            Spacer()
            if isActive {
                MonoLabel("ACTIVE", color: TL.Palette.accent)
            } else {
                Button("USE") { selection.usePeer(p) }
                    .buttonStyle(.tl(.ghost))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }
    }

    // MARK: - BLE / iCloud / Sync

    @ViewBuilder
    private var bleContent: some View {
        HStack(spacing: 10) {
            Image(systemName: bleManager.isConnected
                  ? "antenna.radiowaves.left.and.right"
                  : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(bleManager.isConnected ? TL.Palette.sky : TL.Palette.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(bleManager.isConnected ? "Connected" : "Not connected")
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                Text(bleManager.macName ?? "Fast sync when your Mac is nearby")
                    .font(.system(size: 11))
                    .foregroundStyle(TL.Palette.dim)
            }
            Spacer()
            if bleManager.isScanning { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }

        HStack(spacing: 10) {
            if bleManager.isConnected {
                Button(role: .destructive) { bleManager.disconnect() } label: {
                    Label("Disconnect", systemImage: "xmark")
                }
                .buttonStyle(.tl(.danger))
            } else {
                Button { bleManager.startScanning() } label: {
                    Label("Scan for Mac", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.tl(.secondary))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    @ViewBuilder
    private var iCloudContent: some View {
        HStack(spacing: 10) {
            Image(systemName: cloudKit.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                .foregroundStyle(cloudKit.iCloudAvailable ? TL.Palette.violet : TL.Palette.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(cloudKit.iCloudAvailable ? "iCloud Connected" : "iCloud Unavailable")
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                Text("Syncs through your Apple ID")
                    .font(.system(size: 11))
                    .foregroundStyle(TL.Palette.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    @ViewBuilder
    private var syncContent: some View {
        if let date = syncEngine.lastSyncDate {
            HStack {
                Image(systemName: "clock").foregroundStyle(TL.Palette.mute)
                Text("Last sync")
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                Spacer()
                Text(date, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(TL.Palette.mute)
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }
        }
        if let error = syncEngine.syncError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(TL.Palette.danger)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(TL.Palette.danger)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }
        }

        HStack(spacing: 10) {
            Button {
                Task { await syncEngine.performSync() }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.tl(.primary))
            .disabled(transport == .offline)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Custom host sheet

struct CustomHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var http: HTTPClient
    @State private var host = ""
    @State private var port = String(ServerSelection.defaultPort)
    @State private var probing = false
    @State private var probeResult: Bool?
    let onSubmit: (String, Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                MonoLabel("Endpoint").padding(.top, 24)

                VStack(alignment: .leading, spacing: 0) {
                    labelField("Host or IP", text: $host, autocap: false)
                    labelField("Port", text: $port, keyboard: .numberPad)
                }
                .background(TL.Palette.surface)
                .overlay {
                    Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
                }

                HStack {
                    Button("TEST") { Task { await probe() } }
                        .buttonStyle(.tl(.secondary))
                        .disabled(host.isEmpty || probing)
                    Spacer()
                    if probing {
                        ProgressView()
                    } else if let r = probeResult {
                        Label(r ? "Reachable" : "Unreachable",
                              systemImage: r ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r ? TL.Palette.accent : TL.Palette.danger)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("CANCEL") { dismiss() }
                        .buttonStyle(.tl(.ghost, fullWidth: true))
                    Button("CONNECT") {
                        let p = Int(port) ?? ServerSelection.defaultPort
                        onSubmit(host, p)
                        dismiss()
                    }
                    .buttonStyle(.tl(.primary, fullWidth: true))
                    .disabled(host.isEmpty)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .background(TL.Palette.bg)
            .navigationTitle("Custom host")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func labelField(_ label: String, text: Binding<String>,
                            autocap: Bool = true,
                            keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(TL.Palette.ink)
            Spacer()
            TextField("", text: text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(TL.Palette.mute)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled(!autocap)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(TL.Palette.line).frame(height: 1) }
    }

    private func probe() async {
        probing = true
        probeResult = nil
        let p = Int(port) ?? ServerSelection.defaultPort
        probeResult = await http.pingEndpoint(host: host, port: p)
        probing = false
    }
}
