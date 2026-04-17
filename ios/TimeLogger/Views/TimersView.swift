import SwiftUI
import SwiftData

struct TimersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \ActiveTimerLocal.startedAt, order: .reverse) private var timers: [ActiveTimerLocal]

    @State private var showNewTimer = false
    @State private var heroIndex = 0

    private var heroHeight: CGFloat {
        if verticalSizeClass == .compact { return 240 }
        if dynamicTypeSize >= .accessibility1 { return 400 }
        return UIScreen.main.bounds.height < 700 ? 300 : 360
    }

    private var ringHeight: CGFloat {
        heroHeight - 140
    }

    var runningTimer: ActiveTimerLocal? { timers.first { $0.isRunning } }
    var pausedTimers: [ActiveTimerLocal] { timers.filter { $0.isPaused } }

    /// The "Now Playing" carousel stack: running first, then paused.
    var heroStack: [ActiveTimerLocal] {
        var arr: [ActiveTimerLocal] = []
        if let r = runningTimer { arr.append(r) }
        arr.append(contentsOf: pausedTimers)
        return arr
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TL.Space.l) {
                    headerRow

                    if heroStack.isEmpty {
                        emptyHero
                    } else {
                        heroCarousel
                    }

                    if !pausedTimers.isEmpty {
                        pausedListSection
                    }
                }
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.s)
                .padding(.bottom, TL.Space.l)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Timers")
                        .font(TL.TypeScale.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewTimer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(TL.Palette.emerald.gradient)
                    }
                }
            }
            .sheet(isPresented: $showNewTimer) {
                NewTimerSheet()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            TransportBadge(transport: transportForUI)
            Spacer()
            if let running = runningTimer {
                PulsingDot(color: TL.categoryColor(running.category))
                Text("Active")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transportForUI: SyncTransport {
        if bleManager.isConnected { return .ble }
        if syncEngine.isOnline { return .wifi }
        return .offline
    }

    // MARK: - Hero

    @ViewBuilder
    private var emptyHero: some View {
        VStack(spacing: TL.Space.m) {
            Image(systemName: "timer")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, TL.Space.xl)

            Text("Ready to focus")
                .font(TL.TypeScale.title2)

            Text("Tap the + button or swipe up to start a new timer.")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TL.Space.l)

            Button {
                showNewTimer = true
            } label: {
                Label("Start Timer", systemImage: "play.fill")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.glass(tint: TL.Palette.emerald, prominent: true))
            .padding(.top, TL.Space.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TL.Space.xl)
        .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.xl, padding: TL.Space.m)
    }

    @ViewBuilder
    private var heroCarousel: some View {
        TabView(selection: $heroIndex) {
            ForEach(Array(heroStack.enumerated()), id: \.element.localId) { idx, timer in
                heroCard(timer)
                    .padding(.horizontal, 2)
                    .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: heroStack.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private func heroCard(_ timer: ActiveTimerLocal) -> some View {
        let tint = TL.categoryColor(timer.category)
        let isRunning = timer.isRunning

        VStack(spacing: TL.Space.m) {
            HStack {
                CategoryChip(name: timer.category)
                Spacer()
                if isRunning {
                    HStack(spacing: 4) {
                        PulsingDot(color: tint)
                        Text("RUNNING")
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(tint)
                    }
                } else {
                    Text("PAUSED")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            RingProgress(progress: nil, tint: tint, lineWidth: 12, glow: isRunning) {
                VStack(spacing: 4) {
                    Text(timer.name)
                        .font(TL.TypeScale.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(TL.clock(timer.activeSecs))
                            .font(TL.TypeScale.mono(40, weight: .semibold))
                            .foregroundStyle(isRunning ? .primary : .secondary)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                    }
                }
            }
            .frame(height: ringHeight)

            HStack(spacing: TL.Space.s) {
                if isRunning {
                    Button {
                        pauseTimer(timer)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass(tint: TL.Palette.citrine, prominent: true))
                } else {
                    Button {
                        resumeTimer(timer)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass(tint: TL.Palette.emerald, prominent: true))
                }

                Button {
                    stopTimer(timer)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass(tint: TL.Palette.ember))
            }
        }
        .padding(TL.Space.m)
        .glassCard(tint: tint, cornerRadius: TL.Radius.xl, padding: 0, elevation: 2)
    }

    // MARK: - Paused list

    @ViewBuilder
    private var pausedListSection: some View {
        VStack(alignment: .leading, spacing: TL.Space.s) {
            HStack {
                Text("PAUSED · \(pausedTimers.count)")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(pausedTimers, id: \.localId) { t in
                PausedTimerRow(timer: t,
                               onResume: { resumeTimer(t) },
                               onStop: { stopTimer(t) },
                               onDelete: { deleteTimer(t) })
            }
        }
    }

    // MARK: - Actions

    private func pauseTimer(_ timer: ActiveTimerLocal) {
        timer.pause()
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func resumeTimer(_ timer: ActiveTimerLocal) {
        if let running = runningTimer, running.localId != timer.localId {
            running.pause()
        }
        timer.resume()
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func stopTimer(_ timer: ActiveTimerLocal) {
        let now = Int64(Date().timeIntervalSince1970)
        let entry = TimeEntryLocal(
            name: timer.name,
            category: timer.category,
            startedAt: timer.startedAt,
            endedAt: now,
            activeSecs: timer.activeSecs,
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

    private func deleteTimer(_ timer: ActiveTimerLocal) {
        if let serverId = timer.serverId {
            modelContext.insert(PendingDeletion(tableName: "active_timers", recordServerId: serverId))
        }
        modelContext.delete(timer)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }
}

// MARK: - Paused row

struct PausedTimerRow: View {
    let timer: ActiveTimerLocal
    let onResume: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let tint = TL.categoryColor(timer.category)
        HStack(spacing: TL.Space.s) {
            Rectangle()
                .fill(tint.gradient)
                .frame(width: 3)
                .cornerRadius(1.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.name)
                    .font(TL.TypeScale.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    CategoryChip(name: timer.category, compact: true)
                    Text(TL.clock(timer.activeSecs))
                        .font(TL.TypeScale.mono(12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { onResume() } label: {
                Image(systemName: "play.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(TL.Palette.emerald.gradient) }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 0)
        .padding(.trailing, TL.Space.s)
        .padding(.vertical, 6)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: 0)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onStop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .tint(TL.Palette.ember)
        }
    }
}
