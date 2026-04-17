import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntryLocal.endedAt, order: .reverse) private var allEntries: [TimeEntryLocal]

    @State private var range: Range = .week
    @State private var serverAnalytics: APIAnalyticsResponse?
    @State private var aggregates = AnalyticsAggregates()
    @State private var loadState: LoadState = .idle
    @State private var selectedCategory: String?

    enum Range: String, CaseIterable {
        case week = "Week", month = "Month"
        var days: Int { self == .week ? 7 : 30 }
        var apiName: String { self == .week ? "week" : "month" }
    }

    enum LoadState { case idle, loading, ready, empty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TL.Space.m) {
                    rangeToggle

                    HStack(spacing: TL.Space.s) {
                        totalCard
                        streakCard
                    }

                    stackedBarCard
                    donutCard
                }
                .padding(.horizontal, TL.Space.m)
                .padding(.top, TL.Space.s)
                .padding(.bottom, TL.Space.xl)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Stats").font(TL.TypeScale.headline)
                }
            }
            .task(id: range) { await loadAnalytics() }
            .onChange(of: allEntries.count) { _, _ in recomputeAggregates() }
            .onChange(of: serverAnalytics?.total_secs) { _, _ in recomputeAggregates() }
        }
    }

    // MARK: - Range toggle

    @ViewBuilder
    private var rangeToggle: some View {
        HStack(spacing: 6) {
            ForEach(Range.allCases, id: \.self) { r in
                Button {
                    withAnimation(TL.Motion.smooth) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(TL.TypeScale.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .foregroundStyle(range == r ? .white : .primary.opacity(0.7))
                        .background {
                            if range == r {
                                Capsule().fill(TL.Palette.iris.gradient)
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

    // MARK: - Cards

    @ViewBuilder
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOTAL")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
            Text(TL.clockShort(aggregates.totalSecs))
                .font(TL.TypeScale.mono(26, weight: .semibold))
                .foregroundStyle(TL.Palette.iris)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("\(range.days) days")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    @ViewBuilder
    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("STREAK")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(aggregates.streakDays)")
                    .font(TL.TypeScale.mono(26, weight: .semibold))
                    .foregroundStyle(TL.Palette.ember)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(aggregates.streakDays == 1 ? "day" : "days")
                    .font(TL.TypeScale.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "flame.fill")
                    .foregroundStyle(TL.Palette.ember)
            }
            Text("consecutive")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.ember, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    @ViewBuilder
    private var stackedBarCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DAILY BREAKDOWN")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(aggregates.unitLabel)
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            }

            chartContent {
                StackedBarChart(rows: aggregates.byDayCategory,
                                useHours: aggregates.useHours,
                                categories: aggregates.categoryOrder)
                    .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    @ViewBuilder
    private var donutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY SHARE")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            chartContent {
                DonutChart(slices: aggregates.byCategory,
                           totalSecs: aggregates.totalSecs,
                           selected: $selectedCategory)
                    .frame(height: 240)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.emerald, cornerRadius: TL.Radius.l, padding: TL.Space.s)
    }

    @ViewBuilder
    private func chartContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if loadState == .loading && aggregates.totalSecs == 0 {
            HStack { Spacer(); ProgressView(); Spacer() }
                .frame(height: 80)
        } else if aggregates.totalSecs == 0 {
            emptyMini
        } else {
            content()
        }
    }

    @ViewBuilder
    private var emptyMini: some View {
        Text("No data yet")
            .font(TL.TypeScale.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TL.Space.l)
    }

    // MARK: - Data

    func loadAnalytics() async {
        loadState = .loading
        if bleManager.isConnected {
            serverAnalytics = try? await bleManager.getAnalytics(range: range.apiName)
        } else {
            serverAnalytics = nil
        }
        recomputeAggregates()
    }

    private func recomputeAggregates() {
        let computed = AnalyticsAggregates.compute(
            range: range,
            serverAnalytics: serverAnalytics,
            allEntries: allEntries
        )
        aggregates = computed
        loadState = computed.totalSecs == 0 ? .empty : .ready
    }
}

// MARK: - Aggregates (memoized)

struct AnalyticsAggregates: Equatable {
    var totalSecs: Int64 = 0
    var streakDays: Int = 0
    var byDayCategory: [DayCategorySlice] = []
    var byCategory: [CategoryShare] = []
    var categoryOrder: [String] = []
    var useHours: Bool = false

    var unitLabel: String { useHours ? "hours" : "minutes" }

    struct DayCategorySlice: Identifiable, Equatable {
        let id: String
        let day: Date
        let category: String
        let secs: Int64
    }

    struct CategoryShare: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let secs: Int64
    }

    static func compute(
        range: AnalyticsView.Range,
        serverAnalytics: APIAnalyticsResponse?,
        allEntries: [TimeEntryLocal]
    ) -> AnalyticsAggregates {
        let cal = Calendar.current
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(range.days * 86400)
        let filtered = allEntries.filter { $0.startedAt >= cutoff }

        // Per-day-per-category (always computed locally — server doesn't expose this)
        var dayCat: [Date: [String: Int64]] = [:]
        for e in filtered {
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: Double(e.startedAt)))
            dayCat[d, default: [:]][e.category, default: 0] += e.activeSecs
        }
        var slices: [DayCategorySlice] = []
        for (d, cats) in dayCat.sorted(by: { $0.key < $1.key }) {
            for (cat, secs) in cats.sorted(by: { $0.value > $1.value }) {
                let id = "\(Int(d.timeIntervalSince1970))-\(cat)"
                slices.append(DayCategorySlice(id: id, day: d, category: cat, secs: secs))
            }
        }

        // Category totals — prefer server
        var byCategory: [CategoryShare]
        if let s = serverAnalytics {
            byCategory = s.by_category.map { CategoryShare(name: $0.name, secs: $0.secs) }
        } else {
            var acc: [String: Int64] = [:]
            for e in filtered { acc[e.category, default: 0] += e.activeSecs }
            byCategory = acc.sorted { $0.value > $1.value }.map { CategoryShare(name: $0.key, secs: $0.value) }
        }

        let total: Int64 = serverAnalytics?.total_secs
            ?? filtered.reduce(0) { $0 + $1.activeSecs }

        let streak: Int = {
            if let s = serverAnalytics { return Int(s.streak_days) }
            var days = Set<Date>()
            for e in allEntries {
                days.insert(cal.startOfDay(for: Date(timeIntervalSince1970: Double(e.startedAt))))
            }
            var streak = 0
            var cursor = cal.startOfDay(for: Date())
            while days.contains(cursor) {
                streak += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
            return streak
        }()

        // Switch to hours when peak day exceeds 2h to keep axis labels readable.
        let perDayTotals = dayCat.mapValues { $0.values.reduce(0, +) }
        let peakSecs = perDayTotals.values.max() ?? 0
        let useHours = peakSecs >= 7200

        let categoryOrder = byCategory.map(\.name)

        return AnalyticsAggregates(
            totalSecs: total,
            streakDays: streak,
            byDayCategory: slices,
            byCategory: byCategory,
            categoryOrder: categoryOrder,
            useHours: useHours
        )
    }
}

