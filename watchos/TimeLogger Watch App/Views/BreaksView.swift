import SwiftUI
import SwiftData
import WatchKit

struct BreaksView: View {
    let syncEngine: SyncEngine
    let bleManager: BLEManager

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ActiveTimerLocal> { $0.state == "running" || $0.state == "paused" },
           sort: \ActiveTimerLocal.startedAt, order: .reverse)
    private var activeTimers: [ActiveTimerLocal]

    private var current: ActiveTimerLocal? { activeTimers.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.m) {
                header
                if let timer = current {
                    liveCard(timer)
                    breaksSection(timer)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, TL.Space.s)
            .padding(.bottom, TL.Space.m)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Breaks")
                .font(TL.TypeScale.title2)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Live card

    @ViewBuilder
    private func liveCard(_ timer: ActiveTimerLocal) -> some View {
        let tint = TL.categoryColor(timer.category)
        let isOnBreak = timer.state == "paused"

        VStack(spacing: 6) {
            HStack {
                Circle()
                    .fill(isOnBreak ? TL.Palette.citrine : TL.Palette.emerald)
                    .frame(width: 8, height: 8)
                Text(isOnBreak ? "ON BREAK" : "RUNNING")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timer.name)
                    .font(TL.TypeScale.caption)
                    .lineLimit(1)
            }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(TL.clock(Int64(timer.activeSecs)))
                    .font(TL.TypeScale.mono(22, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }

            Button {
                WKInterfaceDevice.current().play(isOnBreak ? .success : .stop)
                toggleBreak(timer)
            } label: {
                Label(isOnBreak ? "Resume" : "Take Break",
                      systemImage: isOnBreak ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: isOnBreak ? TL.Palette.emerald : TL.Palette.citrine, prominent: true))
        }
        .frame(maxWidth: .infinity)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    // MARK: - Breaks list

    @ViewBuilder
    private func breaksSection(_ timer: ActiveTimerLocal) -> some View {
        if timer.breaks.isEmpty {
            Text("No breaks yet")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, TL.Space.s)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("HISTORY · \(timer.breaks.count)")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)

                ForEach(Array(timer.breaks.enumerated()), id: \.offset) { _, brk in
                    breakRow(brk)
                }
            }
        }
    }

    @ViewBuilder
    private func breakRow(_ brk: BreakPeriod) -> some View {
        let isOpen = brk.endTs == 0
        let durationSecs: Int64 = isOpen
            ? max(0, Int64(Date.now.timeIntervalSince1970) - brk.startTs)
            : brk.endTs - brk.startTs
        let start = Date(timeIntervalSince1970: Double(brk.startTs))

        HStack {
            Image(systemName: isOpen ? "pause.circle.fill" : "checkmark.circle")
                .foregroundStyle(isOpen ? TL.Palette.citrine : .secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 0) {
                Text(start.formatted(date: .omitted, time: .shortened))
                    .font(TL.TypeScale.caption)
                if isOpen {
                    Text("in progress")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(TL.Palette.citrine)
                }
            }
            Spacer()
            Text(TL.clockShort(durationSecs))
                .font(TL.TypeScale.mono(12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "pause.circle")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.55))
            Text("No active timer")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
            Text("Start a timer to track breaks.")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TL.Space.xl)
    }

    // MARK: - Actions

    private func toggleBreak(_ timer: ActiveTimerLocal) {
        let isOnBreak = timer.state == "paused"

        if syncEngine.isOnline, let sid = timer.serverId {
            Task {
                switch syncEngine.transport {
                case .ble:
                    if isOnBreak {
                        _ = try? await bleManager.resumeTimer(id: sid)
                    } else {
                        _ = try? await bleManager.pauseTimer(id: sid)
                    }
                case .wifi, .icloud:
                    if isOnBreak {
                        _ = try? await syncEngine.apiClient.resumeTimer(id: sid)
                    } else {
                        _ = try? await syncEngine.apiClient.pauseTimer(id: sid)
                    }
                case .offline:
                    break
                }
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        } else {
            if isOnBreak {
                timer.state = "running"
                if var last = timer.breaks.last, last.endTs == 0 {
                    last.close()
                    timer.breaks[timer.breaks.count - 1] = last
                }
            } else {
                timer.state = "paused"
                timer.breaks.append(.now())
            }
            timer.lastModified = .now
            timer.needsSync = true
            try? modelContext.save()
            syncEngine.scheduleSyncAfterMutation()
        }
    }
}
