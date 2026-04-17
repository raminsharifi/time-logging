import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var cloudKit: CloudKitManager
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(filter: #Predicate<ActiveTimerLocal> { $0.state == "running" })
    private var runningTimers: [ActiveTimerLocal]

    @State private var selected: Tab = .timers
    @State private var syncInFlight = false

    private let syncTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    enum Tab: Hashable, CaseIterable {
        case timers, log, analytics, todos, settings

        var title: String {
            switch self {
            case .timers:    "Timers"
            case .log:       "Log"
            case .analytics: "Stats"
            case .todos:     "Todos"
            case .settings:  "Settings"
            }
        }

        var icon: String {
            switch self {
            case .timers:    "timer"
            case .log:       "clock.arrow.circlepath"
            case .analytics: "chart.bar.xaxis"
            case .todos:     "checklist"
            case .settings:  "gear"
            }
        }

        var tint: Color {
            switch self {
            case .timers:    TL.Palette.emerald
            case .log:       TL.Palette.citrine
            case .analytics: TL.Palette.iris
            case .todos:     TL.Palette.sky
            case .settings:  TL.Palette.mist
            }
        }
    }

    private var heroTint: Color {
        if let name = runningTimers.first?.category { return TL.categoryColor(name) }
        return selected.tint
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Ambient mesh background responsive to active timer / selected tab.
            AnimatedMesh(tint: heroTint, animated: runningTimers.first != nil)
                .ignoresSafeArea()

            // Current tab content.
            Group {
                switch selected {
                case .timers:    TimersView()
                case .log:       EntriesView()
                case .analytics: AnalyticsView()
                case .todos:     TodosView()
                case .settings:  SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                // Push content above the floating glass tab bar.
                Color.clear.frame(height: 70)
            }

            // Floating glass tab bar.
            GlassTabBar(selected: $selected)
                .padding(.horizontal, TL.Space.m)
                .padding(.bottom, 6)
        }
        .onChange(of: bleManager.isConnected) { _, connected in
            if connected {
                Task { await syncEngine.performSync() }
            }
        }
        .onChange(of: runningTimers.first?.localId) { _, _ in
            WidgetBridge.publish(runningTimer: runningTimers.first)
        }
        .onAppear {
            WidgetBridge.publish(runningTimer: runningTimers.first)
        }
        .onReceive(syncTimer) { _ in
            guard !syncInFlight, bleManager.isConnected || cloudKit.iCloudAvailable else { return }
            syncInFlight = true
            Task {
                await syncEngine.performSync()
                await MainActor.run { syncInFlight = false }
            }
        }
    }
}

// MARK: - Glass tab bar

struct GlassTabBar: View {
    @Binding var selected: ContentView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: ContentView.Tab) -> some View {
        let isSelected = tab == selected
        Button {
            withAnimation(TL.Motion.smooth) {
                selected = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .primary.opacity(0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(tab.tint.gradient)
                        .shadow(color: tab.tint.opacity(0.45), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
