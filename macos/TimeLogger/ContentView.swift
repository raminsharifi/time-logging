import SwiftUI

struct ContentView: View {
    @EnvironmentObject var api: APIClient
    @State private var selection: SidebarItem = .timers

    var runningTimer: TimerResponse? { api.timers.first { $0.isRunning } }

    var body: some View {
        HStack(spacing: 0) {
            TLSidebar(selection: $selection)
                .frame(width: 232)
                .background(Color(red: 0.055, green: 0.055, blue: 0.063)) // #0E0E10
                .overlay(alignment: .trailing) {
                    Rectangle().fill(TL.Palette.line).frame(width: 1)
                }

            DetailColumn(selection: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TL.Palette.bg)
        }
        .task { api.startPolling() }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .tlNavigateTo)) { note in
            guard let raw = note.userInfo?[NotificationKey.sidebarItem] as? String,
                  let item = SidebarItem(rawValue: raw) else { return }
            selection = item
        }
    }
}

// MARK: - Sidebar

private struct TLSidebar: View {
    @Binding var selection: SidebarItem
    @EnvironmentObject var api: APIClient

    @State private var day: [TimerResponse] = []

    var running: TimerResponse? { api.timers.first { $0.isRunning } }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            brandBlock

            VStack(spacing: 0) {
                MonoLabel("Workspace", size: 9, color: TL.Palette.dim)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(SidebarItem.allCases) { item in
                    sidebarRow(item)
                }
            }

            VStack(spacing: 0) {
                MonoLabel("Categories", size: 9, color: TL.Palette.dim)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Placeholder category rows — derived from running timer when available.
                let cats: [String] = {
                    let fromTimers = api.timers.map(\.category)
                    let fallback = ["Deep Work", "Meetings", "Review", "Admin", "Learning"]
                    let unique = Array(Set(fromTimers)).sorted()
                    return unique.isEmpty ? fallback : unique
                }()

                ForEach(cats, id: \.self) { name in
                    HStack(spacing: 10) {
                        Rectangle().fill(TL.categoryColor(name)).frame(width: 8, height: 8)
                        Text(name)
                            .font(.system(size: 12))
                            .foregroundStyle(TL.Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                }
            }

            Spacer(minLength: 0)

            todayFooter
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Time Logger", size: 9, color: TL.Palette.dim).tracking(1.8)
            HStack(spacing: 8) {
                if let r = running {
                    PulsingDot(color: TL.categoryColor(r.category), size: 5)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    MonoNum(running.map { TL.clock($0.active_secs) } ?? "00:00:00",
                            size: 22, weight: .semibold, color: TL.Palette.ink)
                }
            }
            Text(running?.name ?? "No timer running")
                .font(.system(size: 12))
                .foregroundStyle(running != nil ? TL.Palette.ink : TL.Palette.mute)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        let selected = item == selection
        Button { selection = item } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? TL.Palette.ink : TL.Palette.mute)
                    .frame(width: 16)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? TL.Palette.ink : TL.Palette.mute)
                Spacer()
                if selected {
                    Text(shortcut(for: item))
                        .font(TL.TypeScale.label(9))
                        .tracking(1.2)
                        .foregroundStyle(TL.Palette.dim)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: TL.Radius.s)
                    .fill(selected ? TL.Palette.raised : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func shortcut(for item: SidebarItem) -> String {
        switch item {
        case .timers:    "⌘1"
        case .log:       "⌘2"
        case .analytics: "⌘3"
        case .todos:     "⌘4"
        case .pomodoro:  "⌘5"
        case .devices:   "⌘6"
        }
    }

    private var todayFooter: some View {
        let total = api.timers.reduce(Int64(0)) { $0 + $1.active_secs }
        let goal: Int64 = 8 * 3600
        let pct = min(1.0, Double(total) / Double(goal))
        return VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Today · goal 8h", size: 9, color: TL.Palette.dim)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(TL.Palette.raised)
                    Rectangle().fill(TL.Palette.accent).frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 4)
            HStack {
                MonoNum(TL.clockShort(total), size: 12, weight: .semibold, color: TL.Palette.ink)
                Spacer()
                MonoLabel("\(Int(pct * 100))%", size: 9, color: TL.Palette.accent)
            }
        }
        .padding(14)
        .overlay(alignment: .top) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }
}

// MARK: - Detail

private struct DetailColumn: View {
    let selection: SidebarItem

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Group {
                switch selection {
                case .timers:    TimersView()
                case .log:       EntriesView()
                case .todos:     TodosView()
                case .pomodoro:  PomodoroView()
                case .analytics: AnalyticsView()
                case .devices:   DevicesView()
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            MonoLabel(dateCaption(), color: TL.Palette.ink).tracking(1.4)
            MonoLabel("W\(weekNumber())", color: TL.Palette.dim)
            Spacer()
            shortcutChip(key: "⌘K", label: "Quick start")
            shortcutChip(key: "⌘⇧N", label: "New entry")
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Color(red: 0.047, green: 0.047, blue: 0.055)) // #0C0C0E
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private func shortcutChip(key: String, label: String) -> some View {
        HStack(spacing: 6) {
            MonoLabel(key, size: 9, color: TL.Palette.dim)
            MonoLabel(label, size: 10, color: TL.Palette.mute)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay {
            RoundedRectangle(cornerRadius: TL.Radius.m)
                .strokeBorder(TL.Palette.line, lineWidth: 1)
        }
    }

    private func dateCaption() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        return df.string(from: .now).uppercased()
    }

    private func weekNumber() -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)
    }
}
