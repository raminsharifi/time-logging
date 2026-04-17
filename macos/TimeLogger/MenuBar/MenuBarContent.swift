import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var api: APIClient
    @State private var showNewTimer = false
    @Environment(\.openWindow) private var openWindow

    var runningTimer: TimerResponse? { api.timers.first { $0.isRunning } }
    var pausedTimers: [TimerResponse] { api.timers.filter { $0.isPaused } }

    var body: some View {
        VStack(alignment: .leading, spacing: TL.Space.s) {
            if let running = runningTimer {
                runningCard(running)
            } else {
                idleRow
            }

            if !pausedTimers.isEmpty {
                Divider()
                Text("PAUSED")
                    .font(TL.TypeScale.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(pausedTimers) { p in
                    pausedRow(p)
                }
            }

            Divider()

            Button {
                showNewTimer = true
            } label: {
                Label("Start New…", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first(where: { $0.title.contains("TimeLogger") || $0.contentViewController != nil }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            } label: {
                Label("Open TimeLogger", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            HStack(spacing: 6) {
                Circle()
                    .fill(api.isConnected ? TL.Palette.emerald : TL.Palette.ember)
                    .frame(width: 6, height: 6)
                Text(api.isConnected ? "Server connected" : "Server offline")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 300)
        .sheet(isPresented: $showNewTimer) {
            NewTimerSheet { await api.refreshTimers() }
        }
    }

    @ViewBuilder
    private func runningCard(_ timer: TimerResponse) -> some View {
        let tint = TL.categoryColor(timer.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PulsingDot(color: tint)
                Text("RUNNING")
                    .font(TL.TypeScale.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                CategoryChip(name: timer.category)
            }

            Text(timer.name)
                .font(TL.TypeScale.headline)
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
                    Task { _ = try? await api.pauseTimer(id: timer.id); await api.refreshTimers() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    Task { _ = try? await api.stopTimer(id: timer.id); await api.refreshTimers() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.ember)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous))
    }

    @ViewBuilder
    private var idleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(TL.Palette.mist)
            Text("No timer running")
                .font(TL.TypeScale.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func pausedRow(_ t: TimerResponse) -> some View {
        let tint = TL.categoryColor(t.category)
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.name)
                    .font(TL.TypeScale.subheadline)
                    .lineLimit(1)
                Text(TL.clockShort(t.active_secs))
                    .font(TL.TypeScale.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { _ = try? await api.resumeTimer(id: t.id); await api.refreshTimers() }
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(TL.Palette.emerald)
        }
        .padding(.vertical, 2)
    }

}
