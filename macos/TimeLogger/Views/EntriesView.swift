import SwiftUI

enum EntryFilter: String, CaseIterable {
    case today = "Today"
    case week = "This Week"
    case all = "All"
}

struct EntriesView: View {
    @EnvironmentObject var api: APIClient
    @State private var wideRangeEntries: [EntryResponse] = []
    @State private var filter: EntryFilter = .today
    @State private var selectedEntryId: Int?
    @State private var editingEntry: EntryResponse?
    @State private var errorBanner: String?

    /// Today → live stream from APIClient. Week/All → an explicit one-off fetch
    /// that populates `wideRangeEntries`.
    var entries: [EntryResponse] {
        filter == .today ? api.todayEntries : wideRangeEntries
    }

    var selectedEntry: EntryResponse? {
        guard let id = selectedEntryId else { return nil }
        return entries.first { $0.id == id }
    }

    var totalSecs: Int64 { entries.reduce(0) { $0 + $1.active_secs } }

    // 5-week heatmap dates (descending)
    var heatmapDays: [(Date, Int64)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var buckets: [Date: Int64] = [:]
        for e in entries {
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(e.started_at)))
            buckets[d, default: 0] += e.active_secs
        }
        return (0..<35).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return (d, buckets[d] ?? 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TL.Space.m) {
            if let err = errorBanner {
                MutationBanner(message: err) { errorBanner = nil }
                    .padding(.horizontal, TL.Space.m)
                    .padding(.top, TL.Space.m)
            }

            HStack(spacing: TL.Space.s) {
                filterPicker
                Spacer()
                Text("Total: \(formatDuration(totalSecs))")
                    .font(TL.TypeScale.mono(14, weight: .semibold))
                    .foregroundStyle(TL.Palette.iris)
            }
            .padding(.horizontal, TL.Space.m)
            .padding(.top, errorBanner == nil ? TL.Space.m : 0)

            heatmapCard
                .padding(.horizontal, TL.Space.m)

            entryTable
        }
        .sheet(item: $editingEntry) { e in
            EntryDetailSheet(entry: e) { await api.pokeNow(); await loadEntries() }
        }
        .onChange(of: filter) { _, _ in Task { await loadEntries() } }
        .task { await loadEntries() }
    }

    @ViewBuilder
    private var filterPicker: some View {
        HStack(spacing: 4) {
            ForEach(EntryFilter.allCases, id: \.self) { f in
                Button {
                    filter = f
                } label: {
                    Text(f.rawValue)
                        .font(TL.TypeScale.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(filter == f ? .white : .primary.opacity(0.7))
                        .background {
                            if filter == f {
                                Capsule().fill(TL.Palette.citrine.gradient)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var heatmapCard: some View {
        let days = heatmapDays
        let maxSecs = days.map { $0.1 }.max() ?? 1
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVITY — LAST 5 WEEKS")
                .font(TL.TypeScale.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(days, id: \.0) { pair in
                    let (_, secs) = pair
                    let intensity = maxSecs > 0 ? Double(secs) / Double(maxSecs) : 0
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            intensity > 0
                                ? TL.Palette.iris.opacity(0.2 + intensity * 0.8)
                                : Color.primary.opacity(0.06)
                        )
                        .frame(height: 18)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.m, elevation: 6)
    }

    @ViewBuilder
    private var entryTable: some View {
        Table(entries, selection: $selectedEntryId) {
            TableColumn("Name") { entry in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TL.categoryColor(entry.category))
                        .frame(width: 3, height: 18)
                    Text(entry.name)
                }
            }
            .width(min: 140)

            TableColumn("Category") { entry in
                CategoryChip(name: entry.category)
            }
            .width(min: 80, max: 160)

            TableColumn("Started") { entry in
                Text(formatDateShort(entry.started_at))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, max: 180)

            TableColumn("Duration") { entry in
                Text(formatDuration(entry.active_secs))
                    .monospacedDigit()
                    .foregroundStyle(TL.Palette.iris)
            }
            .width(min: 80, max: 140)
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Int.self) { selection in
            if let id = selection.first, let entry = entries.first(where: { $0.id == id }) {
                Button("Edit...") { editingEntry = entry }
                Divider()
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await api.deleteEntry(id: entry.id)
                            await api.pokeNow()
                            await loadEntries()
                        } catch {
                            errorBanner = "Couldn't delete entry: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    /// Only fetches for non-today ranges — the today view is driven by the
    /// always-polling `api.todayEntries` stream.
    private func loadEntries() async {
        guard filter != .today else { return }
        wideRangeEntries = (try? await api.getEntries(
            today: false,
            week: filter == .week
        )) ?? []
    }
}


