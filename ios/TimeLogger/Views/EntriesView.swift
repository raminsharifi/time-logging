import SwiftUI
import SwiftData

enum EntryFilter: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case all = "All"
}

struct EntriesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \TimeEntryLocal.endedAt, order: .reverse) private var allEntries: [TimeEntryLocal]

    @State private var filter: EntryFilter = .today
    @State private var selectedEntry: TimeEntryLocal?
    @State private var selectedDay: Date?

    var filteredEntries: [TimeEntryLocal] {
        let now = Date()
        let entries: [TimeEntryLocal]
        switch filter {
        case .all:
            entries = allEntries
        case .today:
            let startOfDay = Calendar.current.startOfDay(for: now)
            let ts = Int64(startOfDay.timeIntervalSince1970)
            entries = allEntries.filter { $0.startedAt >= ts }
        case .week:
            let weekAgo = Int64(now.timeIntervalSince1970) - 7 * 86400
            entries = allEntries.filter { $0.startedAt >= weekAgo }
        case .month:
            let monthAgo = Int64(now.timeIntervalSince1970) - 30 * 86400
            entries = allEntries.filter { $0.startedAt >= monthAgo }
        }
        guard let selectedDay else { return entries }
        let cal = Calendar.current
        return entries.filter { cal.isDate(Date(timeIntervalSince1970: Double($0.startedAt)), inSameDayAs: selectedDay) }
    }

    var totalActiveSecs: Int64 {
        filteredEntries.reduce(0) { $0 + $1.activeSecs }
    }

    /// [Date: totalSecs] across the last 35 days (5 rows × 7 cols) for the heatmap.
    var heatmapData: [(Date, Int64)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<35).map { cal.date(byAdding: .day, value: -34 + $0, to: today)! }
        var buckets: [Date: Int64] = [:]
        for entry in allEntries {
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: Double(entry.startedAt)))
            buckets[d, default: 0] += entry.activeSecs
        }
        return days.map { ($0, buckets[$0] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TL.Space.m) {
                    heatmapCard

                    filterPills

                    totalsRow

                    if filteredEntries.isEmpty {
                        emptyCard
                    } else {
                        entriesList
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
                    Text("Log").font(TL.TypeScale.headline)
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailView(entry: entry)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Heatmap

    @ViewBuilder
    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LAST 5 WEEKS")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let selectedDay {
                    Button {
                        withAnimation(TL.Motion.smooth) { self.selectedDay = nil }
                    } label: {
                        Text(selectedDay.formatted(.dateTime.month().day()))
                            .font(TL.TypeScale.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background {
                                Capsule().fill(.ultraThinMaterial)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            let maxSecs = max(heatmapData.map(\.1).max() ?? 1, 1)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(heatmapData, id: \.0) { day, secs in
                    dayCell(day: day, secs: secs, maxSecs: maxSecs)
                        .onTapGesture {
                            withAnimation(TL.Motion.smooth) {
                                selectedDay = (selectedDay == day) ? nil : day
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    @ViewBuilder
    private func dayCell(day: Date, secs: Int64, maxSecs: Int64) -> some View {
        let t = maxSecs == 0 ? 0 : Double(secs) / Double(maxSecs)
        let isSelected = selectedDay == day
        let isToday = Calendar.current.isDateInToday(day)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(TL.Palette.emerald.opacity(0.12 + 0.7 * t))
            .frame(height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? .white : (isToday ? TL.Palette.emerald : .clear),
                                  lineWidth: isSelected ? 1.5 : 1)
            }
    }

    // MARK: - Filter pills

    @ViewBuilder
    private var filterPills: some View {
        HStack(spacing: 6) {
            ForEach(EntryFilter.allCases, id: \.self) { f in
                Button {
                    withAnimation(TL.Motion.smooth) { filter = f }
                } label: {
                    Text(f.rawValue)
                        .font(TL.TypeScale.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(filter == f ? .white : .primary.opacity(0.75))
                        .background {
                            if filter == f {
                                Capsule().fill(TL.Palette.sky.gradient)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Totals

    @ViewBuilder
    private var totalsRow: some View {
        if !filteredEntries.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                    Text(TL.clock(totalActiveSecs))
                        .font(TL.TypeScale.mono(22, weight: .semibold))
                        .foregroundStyle(TL.Palette.citrine)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ENTRIES")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(filteredEntries.count)")
                        .font(TL.TypeScale.mono(22, weight: .semibold))
                }
            }
            .padding(.horizontal, TL.Space.s)
        }
    }

    // MARK: - Entries

    @ViewBuilder
    private var entriesList: some View {
        VStack(spacing: 8) {
            ForEach(filteredEntries, id: \.localId) { entry in
                EntryRow(entry: entry)
                    .onTapGesture {
                        selectedEntry = entry
                    }
            }
        }
    }

    @ViewBuilder
    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text("No entries")
                .font(TL.TypeScale.callout)
            Text("Completed timers will show up here.")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TL.Space.l)
        .glassCard(tint: TL.Palette.mist, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    private func deleteEntry(_ entry: TimeEntryLocal) {
        if let serverId = entry.serverId {
            modelContext.insert(PendingDeletion(tableName: "time_entries", recordServerId: serverId))
        }
        modelContext.delete(entry)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }
}

// MARK: - Entry Row (glass)

struct EntryRow: View {
    let entry: TimeEntryLocal

    var body: some View {
        let tint = TL.categoryColor(entry.category)
        HStack(spacing: 0) {
            Rectangle()
                .fill(tint.gradient)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(TL.TypeScale.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    CategoryChip(name: entry.category, compact: true)
                    Text(dateString(entry.startedAt))
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, TL.Space.s)

            Spacer(minLength: 8)

            Text(TL.clock(entry.activeSecs))
                .font(TL.TypeScale.mono(14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.trailing, TL.Space.s)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 4)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: 0)
    }

    func dateString(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today · \(formatter.string(from: date))" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(formatter.string(from: date))" }
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

extension TimeEntryLocal: @retroactive Identifiable {
    public var id: String { localId }
}
