import SwiftUI
import Charts

// MARK: - API models (server /analytics)

struct APIDayBucketMac: Codable, Hashable {
    let date: String
    let secs: Int64
}

struct APICategoryBucketMac: Codable, Hashable {
    let name: String
    let secs: Int64
    let color: String
}

struct APIAnalyticsResponseMac: Codable {
    let range: String
    let total_secs: Int64
    let by_day: [APIDayBucketMac]
    let by_category: [APICategoryBucketMac]
    let streak_days: Int64
}

extension APIClient {
    func getAnalytics(range: String) async throws -> APIAnalyticsResponseMac {
        let url = URL(string: "http://127.0.0.1:9746/api/v1/analytics?range=\(range)")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(APIAnalyticsResponseMac.self, from: data)
    }
}

struct AnalyticsView: View {
    @EnvironmentObject var api: APIClient
    @State private var range: AnalyticsRange = .week
    @State private var data: APIAnalyticsResponseMac?
    @State private var aggregates = AnalyticsMacAggregates()
    @State private var loadState: LoadState = .idle
    @State private var hoveredDay: Date?
    @State private var selectedCategory: String?

    enum AnalyticsRange: String, CaseIterable {
        case week = "Week", month = "Month"
        var apiName: String { self == .week ? "week" : "month" }
        var days: Int { self == .week ? 7 : 30 }
    }

    enum LoadState { case idle, loading, ready, empty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.m) {
                rangeToggle

                HStack(spacing: TL.Space.m) {
                    totalCard
                    streakCard
                }

