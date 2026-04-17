import SwiftUI

struct ContentView: View {
    @EnvironmentObject var api: APIClient
    @State private var selection: SidebarItem? = .timers

    var runningTimer: TimerResponse? { api.timers.first { $0.isRunning } }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    AnimatedMesh(
                        tint: runningTimer.map { TL.categoryColor($0.category) } ?? (selection ?? .timers).tint,
                        animated: runningTimer != nil
                    )
                    .ignoresSafeArea()
                }
        }
        .task { api.startPolling() }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Hero: running timer mini-card
            if let running = runningTimer {
                RunningMiniCard(timer: running) { action in
                    Task {
                        switch action {
                        case .pause: _ = try? await api.pauseTimer(id: running.id)
                        case .stop:  _ = try? await api.stopTimer(id: running.id)
                        }
                        await api.refreshTimers()
                    }
                }
                .padding(.horizontal, TL.Space.s)
                .padding(.top, TL.Space.s)
            } else {
                IdleMiniCard()
                    .padding(.horizontal, TL.Space.m)
                    .padding(.top, TL.Space.m)
            }

            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .foregroundStyle(item.tint)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            // Transport chip
            HStack(spacing: 6) {
                Circle()
                    .fill(api.isConnected ? TL.Palette.emerald : TL.Palette.ember)
                    .frame(width: 8, height: 8)
                Text(api.isConnected ? "Connected" : "Offline")
                    .font(TL.TypeScale.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(.ultraThinMaterial)
        }
        .background(.regularMaterial)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        Group {
            switch selection ?? .timers {
            case .timers:    TimersView()
            case .log:       EntriesView()
            case .todos:     TodosView()
            case .pomodoro:  PomodoroView()
            case .analytics: AnalyticsView()
            case .devices:   DevicesView()
            }
        }
        .navigationTitle((selection ?? .timers).rawValue)
    }

}

// MARK: - Sidebar running-timer card

private enum MiniCardAction { case pause, stop }

private struct RunningMiniCard: View {
    let timer: TimerResponse
    let onAction: (MiniCardAction) -> Void

    var body: some View {
        let tint = TL.categoryColor(timer.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PulsingDot(color: tint)
                Text("RUNNING")
                    .font(TL.TypeScale.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(timer.name)
                .font(TL.TypeScale.headline)
                .lineLimit(1)
            Text(timer.category)
                .font(TL.TypeScale.caption)
                .foregroundStyle(tint)
                .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = Int64(Date().timeIntervalSince1970) - timer.started_at - timer.break_secs
                Text(TL.clockShort(max(elapsed, 0)))
                    .font(TL.TypeScale.mono(22, weight: .semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Button {
                    onAction(.pause)
                } label: {
                    Image(systemName: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    onAction(.stop)
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.ember)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: TL.Space.s, elevation: 6)
    }
}

private struct IdleMiniCard: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(TL.Palette.mist)
            VStack(alignment: .leading, spacing: 1) {
                Text("Idle")
                    .font(TL.TypeScale.subheadline.weight(.semibold))
                Text("No timer running")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.mist, cornerRadius: TL.Radius.m, padding: TL.Space.s, elevation: 4)
    }
}
