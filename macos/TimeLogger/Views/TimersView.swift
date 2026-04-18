import SwiftUI

struct TimersView: View {
    @EnvironmentObject var api: APIClient
    @State private var todayEntries: [EntryResponse] = []
    @State private var weekEntries:  [EntryResponse] = []
    @State private var showNewTimer = false

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var running: TimerResponse? { api.timers.first { $0.isRunning } }
    var paused:  [TimerResponse] { api.timers.filter { $0.isPaused } }

    private var dayStart: Int64 {
        Int64(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
    }

    private var todayTotal: Int64 {
        todayEntries.reduce(0) { $0 + $1.active_secs } + (running?.active_secs ?? 0)
    }

    private var weekDays: [(date: Date, entries: [EntryResponse], secs: Int64)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).map { i -> (Date, [EntryResponse], Int64) in
            let d = cal.date(byAdding: .day, value: -(6 - i), to: today)!
            let ds = Int64(d.timeIntervalSince1970)
            let de = ds + 86400
            let ents = weekEntries.filter { $0.started_at >= ds && $0.started_at < de }
            let secs = ents.reduce(0) { $0 + $1.active_secs }
            return (d, ents, secs)
        }
    }

    private var categorySums: [(cat: String, secs: Int64)] {
        var acc: [String: Int64] = [:]
        for e in todayEntries { acc[e.category, default: 0] += e.active_secs }
        if let r = running { acc[r.category, default: 0] += r.active_secs }
        return acc.sorted { $0.value > $1.value }.map { (cat: $0.key, secs: $0.value) }
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                leftColumn
                rightColumn.frame(width: 340)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .scrollContentBackground(.hidden)
        .task { await reload() }
        .onReceive(refreshTimer) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tlNewTimer)) { _ in
            showNewTimer = true
        }
        .sheet(isPresented: $showNewTimer) {
            NewTimerSheet { await api.refreshTimers() }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 28) {
            heroBlock
            weekBlock
            sessionsBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Today · 24h horizon")
                    heroCounter
                }
                Spacer()
                if let r = running {
                    livePill(for: r)
                } else {
                    newTimerButton
                }
            }
            horizonBar(height: 72, showScale: true)
            if running == nil && !paused.isEmpty {
                pausedRow
            }
        }
    }

    private var pausedRow: some View {
        HStack(spacing: 8) {
            MonoLabel("PAUSED", size: 9, color: TL.Palette.dim)
            ForEach(paused) { p in
                HStack(spacing: 6) {
                    Circle()
                        .fill(TL.categoryColor(p.category))
                        .frame(width: 6, height: 6)
                    Text(p.name)
                        .font(TL.TypeScale.caption)
                        .lineLimit(1)
                    Text(TL.clockShort(p.active_secs))
                        .font(TL.TypeScale.mono(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        Task { _ = try? await api.resumeTimer(id: p.id); await api.refreshTimers() }
                    } label: {
                        Image(systemName: "play.fill").font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(TL.Palette.emerald)
                    Button(role: .destructive) {
                        Task { _ = try? await api.stopTimer(id: p.id); await api.refreshTimers() }
                    } label: {
                        Image(systemName: "stop.fill").font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(TL.Palette.ember)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var newTimerButton: some View {
        Button {
            showNewTimer = true
        } label: {
            Label("New Timer", systemImage: "plus.circle.fill")
                .font(TL.TypeScale.body.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(TL.Palette.emerald)
        .controlSize(.large)
        .keyboardShortcut("n", modifiers: [.command])
    }

    private var heroCounter: some View {
        let total = todayTotal
        let h = total / 3600
        let m = (total % 3600) / 60
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            MonoNum("\(h)", size: 72, weight: .medium, color: TL.Palette.ink)
            Text("H")
                .font(TL.TypeScale.mono(36, weight: .medium))
                .foregroundStyle(TL.Palette.mute)
            MonoNum(String(format: "%02d", m), size: 72, weight: .medium, color: TL.Palette.ink)
                .padding(.leading, 8)
            Text("M")
                .font(TL.TypeScale.mono(36, weight: .medium))
                .foregroundStyle(TL.Palette.mute)
        }
    }

    @ViewBuilder
    private func livePill(for r: TimerResponse) -> some View {
        let tint = TL.categoryColor(r.category)
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 6) {
                PulsingDot(color: tint, size: 4)
                MonoLabel("LIVE · \(r.category.uppercased())", color: tint)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: TL.Radius.s)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                MonoNum(TL.clock(r.active_secs), size: 30, weight: .semibold, color: TL.Palette.ink)
            }
            Text("\(r.name) · started \(timeOfDay(r.started_at))")
                .font(.system(size: 12))
                .foregroundStyle(TL.Palette.mute)

            HStack(spacing: 6) {
                Button {
                    Task { _ = try? await api.pauseTimer(id: r.id); await api.refreshTimers() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task { _ = try? await api.stopTimer(id: r.id); await api.refreshTimers() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(TL.Palette.ember)
            }
        }
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Week \(weekNumber()) · \(weekRangeText())", color: TL.Palette.ink)
                Spacer()
                HStack(spacing: 18) {
                    stat("TOTAL", TL.clockShort(weekEntries.reduce(0) { $0 + $1.active_secs }))
                    stat("AVG", TL.clockShort(weekEntries.reduce(0) { $0 + $1.active_secs } / 7))
                    stat("GOAL HIT", goalHitText(), accent: true)
                }
            }
            ForEach(Array(weekDays.enumerated()), id: \.offset) { i, d in
                weekRow(d, isToday: i == weekDays.count - 1)
            }
            HStack {
                Spacer().frame(width: 64)
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                        Text(String(format: "%02d:00", h))
                            .font(TL.TypeScale.mono(9))
                            .foregroundStyle(TL.Palette.dim)
                        if h != 24 { Spacer() }
                    }
                }
                Spacer().frame(width: 68)
            }
        }
    }

    private func stat(_ label: String, _ value: String, accent: Bool = false) -> some View {
        HStack(spacing: 4) {
            MonoLabel(label, size: 9, color: TL.Palette.dim)
            MonoNum(value, size: 13, weight: .semibold,
                    color: accent ? TL.Palette.accent : TL.Palette.ink)
        }
    }

    @ViewBuilder
    private func weekRow(_ d: (date: Date, entries: [EntryResponse], secs: Int64), isToday: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                MonoLabel(dayName(d.date), size: 10,
                          color: isToday ? TL.Palette.accent : TL.Palette.mute)
                MonoNum("\(Calendar.current.component(.day, from: d.date))", size: 12, weight: .semibold,
                        color: isToday ? TL.Palette.ink : TL.Palette.mute)
            }
            .frame(width: 52, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(TL.Palette.raised)
                    ForEach([6, 12, 18], id: \.self) { h in
                        Rectangle().fill(TL.Palette.line).frame(width: 1)
                            .offset(x: geo.size.width * CGFloat(Double(h) / 24))
                    }
                    let ds = Int64(d.date.timeIntervalSince1970)
                    ForEach(d.entries) { e in
                        let l = Double(e.started_at - ds) / 86400
                        let w = Double(e.ended_at - e.started_at) / 86400
                        Rectangle()
                            .fill(TL.categoryColor(e.category))
                            .opacity(0.85)
                            .frame(width: max(1, geo.size.width * CGFloat(w)),
                                   height: geo.size.height - 4)
                            .offset(x: geo.size.width * CGFloat(l), y: 2)
                    }
                    if isToday, let r = running {
                        let l = Double(r.started_at - ds) / 86400
                        let nowPct = Double(Date().timeIntervalSince1970 - Double(ds)) / 86400
                        let w = max(0, nowPct - l)
                        let color = TL.categoryColor(r.category)
                        Rectangle()
                            .fill(color)
                            .frame(width: max(1, geo.size.width * CGFloat(w)),
                                   height: geo.size.height)
                            .offset(x: geo.size.width * CGFloat(l))
                        Rectangle().fill(TL.Palette.ink)
                            .frame(width: 2, height: geo.size.height + 4)
                            .offset(x: geo.size.width * CGFloat(nowPct) - 1, y: -2)
                    }
                }
            }
            .frame(height: 18)
            .overlay { Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1) }

            MonoNum(d.secs > 0 ? TL.clockShort(d.secs) : "—", size: 12, weight: .semibold,
                    color: d.secs > 0 ? TL.Palette.ink : TL.Palette.dim)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var sessionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel("Sessions · \(todayEntries.count + (running == nil ? 0 : 1))", color: TL.Palette.ink)
                Spacer()
                MonoLabel("Newest first", color: TL.Palette.dim)
            }
            VStack(spacing: 0) {
                if let r = running {
                    sessionRow(RunningAsEntry(from: r), isLive: true)
                }
                ForEach(todayEntries.reversed()) { e in
                    sessionRow(e, isLive: false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: TL.Radius.m)
                    .strokeBorder(TL.Palette.line, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ e: EntryResponse, isLive: Bool) -> some View {
        let tint = TL.categoryColor(e.category)
        HStack(spacing: 14) {
            Rectangle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: isLive ? tint.opacity(0.8) : .clear, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TL.Palette.ink)
                    .lineLimit(1)
                MonoLabel(e.category + (isLive ? " · Running" : ""), size: 9, color: TL.Palette.mute)
            }
            Spacer(minLength: 0)
            MonoNum(rangeText(e, live: isLive), size: 11, color: TL.Palette.mute)
                .frame(width: 140, alignment: .trailing)
            MonoNum(TL.clockShort(e.active_secs), size: 13, weight: .semibold, color: TL.Palette.ink)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isLive ? Color.white.opacity(0.015) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            categoryPanel
            todosPanel
            shortcutsPanel
        }
    }

    private var categoryPanel: some View {
        let total = max(todayTotal, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoLabel("Category · today", color: TL.Palette.ink)
                Spacer()
                MonoLabel(TL.clockShort(todayTotal), color: TL.Palette.dim)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(categorySums, id: \.cat) { c in
                        Rectangle()
                            .fill(TL.categoryColor(c.cat))
                            .frame(width: geo.size.width * CGFloat(Double(c.secs) / Double(total)))
                    }
                }
            }
            .frame(height: 10)
            .overlay { Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1) }
            VStack(spacing: 10) {
                ForEach(categorySums, id: \.cat) { c in
                    HStack(spacing: 10) {
                        Rectangle().fill(TL.categoryColor(c.cat)).frame(width: 10, height: 10)
                        Text(c.cat)
                            .font(.system(size: 12))
                            .foregroundStyle(TL.Palette.ink)
                        Spacer()
                        MonoNum(TL.clockShort(c.secs), size: 12, weight: .semibold, color: TL.Palette.ink)
                        MonoNum("\(Int(round(Double(c.secs) / Double(total) * 100)))%",
                                size: 10, color: TL.Palette.mute)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                if categorySums.isEmpty {
                    MonoLabel("No activity", size: 10, color: TL.Palette.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
        }
        .padding(16)
        .surface(padding: 0)
    }

    private var todosPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel("Todos · today", color: TL.Palette.ink)
                Spacer()
                Button {
                    Task { await api.refreshTimers() }
                } label: {
                    MonoLabel("Refresh", color: TL.Palette.dim)
                }
                .buttonStyle(.plain)
            }
            MonoLabel("Open the Todos tab to manage tasks on this Mac.",
                      size: 10, color: TL.Palette.dim).tracking(0.3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 0)
    }

    private var shortcutsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Shortcuts", color: TL.Palette.ink)
            let items: [(String, String)] = [
                ("⌘K",  "Quick start"),
                ("⌘⇧N", "New entry"),
                ("⌘P",  "Pause / resume"),
                ("⌘.",  "Stop"),
                ("⌘1—6","Switch tab"),
            ]
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.0) { it in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        MonoLabel(it.0, size: 10, color: TL.Palette.dim)
                            .frame(width: 52, alignment: .leading)
                        Text(it.1)
                            .font(.system(size: 12))
                            .foregroundStyle(TL.Palette.ink)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(padding: 0)
    }

    // MARK: - Horizon bar

    private func horizonBar(height: CGFloat, showScale: Bool) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(TL.Palette.surface)
                    Rectangle().fill(Color.white.opacity(0.015))
                        .frame(width: nowOffset(in: geo.size.width))
                    ForEach(0..<25, id: \.self) { i in
                        let major = i % 6 == 0
                        Rectangle()
                            .fill(major ? TL.Palette.lineHi : TL.Palette.line)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .offset(x: geo.size.width * CGFloat(Double(i) / 24))
                            .opacity((i == 0 || i == 24) ? 0 : 1)
                    }
                    ForEach(todayEntries) { e in
                        let l = Double(e.started_at - dayStart) / 86400
                        let w = Double(e.ended_at - e.started_at) / 86400
                        Rectangle()
                            .fill(TL.categoryColor(e.category))
                            .opacity(0.85)
                            .frame(width: max(1, geo.size.width * CGFloat(w)),
                                   height: geo.size.height - 16)
                            .offset(x: geo.size.width * CGFloat(l), y: 8)
                    }
                    if let r = running {
                        let l = Double(r.started_at - dayStart) / 86400
                        let nowPct = Double(Date().timeIntervalSince1970 - Double(dayStart)) / 86400
                        let w = max(0, nowPct - l)
                        let color = TL.categoryColor(r.category)
                        Rectangle()
                            .fill(color)
                            .frame(width: max(1, geo.size.width * CGFloat(w)),
                                   height: geo.size.height - 8)
                            .offset(x: geo.size.width * CGFloat(l), y: 4)
                            .shadow(color: color.opacity(0.6), radius: 8)
                        Rectangle().fill(TL.Palette.ink)
                            .frame(width: 2, height: geo.size.height + 4)
                            .offset(x: geo.size.width * CGFloat(nowPct) - 1, y: -2)
                            .shadow(color: TL.Palette.ink.opacity(0.8), radius: 6)
                        Circle().fill(TL.Palette.ink)
                            .frame(width: 10, height: 10)
                            .offset(x: geo.size.width * CGFloat(nowPct) - 5, y: -5)
                            .shadow(color: TL.Palette.ink.opacity(0.6), radius: 6)
                    }
                }
            }
            .frame(height: height)
            .overlay { Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1) }

            if showScale {
                HStack {
                    ForEach([0, 3, 6, 9, 12, 15, 18, 21, 24], id: \.self) { h in
                        Text(String(format: "%02d:00", h))
                            .font(TL.TypeScale.mono(9))
                            .foregroundStyle(TL.Palette.dim)
                        if h != 24 { Spacer() }
                    }
                }
            }
        }
    }

    private func nowOffset(in width: CGFloat) -> CGFloat {
        let nowPct = Double(Date().timeIntervalSince1970 - Double(dayStart)) / 86400
        return width * CGFloat(max(0, min(1, nowPct)))
    }

    // MARK: - Data / helpers

    private func reload() async {
        async let today: [EntryResponse] = api.getEntries(today: true)
        async let week: [EntryResponse]  = api.getEntries(week: true)
        todayEntries = (try? await today) ?? todayEntries
        weekEntries  = (try? await week)  ?? weekEntries
    }

    private func weekNumber() -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)
    }

    private func weekRangeText() -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -6, to: today)!
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(df.string(from: start)) — \(df.string(from: today))".uppercased()
    }

    private func goalHitText() -> String {
        let hit = weekDays.filter { $0.secs >= 8 * 3600 }.count
        return "\(hit)/7"
    }

    private func dayName(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df.string(from: d).uppercased()
    }

    private func timeOfDay(_ ts: Int64) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts))).lowercased()
    }

    private func rangeText(_ e: EntryResponse, live: Bool) -> String {
        let start = timeOfDay(e.started_at).uppercased()
        if live { return "\(start) — NOW" }
        let end = timeOfDay(e.ended_at).uppercased()
        return "\(start) — \(end)"
    }
}

// MARK: - Bridge: render the running timer as an EntryResponse for the sessions table

private func RunningAsEntry(from t: TimerResponse) -> EntryResponse {
    EntryResponse(
        id: t.id,
        name: t.name,
        category: t.category,
        started_at: t.started_at,
        ended_at: Int64(Date().timeIntervalSince1970),
        active_secs: t.active_secs,
        break_secs: t.break_secs,
        todo_id: t.todo_id,
        last_modified: t.last_modified
    )
}
