import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var cloudKit: CloudKitManager
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(filter: #Predicate<ActiveTimerLocal> { $0.state == "running" })
    private var runningTimers: [ActiveTimerLocal]

    @State private var selected: Tab = .timers
    @State private var syncInFlight = false

    private let syncTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    enum Tab: Hashable, CaseIterable {
        case timers, log, stats, todos, settings

        var title: String {
            switch self {
            case .timers:   "Now"
            case .log:      "Log"
            case .stats:    "Stats"
            case .todos:    "Todos"
            case .settings: "Set"
            }
        }

        var icon: String {
            switch self {
            case .timers:   "timer"
            case .log:      "list.bullet"
            case .stats:    "chart.bar"
            case .todos:    "checklist"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        ZStack {
            TL.Palette.bg.ignoresSafeArea()

            if hSizeClass == .regular {
                // iPad / landscape — sidebar + detail
                HStack(spacing: 0) {
                    TLiPadSidebar(selected: $selected, running: runningTimers.first)
                        .frame(width: 260)
                        .background(Color(red: 0.039, green: 0.039, blue: 0.047))
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(TL.Palette.line).frame(width: 1)
                        }

                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // iPhone / compact — tab bar at the bottom
                VStack(spacing: 0) {
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    TLTabBar(selected: $selected)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: bleManager.isConnected) { _, connected in
            if connected { Task { await syncEngine.performSync() } }
        }
        .onChange(of: runningTimers.first?.localId) { _, _ in
            WidgetBridge.publish(runningTimer: runningTimers.first, modelContext: modelContext)
        }
        .onAppear {
            WidgetBridge.publish(runningTimer: runningTimers.first, modelContext: modelContext)
        }
        .onReceive(syncTimer) { _ in
            guard !syncInFlight, syncEngine.isOnline else { return }
            syncInFlight = true
            Task {
                await syncEngine.performSync()
                await MainActor.run { syncInFlight = false }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .timers:   TimersView()
        case .log:      EntriesView()
        case .stats:    AnalyticsView()
        case .todos:    TodosView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - iPhone tab bar

struct TLTabBar: View {
    @Binding var selected: ContentView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                button(tab)
            }
        }
        .background { Rectangle().fill(TL.Palette.bg) }
        .overlay(alignment: .top) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private func button(_ tab: ContentView.Tab) -> some View {
        let active = tab == selected
        Button { selected = tab } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .regular))
                Text(tab.title.uppercased())
                    .font(TL.TypeScale.label(9))
                    .tracking(1.2)
            }
            .foregroundStyle(active ? TL.Palette.ink : TL.Palette.dim)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .overlay(alignment: .top) {
                if active {
                    Rectangle()
                        .fill(TL.Palette.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 24)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - iPad sidebar

private struct TLiPadSidebar: View {
    @Binding var selected: ContentView.Tab
    let running: ActiveTimerLocal?

    @EnvironmentObject var identity: DeviceIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandBlock
            workspaceList
            categoriesList
            Spacer(minLength: 0)
            todayFooter
        }
        .padding(.top, 24)
    }

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Time Logger", size: 9, color: TL.Palette.dim).tracking(1.8)
            HStack(spacing: 8) {
                if let r = running {
                    PulsingDot(color: TL.categoryColor(r.category), size: 5)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MonoNum(running.map { TL.clock($0.activeSecs) } ?? "00:00:00",
                            size: 26, weight: .semibold, color: TL.Palette.ink)
                }
            }
            Text(running?.name ?? "No timer running")
                .font(.system(size: 13))
                .foregroundStyle(running != nil ? TL.Palette.ink : TL.Palette.mute)
                .lineLimit(1)
                .padding(.top, 2)

            if running != nil {
                HStack(spacing: 6) {
                    Text("PAUSE")
                        .font(TL.TypeScale.label(10))
                        .tracking(1.2)
                        .foregroundStyle(TL.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay {
                            RoundedRectangle(cornerRadius: TL.Radius.m)
                                .strokeBorder(TL.Palette.line, lineWidth: 1)
                        }
                        .background(RoundedRectangle(cornerRadius: TL.Radius.m).fill(TL.Palette.raised))
                    Text("STOP")
                        .font(TL.TypeScale.label(10))
                        .tracking(1.2)
                        .foregroundStyle(TL.Palette.mute)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay {
                            RoundedRectangle(cornerRadius: TL.Radius.m)
                                .strokeBorder(TL.Palette.line, lineWidth: 1)
                        }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private var workspaceList: some View {
        VStack(alignment: .leading, spacing: 2) {
            MonoLabel("Workspace", size: 9, color: TL.Palette.dim)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                sidebarRow(tab)
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ tab: ContentView.Tab) -> some View {
        let active = tab == selected
        Button { selected = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(active ? TL.Palette.ink : TL.Palette.mute)
                    .frame(width: 16)
                Text(tab.title == "Set" ? "Settings" : tab.title)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? TL.Palette.ink : TL.Palette.mute)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: TL.Radius.s)
                    .fill(active ? TL.Palette.raised : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private var categoriesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel("Categories · today", size: 9, color: TL.Palette.dim)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
            let cats = ["Deep Work", "Meetings", "Review", "Admin", "Learning"]
            ForEach(cats, id: \.self) { name in
                HStack(spacing: 10) {
                    Rectangle().fill(TL.categoryColor(name)).frame(width: 8, height: 8)
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(TL.Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 7)
            }
        }
    }

    private var todayFooter: some View {
        let goal: Double = 8 * 3600
        let pct = min(1.0, Double(running?.activeSecs ?? 0) / goal)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel("Today", color: TL.Palette.ink)
                Spacer()
                MonoNum(TL.clockShort(running?.activeSecs ?? 0),
                        size: 18, weight: .semibold, color: TL.Palette.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(TL.Palette.raised)
                    Rectangle().fill(TL.Palette.accent)
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 5)
            HStack {
                MonoLabel("Of 8h goal", size: 9, color: TL.Palette.dim)
                Spacer()
                MonoLabel("\(Int(pct * 100))%", size: 9, color: TL.Palette.accent)
            }
        }
        .padding(20)
        .overlay(alignment: .top) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }
}
