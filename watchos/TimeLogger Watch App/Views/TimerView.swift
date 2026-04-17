import SwiftUI
import SwiftData
import WatchKit
import WidgetKit

struct TimerView: View {
    let syncEngine: SyncEngine
    let bleManager: BLEManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.isLuminanceReduced) private var dimmed  // Always-On

    @Query(filter: #Predicate<ActiveTimerLocal> { $0.state == "running" })
    private var runningTimers: [ActiveTimerLocal]
    @Query(sort: \ActiveTimerLocal.startedAt, order: .reverse)
    private var allTimers: [ActiveTimerLocal]

    @State private var showStartSheet = false
    @State private var crownIndex: Double = 0
    @State private var selectedPausedLocalId: UUID?

    private var running: ActiveTimerLocal? { runningTimers.first }
    private var paused: [ActiveTimerLocal] { allTimers.filter { $0.state == "paused" } }

    var body: some View {
        Group {
            if let timer = running {
                runningHero(timer)
            } else {
                idleContent
            }
        }
        .sheet(isPresented: $showStartSheet) {
            TimerControlSheet(syncEngine: syncEngine)
        }
    }

    // MARK: - Running hero

    @ViewBuilder
    private func runningHero(_ timer: ActiveTimerLocal) -> some View {
        let tint = TL.categoryColor(timer.category)

        ZStack {
            RingProgress(progress: nil, tint: tint, lineWidth: 10, glow: !dimmed) {
                VStack(spacing: 2) {
                    Text(timer.name)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    TimelineView(dimmed ? .periodic(from: .now, by: 60) : .periodic(from: .now, by: 1)) { ctx in
                        Text(TL.clock(liveSeconds(timer, now: ctx.date)))
                            .font(TL.TypeScale.mono(dimmed ? 20 : 26, weight: .semibold))
                            .foregroundStyle(dimmed ? .secondary : .primary)
                            .contentTransition(.numericText())
                    }
                    CategoryChip(name: timer.category, compact: true)
                        .opacity(dimmed ? 0.5 : 1)
                }
            }
            .padding(14)
        }
        .overlay(alignment: .bottom) {
            if !dimmed {
                HStack(spacing: 10) {
                    circleButton("pause.fill", color: TL.Palette.citrine) { pauseTimer(timer) }
                    circleButton("stop.fill", color: TL.Palette.ember) { stopTimer(timer) }
                    circleButton("plus", color: TL.Palette.emerald) { showStartSheet = true }
                }
                .padding(.bottom, 2)
            }
        }
    }

    @ViewBuilder
    private func circleButton(_ systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            WKInterfaceDevice.current().play(.click)
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .background {
                    Circle().fill(color.gradient)
                }
                .foregroundStyle(.white)
                .shadow(color: color.opacity(0.5), radius: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Idle (no running timer)

    @ViewBuilder
    private var idleContent: some View {
        ScrollView {
            VStack(spacing: TL.Space.m) {
                if paused.isEmpty {
                    emptyState
                } else {
                    pausedCarousel
                }

                Button {
                    WKInterfaceDevice.current().play(.start)
                    showStartSheet = true
                } label: {
                    Label("Start Timer", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.emerald, prominent: true))
            }
            .padding(.horizontal, TL.Space.s)
            .padding(.top, TL.Space.m)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: TL.Space.s) {
            Image(systemName: "timer")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.25), radius: 4)
            Text("Ready to focus")
                .font(TL.TypeScale.headline)
            Text("Rotate the crown after starting to switch between paused timers.")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, TL.Space.xl)
    }

    @ViewBuilder
    private var pausedCarousel: some View {
        let current = paused.indices.contains(Int(crownIndex.rounded()))
            ? paused[Int(crownIndex.rounded())]
            : paused[0]
        let tint = TL.categoryColor(current.category)

        VStack(spacing: 8) {
            Text("\(Int(crownIndex.rounded()) + 1) of \(paused.count) paused")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(current.name)
                    .font(TL.TypeScale.headline)
                    .lineLimit(2)
                Text(TL.clock(Int64(current.activeSecs)))
                    .font(TL.TypeScale.mono(18))
                    .foregroundStyle(tint)
                CategoryChip(name: current.category, compact: true)
            }
            .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: TL.Space.m)

            Button {
                WKInterfaceDevice.current().play(.success)
                resumeTimer(current)
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(tint: tint, prominent: true))
        }
        .focusable()
        .digitalCrownRotation(
            $crownIndex,
            from: 0, through: Double(max(0, paused.count - 1)),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    // MARK: - Actions

    private func liveSeconds(_ timer: ActiveTimerLocal, now: Date) -> Int64 {
        // ActiveTimerLocal.activeSecs already accounts for breaks/pauses. Add the
        // time since startedAt only if running so the clock ticks smoothly.
        Int64(timer.activeSecs)
    }

    private func pauseTimer(_ timer: ActiveTimerLocal) {
        WKInterfaceDevice.current().play(.stop)
        if syncEngine.isOnline, let sid = timer.serverId {
            Task {
                switch syncEngine.transport {
                case .ble:
                    _ = try? await bleManager.pauseTimer(id: sid)
                case .wifi:
                    _ = try? await syncEngine.apiClient.pauseTimer(id: sid)
                case .offline:
                    break
                }
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        } else {
            timer.state = "paused"
            timer.breaks.append(.now())
            timer.lastModified = .now
            timer.needsSync = true
            try? modelContext.save()
            syncEngine.scheduleSyncAfterMutation()
        }
        updateWidget(running: nil)
    }

    private func resumeTimer(_ timer: ActiveTimerLocal) {
        if syncEngine.isOnline, let sid = timer.serverId {
            Task {
                switch syncEngine.transport {
                case .ble:
                    _ = try? await bleManager.resumeTimer(id: sid)
                case .wifi:
                    _ = try? await syncEngine.apiClient.resumeTimer(id: sid)
                case .offline:
                    break
                }
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        } else {
            timer.state = "running"
            if var last = timer.breaks.last, last.endTs == 0 {
                last.close()
                timer.breaks[timer.breaks.count - 1] = last
            }
            timer.lastModified = .now
            timer.needsSync = true
            try? modelContext.save()
            syncEngine.scheduleSyncAfterMutation()
        }
        updateWidget(running: timer)
    }

    private func stopTimer(_ timer: ActiveTimerLocal) {
        if syncEngine.isOnline, let sid = timer.serverId {
            Task {
                switch syncEngine.transport {
                case .ble:
                    _ = try? await bleManager.stopTimer(id: sid)
                case .wifi:
                    _ = try? await syncEngine.apiClient.stopTimer(id: sid)
                case .offline:
                    break
                }
                await syncEngine.syncIfReachable(modelContainer: modelContext.container)
            }
        } else {
            let now = Date.now
            let activeSecs = Int(timer.activeSecs)
            let entry = TimeEntryLocal(
                serverId: nil,
                name: timer.name,
                category: timer.category,
                startedAt: timer.startedAt,
                endedAt: now,
                activeSecs: activeSecs,
                breaks: timer.breaks,
                todoId: timer.todoId
            )
            modelContext.insert(entry)

            if let serverId = timer.serverId {
                modelContext.insert(PendingDeletion(tableName: "active_timers", recordServerId: serverId))
            }
            modelContext.delete(timer)
            try? modelContext.save()
            syncEngine.scheduleSyncAfterMutation()
        }
        updateWidget(running: nil)
    }
}

// MARK: - Widget bridge

func widgetTimerFileURL() -> URL {
    // Prefer the App Group shared container so the widget can read the file.
    // Fall back to the app's Documents directory for backward compat.
    if let shared = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.raminsharifi.TimeLogger"
    ) {
        return shared.appendingPathComponent("widget_timer.json")
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent("widget_timer.json")
}

func updateWidget(running timer: ActiveTimerLocal?) {
    let fileURL = widgetTimerFileURL()
    if let timer, timer.state == "running" {
        let data: [String: Any] = [
            "isRunning": true,
            "name": timer.name,
            "category": timer.category,
            "startedAt": timer.startedAt.timeIntervalSince1970,
            "activeSecs": timer.activeSecs,
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: fileURL)
        }
    } else {
        let data: [String: Any] = ["isRunning": false]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: fileURL)
        }
    }
    WidgetCenter.shared.reloadAllTimelines()
}

func formatDuration(_ secs: TimeInterval) -> String {
    TL.clock(Int64(secs))
}