// MARK: - Stacked bar (extracted, equatable to avoid re-renders)

struct StackedBarChart: View, Equatable {
    let rows: [AnalyticsAggregates.DayCategorySlice]
    let useHours: Bool
    let categories: [String]

    var body: some View {
        let colorRange = categories.map { TL.categoryColor($0) }

        Chart(rows) { row in
            BarMark(
                x: .value("Day", row.day, unit: .day),
                y: .value(useHours ? "Hours" : "Minutes",
                          useHours ? Double(row.secs) / 3600.0 : Double(row.secs) / 60.0)
            )
            .foregroundStyle(by: .value("Category", row.category))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: categories, range: colorRange)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day(), centered: true)
                    .font(TL.TypeScale.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(useHours
                             ? String(format: "%.0fh", v)
                             : "\(Int(v))m")
                            .font(TL.TypeScale.caption2)
                    }
                }
            }
        }
    }

    static func == (lhs: StackedBarChart, rhs: StackedBarChart) -> Bool {
        lhs.useHours == rhs.useHours &&
        lhs.categories == rhs.categories &&
        lhs.rows == rhs.rows
    }
}

// MARK: - Donut chart with selection + center total

struct DonutChart: View {
    let slices: [AnalyticsAggregates.CategoryShare]
    let totalSecs: Int64
    @Binding var selected: String?

    @State private var selectionAngle: Double?

    var body: some View {
        let visible = Array(slices.prefix(7))

        Chart(visible) { slice in
            SectorMark(
                angle: .value("Time", Double(slice.secs)),
                innerRadius: .ratio(0.62),
                angularInset: 2
            )
            .foregroundStyle(TL.categoryColor(slice.name).gradient)
            .cornerRadius(4)
            .opacity(selected == nil || selected == slice.name ? 1.0 : 0.35)
        }
        .chartAngleSelection(value: $selectionAngle)
        .chartBackground { proxy in
            GeometryReader { geo in
                let frame = geo[proxy.plotAreaFrame]
                centerLabel(visible: visible)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .onChange(of: selectionAngle) { _, newValue in
            guard let value = newValue else { selected = nil; return }
            selected = sliceForAngle(value, in: visible)?.name
        }
    }

    @ViewBuilder
    private func centerLabel(visible: [AnalyticsAggregates.CategoryShare]) -> some View {
        if let name = selected,
           let slice = visible.first(where: { $0.name == name }) {
            VStack(spacing: 2) {
                CategoryChip(name: slice.name)
                Text(TL.clockShort(slice.secs))
                    .font(TL.TypeScale.mono(20, weight: .semibold))
                    .monospacedDigit()
                if totalSecs > 0 {
                    Text("\(Int(round(Double(slice.secs) / Double(totalSecs) * 100)))%")
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 2) {
                Text("TOTAL")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)
                Text(TL.clockShort(totalSecs))
                    .font(TL.TypeScale.mono(22, weight: .semibold))
                    .foregroundStyle(TL.Palette.emerald)
                    .monospacedDigit()
                Text("tap a slice")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sliceForAngle(_ angle: Double, in visible: [AnalyticsAggregates.CategoryShare]) -> AnalyticsAggregates.CategoryShare? {
        let total = visible.reduce(0.0) { $0 + Double($1.secs) }
        guard total > 0 else { return nil }
        var cumulative = 0.0
        let target = angle.truncatingRemainder(dividingBy: total)
        for slice in visible {
            cumulative += Double(slice.secs)
            if target <= cumulative { return slice }
        }
        return visible.last
    }
}