                barCard
                donutCard
                topCategoriesCard
            }
            .padding(TL.Space.l)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .task(id: range) { await loadData() }
    }

    @ViewBuilder
    private var rangeToggle: some View {
        HStack(spacing: 6) {
            ForEach(AnalyticsRange.allCases, id: \.self) { r in
                Button {
                    range = r
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

    @ViewBuilder
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOTAL")
                .font(TL.TypeScale.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatDuration(aggregates.totalSecs))
                .font(TL.TypeScale.mono(30, weight: .semibold))
                .foregroundStyle(TL.Palette.iris)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("over \(range.days) days")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    @ViewBuilder
    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STREAK")
                .font(TL.TypeScale.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(aggregates.streakDays)")
                    .font(TL.TypeScale.mono(30, weight: .semibold))
                    .foregroundStyle(TL.Palette.ember)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(aggregates.streakDays == 1 ? "day" : "days")
                    .font(TL.TypeScale.callout)
                    .foregroundStyle(.secondary)
                Image(systemName: "flame.fill")
                    .foregroundStyle(TL.Palette.ember)
            }
            Text("consecutive")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.ember, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    @ViewBuilder
    private var barCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DAILY BREAKDOWN")
                    .font(TL.TypeScale.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(aggregates.useHours ? "hours" : "minutes")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            }

            chartContent {
                DailyBarChart(
                    rows: aggregates.dailyRows,
                    useHours: aggregates.useHours,
                    categories: aggregates.categoryOrder,
                    hovered: $hoveredDay
                )
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.sky, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    @ViewBuilder
    private var donutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY SHARE")
                .font(TL.TypeScale.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            chartContent {
                DonutChartMac(
                    slices: aggregates.byCategory,
                    totalSecs: aggregates.totalSecs,
                    selected: $selectedCategory
                )
                .frame(height: 240)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.emerald, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    @ViewBuilder
    private var topCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP CATEGORIES")
                .font(TL.TypeScale.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if aggregates.byCategory.isEmpty {
                Text("No data yet")
                    .font(TL.TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TL.Space.l)
            } else {
                ForEach(aggregates.byCategory.prefix(6), id: \.name) { c in
                    let isSelected = selectedCategory == c.name
                    HStack {
                        Circle()
                            .fill(TL.categoryColor(c.name).gradient)
                            .frame(width: 10, height: 10)
                        Text(c.name)
                            .font(TL.TypeScale.body)
                            .foregroundStyle(.primary)
                            .opacity(isSelected || selectedCategory == nil ? 1 : 0.55)
                        Spacer()
                        if aggregates.totalSecs > 0 {
                            Text("\(Int(round(Double(c.secs) / Double(aggregates.totalSecs) * 100)))%")
                                .font(TL.TypeScale.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        Text(formatDuration(c.secs))
                            .font(TL.TypeScale.mono(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCategory = isSelected ? nil : c.name
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: TL.Palette.citrine, cornerRadius: TL.Radius.l, padding: TL.Space.m)
    }

    @ViewBuilder
    private func chartContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if loadState == .loading && aggregates.totalSecs == 0 {
            HStack { Spacer(); ProgressView(); Spacer() }
                .frame(height: 80)
        } else if aggregates.totalSecs == 0 {
            Text("No data yet")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TL.Space.l)
        } else {
            content()
        }
    }

    private func loadData() async {
        loadState = .loading
        data = try? await api.getAnalytics(range: range.apiName)
        aggregates = AnalyticsMacAggregates.compute(range: range, response: data)
        loadState = aggregates.totalSecs == 0 ? .empty : .ready
    }
}

// MARK: - Aggregates (memoized; equatable)

struct AnalyticsMacAggregates: Equatable {
    var totalSecs: Int64 = 0
    var streakDays: Int = 0
    var dailyRows: [DailyRow] = []
    var byCategory: [CategoryShare] = []
    var categoryOrder: [String] = []
    var useHours: Bool = false

    struct DailyRow: Identifiable, Hashable {
        let id: Date
        let day: Date
        let dominantCategory: String
        let secs: Int64
    }

    struct CategoryShare: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let secs: Int64
    }

    static func compute(range: AnalyticsView.AnalyticsRange,
                        response: APIAnalyticsResponseMac?) -> AnalyticsMacAggregates {
        guard let response else { return AnalyticsMacAggregates() }

        let cats = response.by_category.sorted { $0.secs > $1.secs }
        let topCategoryName = cats.first?.name ?? "General"

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        let rows: [DailyRow] = response.by_day.compactMap { b in
            guard let d = fmt.date(from: b.date) else { return nil }
            return DailyRow(id: d, day: d, dominantCategory: topCategoryName, secs: b.secs)
        }

        let peak = rows.map(\.secs).max() ?? 0
        let useHours = peak >= 7200

        return AnalyticsMacAggregates(
            totalSecs: response.total_secs,
            streakDays: Int(response.streak_days),
            dailyRows: rows,
            byCategory: cats.map { CategoryShare(name: $0.name, secs: $0.secs) },
            categoryOrder: cats.map(\.name),
            useHours: useHours
        )
    }
}

// MARK: - Daily bar (colored by dominant category)

struct DailyBarChart: View, Equatable {
    let rows: [AnalyticsMacAggregates.DailyRow]
    let useHours: Bool
    let categories: [String]
    @Binding var hovered: Date?

    var body: some View {
        let colorRange = categories.map { TL.categoryColor($0) }

        Chart(rows) { row in
            BarMark(
                x: .value("Day", row.day, unit: .day),
                y: .value(useHours ? "Hours" : "Minutes",
                          useHours ? Double(row.secs) / 3600.0 : Double(row.secs) / 60.0)
            )
            .foregroundStyle(by: .value("Top category", row.dominantCategory))
            .cornerRadius(4)
            .opacity(hovered == nil || hovered == row.day ? 1.0 : 0.4)
            .annotation(position: .top, alignment: .center, spacing: 4) {
                if hovered == row.day {
                    Text(formatDuration(row.secs))
                        .font(TL.TypeScale.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .chartForegroundStyleScale(domain: categories, range: colorRange)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, rows.count / 10))) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .font(TL.TypeScale.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(useHours ? String(format: "%.0fh", v) : "\(Int(v))m")
                            .font(TL.TypeScale.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let frame = geo[plotFrame]
                            let x = pt.x - frame.origin.x
                            if let day: Date = proxy.value(atX: x) {
                                hovered = Calendar.current.startOfDay(for: day)
                            }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }

    static func == (lhs: DailyBarChart, rhs: DailyBarChart) -> Bool {
        lhs.useHours == rhs.useHours &&
        lhs.categories == rhs.categories &&
        lhs.rows == rhs.rows &&
        lhs.hovered == rhs.hovered
    }
}

// MARK: - Donut with selection + center total

struct DonutChartMac: View {
    let slices: [AnalyticsMacAggregates.CategoryShare]
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
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]
                    centerLabel(visible: visible)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .onChange(of: selectionAngle) { _, newValue in
            guard let v = newValue else { selected = nil; return }
            selected = sliceForAngle(v, in: visible)?.name
        }
    }

    @ViewBuilder
    private func centerLabel(visible: [AnalyticsMacAggregates.CategoryShare]) -> some View {
        if let name = selected,
           let slice = visible.first(where: { $0.name == name }) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(TL.categoryColor(slice.name).gradient)
                        .frame(width: 8, height: 8)
                    Text(slice.name)
                        .font(TL.TypeScale.caption.weight(.semibold))
                }
                Text(formatDuration(slice.secs))
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
                Text(formatDuration(totalSecs))
                    .font(TL.TypeScale.mono(22, weight: .semibold))
                    .foregroundStyle(TL.Palette.emerald)
                    .monospacedDigit()
                Text("click a slice")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sliceForAngle(_ angle: Double, in visible: [AnalyticsMacAggregates.CategoryShare]) -> AnalyticsMacAggregates.CategoryShare? {
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
