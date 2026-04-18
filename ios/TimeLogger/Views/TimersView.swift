import SwiftUI
import SwiftData

struct TimersView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \ActiveTimerLocal.startedAt, order: .reverse)
    private var timers: [ActiveTimerLocal]
    @Query(sort: \TimeEntryLocal.startedAt, order: .reverse)
    private var allEntries: [TimeEntryLocal]

    @State private var showNewTimer = false

    var runningTimer: ActiveTimerLocal? { timers.first { $0.isRunning } }
    var pausedTimers: [ActiveTimerLocal] { timers.filter { $0.isPaused } }

    private var dayStart: Int64 {
        Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
    }

    private var todayEntries: [TimeEntryLocal] {
        allEntries.filter { $0.startedAt >= dayStart }
    }

    private var todaySecs: Int64 {
        todayEntries.reduce(Int64(0)) { $0 + $1.activeSecs }
            + (runningTimer?.activeSecs ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusStrip(
                    title: "Now",
                    caption: tlStatusCaption(),
                    right: {
                        HStack(spacing: 6) {
                            if runningTimer != nil {
                                PulsingDot(color: TL.Palette.accent, size: 5)
                                MonoLabel("LIVE", size: 10, color: TL.Palette.ink).tracking(1.4)
                            } else {
                                MonoLabel("IDLE", size: 10, color: TL.Palette.mute)
                            }
                        }
                    }
                )
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 20) {
                    horizonBlock
                    activeSession
                    quickStart
                    if !pausedTimers.isEmpty { pausedSection }
                }
                .padding(.horizontal, TL.Space.l)
                .padding(.bottom, TL.Space.l)
            }
        }
        .background(TL.Palette.bg)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showNewTimer) {
            NewTimerSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(TL.Palette.bg)
        }
    }

    // MARK: - Horizon

    private var horizonBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Today · 24h horizon")
                Spacer()
                MonoLabel("\(TL.clockShort(todaySecs)) / 8h", color: TL.Palette.ink)
            }
            HorizonBar(
                entries: todayEntries.map { e in
                    HorizonSegment(id: e.localId, startedAt: e.startedAt,
                                   endedAt: e.endedAt, category: e.category)
                },
                activeStartedAt: runningTimer?.startedAt,
                activeCategory: runningTimer?.category,
                dayStart: dayStart,
                height: 64
            )
        }
    }

    // MARK: - Active session card

    @ViewBuilder
    private var activeSession: some View {
        if let timer = runningTimer {
            let tint = TL.categoryColor(timer.category)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CategoryTag(name: timer.category)
                    Spacer()
                    HStack(spacing: 6) {
                        PulsingDot(color: tint, size: 5)
                        MonoLabel("Running", size: 10, color: tint)
                    }
                }

                Text(timer.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TL.Palette.ink)
                    .tracking(-0.3)
                    .padding(.top, 14)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MonoNum(TL.clock(timer.activeSecs), size: 56, weight: .medium, color: TL.Palette.ink)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                HStack(spacing: 16) {
                    MonoLabel("Started \(timeOfDay(timer.startedAt))")
                    MonoLabel("·", color: TL.Palette.dim)
                    MonoLabel("Breaks \(timer.breaks.count)")
                    Spacer()
                }
                .padding(.bottom, 18)

                HStack(spacing: 8) {
                    Button { pause(timer) } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.tl(.secondary, fullWidth: true))

                    Button { stop(timer) } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.tl(.ghost, fullWidth: true))
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: TL.Radius.l, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.08), TL.Palette.surface],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TL.Radius.l, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) { cornerTicks(tint) }
        } else if let paused = pausedTimers.first {
            let tint = TL.categoryColor(paused.category)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CategoryTag(name: paused.category)
                    Spacer()
                    MonoLabel("Paused", size: 10, color: TL.Palette.mute)
                }
                Text(paused.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TL.Palette.ink)
                MonoNum(TL.clock(paused.activeSecs), size: 48, weight: .medium, color: TL.Palette.mute)

                Button { resume(paused) } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.tl(.primary, fullWidth: true))
            }
            .padding(20)
            .surface(cornerRadius: TL.Radius.l, padding: 0)
            .overlay(alignment: .topLeading) { cornerTicks(tint) }
        } else {
            VStack(spacing: 10) {
                MonoLabel("Idle")
                Text("Nothing running.")
                    .font(.system(size: 20))
                    .foregroundStyle(TL.Palette.ink)
                Button {
                    showNewTimer = true
                } label: {
                    Label("Start session", systemImage: "play.fill")
                }
                .buttonStyle(.tl(.primary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .surface(padding: 0)
        }
    }

    @ViewBuilder
    private func cornerTicks(_ color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(color).frame(width: 28, height: 2)
            Rectangle().fill(color).frame(width: 2, height: 28)
        }
    }

    // MARK: - Quick start

    private var quickStart: some View {
        let cats = Array(Set(allEntries.map { $0.category })).prefix(4).sorted()
        let fallback = ["Deep Work", "Meetings", "Review", "Admin"]
        let shown = cats.isEmpty ? fallback : Array(cats)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel("Quick start")
                Spacer()
                MonoLabel("Tap", color: TL.Palette.dim)
            }
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(shown, id: \.self) { cat in
                    quickStartButton(cat)
                }
            }
        }
    }

    @ViewBuilder
    private func quickStartButton(_ category: String) -> some View {
        let tint = TL.categoryColor(category)
        let today = allEntries
            .filter { $0.category == category && $0.startedAt >= dayStart }
            .reduce(Int64(0)) { $0 + $1.activeSecs }

        Button {
            quickStart(category)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        MonoLabel(category, color: TL.Palette.ink)
                    }
                    MonoNum("\(TL.clockShort(today)) today", size: 10, color: TL.Palette.dim)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
            }
            .padding(14)
            .surface(padding: 0, background: TL.Palette.surface)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Paused list

    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Paused · \(pausedTimers.count)")
            VStack(spacing: 6) {
                ForEach(pausedTimers, id: \.localId) { t in
                    pausedRow(t)
                }
            }
        }
    }

    @ViewBuilder
    private func pausedRow(_ t: ActiveTimerLocal) -> some View {
        let tint = TL.categoryColor(t.category)
        HStack(spacing: 12) {
            Circle().fill(tint).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(.system(size: 13))
                    .foregroundStyle(TL.Palette.ink)
                MonoNum(TL.clock(t.activeSecs), size: 10, color: TL.Palette.mute)
            }
            Spacer()
            Button { resume(t) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 9))
                    Text("GO").tracking(1.2).font(TL.TypeScale.label(10))
                }
                .foregroundStyle(TL.Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay {
                    RoundedRectangle(cornerRadius: TL.Radius.m)
                        .strokeBorder(TL.Palette.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surface(padding: 0)
    }

    // MARK: - Actions

    private func pause(_ t: ActiveTimerLocal) {
        t.pause()
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func resume(_ t: ActiveTimerLocal) {
        if let running = runningTimer, running.localId != t.localId {
            running.pause()
        }
        t.resume()
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func stop(_ t: ActiveTimerLocal) {
        let now = Int64(Date().timeIntervalSince1970)
        let entry = TimeEntryLocal(
            name: t.name, category: t.category,
            startedAt: t.startedAt, endedAt: now,
            activeSecs: t.activeSecs, breaks: t.breaks, todoId: t.todoId
        )
        modelContext.insert(entry)
        if let sid = t.serverId {
            modelContext.insert(PendingDeletion(tableName: "active_timers", recordServerId: sid))
        }
        modelContext.delete(t)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func quickStart(_ category: String) {
        if let running = runningTimer { running.pause() }
        let t = ActiveTimerLocal(name: "Focus", category: category, todoId: nil)
        modelContext.insert(t)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    // MARK: - Helpers

    private func timeOfDay(_ ts: Int64) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
