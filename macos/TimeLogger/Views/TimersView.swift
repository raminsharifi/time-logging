import SwiftUI

struct TimersView: View {
    @EnvironmentObject var api: APIClient
    @State private var showNewTimer = false

    var runningTimer: TimerResponse? { api.timers.first { $0.isRunning } }
    var pausedTimers: [TimerResponse] { api.timers.filter { $0.isPaused } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.l) {
                heroCard
                if !pausedTimers.isEmpty {
                    pausedSection
                }
            }
            .padding(TL.Space.l)
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewTimer = true } label: {
                    Label("New Timer", systemImage: "plus.circle.fill")
                }
                .tint(TL.Palette.emerald)
            }
        }
        .sheet(isPresented: $showNewTimer) {
            NewTimerSheet { await api.refreshTimers() }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroCard: some View {
        if let running = runningTimer {
            let tint = TL.categoryColor(running.category)
            HStack(alignment: .center, spacing: TL.Space.l) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = Int64(Date().timeIntervalSince1970) - running.started_at - running.break_secs
                    let bounded = max(elapsed, 0)
                    RingProgress(
                        progress: Double(bounded % 3600) / 3600.0,
                        tint: tint
                    ) {
                        VStack(spacing: 2) {
                            Text(TL.clockShort(bounded))
                                .font(TL.TypeScale.mono(30, weight: .semibold))
                                .foregroundStyle(tint)
                                .monospacedDigit()
                            Text("elapsed")
                                .font(TL.TypeScale.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 180, height: 180)
                }

                VStack(alignment: .leading, spacing: TL.Space.s) {
                    HStack(spacing: 6) {
                        PulsingDot(color: tint)
                        Text("RUNNING")
                            .font(TL.TypeScale.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(running.name)
                        .font(TL.TypeScale.mono(28, weight: .semibold))
                        .lineLimit(2)
                    CategoryChip(name: running.category)

                    HStack(spacing: TL.Space.s) {
                        Button {
                            Task { _ = try? await api.pauseTimer(id: running.id); await api.refreshTimers() }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(role: .destructive) {
                            Task { _ = try? await api.stopTimer(id: running.id); await api.refreshTimers() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TL.Palette.ember)
                        .controlSize(.large)
                    }
                    .padding(.top, TL.Space.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .glassCard(tint: tint, cornerRadius: TL.Radius.xl, padding: TL.Space.l)
        } else {
            VStack(spacing: TL.Space.m) {
                Image(systemName: "timer")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(TL.Palette.sky)
                Text("No timer running")
                    .font(TL.TypeScale.title3)
                    .foregroundStyle(.secondary)
                Button {
                    showNewTimer = true
                } label: {
                    Label("Start Timer", systemImage: "play.fill")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.emerald)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TL.Space.xl)
            .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.xl, padding: TL.Space.l)
        }
    }

    // MARK: - Paused

    @ViewBuilder
    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: TL.Space.s) {
            Text("PAUSED")
                .font(TL.TypeScale.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TL.Space.m) {
                    ForEach(pausedTimers) { t in
                        PausedTimerCard(timer: t,
                                        onResume: { Task { _ = try? await api.resumeTimer(id: t.id); await api.refreshTimers() } },
                                        onStop: { Task { _ = try? await api.stopTimer(id: t.id); await api.refreshTimers() } })
                            .frame(width: 240)
                    }
                }
            }
        }
    }

}

private struct PausedTimerCard: View {
    let timer: TimerResponse
    let onResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        let tint = TL.categoryColor(timer.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(TL.Palette.citrine).frame(width: 8, height: 8)
                Text("PAUSED")
                    .font(TL.TypeScale.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(timer.name)
                .font(TL.TypeScale.headline)
                .lineLimit(1)
            CategoryChip(name: timer.category)
            Text(TL.clockShort(timer.active_secs))
                .font(TL.TypeScale.mono(20, weight: .semibold))
                .foregroundStyle(tint)

            HStack(spacing: 6) {
                Button {
                    onResume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.emerald)
                .controlSize(.small)

                Button(role: .destructive) {
                    onStop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: TL.Radius.l, padding: TL.Space.m, elevation: 6)
    }
}
