import SwiftUI
import SwiftData

enum EntryFilter: String, CaseIterable {
    case today = "Today"
    case week  = "Week"
    case month = "Month"
    case all   = "All"
}

struct EntriesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var syncEngine: SyncEngine

    @Query(sort: \TimeEntryLocal.endedAt, order: .reverse)
    private var allEntries: [TimeEntryLocal]

    @State private var filter: EntryFilter = .today
    @State private var selectedEntry: TimeEntryLocal?
    @State private var isSelecting: Bool = false
    @State private var selectedIds: Set<String> = []

    private var filteredEntries: [TimeEntryLocal] {
        let now = Int64(Date().timeIntervalSince1970)
        switch filter {
        case .all: return allEntries
        case .today:
            let d = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
            return allEntries.filter { $0.startedAt >= d }
        case .week:  return allEntries.filter { $0.startedAt >= now - 7 * 86400 }
        case .month: return allEntries.filter { $0.startedAt >= now - 30 * 86400 }
        }
    }

    private var totalSecs: Int64 { filteredEntries.reduce(0) { $0 + $1.activeSecs } }

    private var avgSecs: Int64 {
        filteredEntries.isEmpty ? 0 : totalSecs / Int64(filteredEntries.count)
    }

    /// Groups entries by calendar day, newest first.
    private var groups: [(date: Date, items: [TimeEntryLocal], totalSecs: Int64)] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: filteredEntries) { entry in
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(entry.startedAt)))
        }
        return buckets
            .map { (date: $0.key, items: $0.value, totalSecs: $0.value.reduce(0) { $0 + $1.activeSecs }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    title: "Log",
                    caption: tlStatusCaption(),
                    right: { headerRight }
                )

                VStack(alignment: .leading, spacing: 20) {
                    filterRow.padding(.top, 16)
                    if isSelecting { selectionBar }
                    kpiStrip
                    groupList
                }
                .padding(.horizontal, TL.Space.l)
                .padding(.bottom, TL.Space.l)
            }
        }
        .background(TL.Palette.bg)
        .scrollContentBackground(.hidden)
        .sheet(item: $selectedEntry) { e in
            EntryDetailView(entry: e)
                .presentationDetents([.medium, .large])
                .presentationBackground(TL.Palette.bg)
        }
        .onChange(of: filter) { _, _ in selectedIds = [] }
    }

    // MARK: - Header + selection

    @ViewBuilder
    private var headerRight: some View {
        if isSelecting {
            Button {
                isSelecting = false
                selectedIds = []
            } label: {
                Text("CANCEL").tracking(1.2)
                    .font(TL.TypeScale.label(10))
                    .foregroundStyle(TL.Palette.ink)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                MonoLabel("\(filteredEntries.count) entries", color: TL.Palette.ink)
                Button {
                    isSelecting = true
                } label: {
                    Text("SELECT").tracking(1.2)
                        .font(TL.TypeScale.label(10))
                        .foregroundStyle(TL.Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectionBar: some View {
        let visibleIds = Set(filteredEntries.map(\.localId))
        let allSelected = !visibleIds.isEmpty && visibleIds.isSubset(of: selectedIds)
        return HStack(spacing: 10) {
            Button {
                if allSelected {
                    selectedIds.subtract(visibleIds)
                } else {
                    selectedIds.formUnion(visibleIds)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(allSelected ? TL.Palette.accent : TL.Palette.mute)
                    Text(allSelected ? "CLEAR" : "SELECT ALL").tracking(1.2)
                        .font(TL.TypeScale.label(10))
                        .foregroundStyle(TL.Palette.ink)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            MonoLabel("\(selectedIds.count) selected", color: TL.Palette.dim)

            Button {
                deleteSelected()
            } label: {
                Text("DELETE").tracking(1.2)
                    .font(TL.TypeScale.label(10))
                    .foregroundStyle(selectedIds.isEmpty ? TL.Palette.mute : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: TL.Radius.s)
                            .fill(selectedIds.isEmpty ? TL.Palette.raised : Color.red)
                    }
            }
            .buttonStyle(.plain)
            .disabled(selectedIds.isEmpty)
        }
    }

    // MARK: - Filter

    private var filterRow: some View {
        HStack(spacing: 4) {
            ForEach(EntryFilter.allCases, id: \.self) { f in
                FilterPill(label: f.rawValue, isSelected: filter == f) {
                    filter = f
                }
            }
            Spacer()
        }
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            kpiCell("Total", TL.clockShort(totalSecs))
            divider
            kpiCell("Sessions", "\(filteredEntries.count)")
            divider
            kpiCell("Avg", filteredEntries.isEmpty ? "—" : TL.clockShort(avgSecs))
        }
        .overlay {
            Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
        }
        .background(TL.Palette.surface)
    }

    private func kpiCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(label)
            MonoNum(value, size: 20, weight: .semibold, color: TL.Palette.ink)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(TL.Palette.line).frame(width: 1)
    }

    // MARK: - Grouped list

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 24) {
            if groups.isEmpty {
                emptyState
            } else {
                ForEach(groups, id: \.date) { g in
                    dayGroup(g)
                }
            }
        }
    }

    @ViewBuilder
    private func dayGroup(_ g: (date: Date, items: [TimeEntryLocal], totalSecs: Int64)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(dayLabel(g.date), color: TL.Palette.ink)
                Spacer()
                MonoNum(TL.clockShort(g.totalSecs), size: 10, color: TL.Palette.mute)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TL.Palette.line).frame(height: 1)
            }
            .padding(.bottom, 10)

            LazyVStack(spacing: 0) {
                ForEach(g.items, id: \.localId) { e in
                    if isSelecting {
                        entryRow(e)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSelection(e) }
                    } else {
                        SwipeToDelete(onDelete: { deleteEntry(e) }) {
                            entryRow(e)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedEntry = e }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ e: TimeEntryLocal) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if isSelecting {
                let selected = selectedIds.contains(e.localId)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? TL.Palette.accent : TL.Palette.mute)
                    .frame(width: 22)
            }
            MonoNum(timeOfDay(e.startedAt), size: 11, color: TL.Palette.dim)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name)
                    .font(.system(size: 14))
                    .foregroundStyle(TL.Palette.ink)
                    .lineLimit(1)
                CategoryTag(name: e.category, compact: true)
            }
            Spacer()
            MonoNum(TL.clockShort(e.activeSecs), size: 13, weight: .semibold,
                    color: TL.categoryColor(e.category))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(TL.Palette.dim)
            Text("No entries yet")
                .font(.system(size: 14))
                .foregroundStyle(TL.Palette.mute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .surface(padding: 0)
    }

    // MARK: - Helpers

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        return df.string(from: date)
    }

    private func timeOfDay(_ ts: Int64) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func deleteEntry(_ entry: TimeEntryLocal) {
        if let sid = entry.serverId {
            let now = Int64(Date().timeIntervalSince1970)
            let deletedAt = max(now, entry.lastModified + 1)
            modelContext.insert(PendingDeletion(
                tableName: "time_entries",
                recordServerId: sid,
                deletedAt: deletedAt
            ))
        }
        modelContext.delete(entry)
        try? modelContext.save()
        syncEngine.scheduleSyncAfterMutation()
    }

    private func toggleSelection(_ entry: TimeEntryLocal) {
        if selectedIds.contains(entry.localId) {
            selectedIds.remove(entry.localId)
        } else {
            selectedIds.insert(entry.localId)
        }
    }

    private func deleteSelected() {
        guard !selectedIds.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let targets = filteredEntries.filter { selectedIds.contains($0.localId) }
        for entry in targets {
            if let sid = entry.serverId {
                let deletedAt = max(now, entry.lastModified + 1)
                modelContext.insert(PendingDeletion(
                    tableName: "time_entries",
                    recordServerId: sid,
                    deletedAt: deletedAt
                ))
            }
            modelContext.delete(entry)
        }
        try? modelContext.save()
        selectedIds = []
        isSelecting = false
        syncEngine.scheduleSyncAfterMutation()
    }
}

extension TimeEntryLocal: @retroactive Identifiable {
    public var id: String { localId }
}
