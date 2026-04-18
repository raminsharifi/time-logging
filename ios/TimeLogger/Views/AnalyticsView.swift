import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \TimeEntryLocal.endedAt, order: .reverse)
    private var allEntries: [TimeEntryLocal]

    @State private var range: StatsRange = .week

    enum StatsRange: String, CaseIterable {
        case week = "7 D", month = "30 D", quarter = "90 D"
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }
    }

    private var dayBuckets: [(date: Date, secs: Int64, byCat: [(cat: String, secs: Int64)])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<range.days).map { i -> Date in
            cal.date(byAdding: .day, value: -(range.days - 1 - i), to: today)!
        }
        var bucketMap: [Date: [String: Int64]] = [:]
        for e in allEntries {
            let d = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(e.startedAt)))
            guard days.contains(d) else { continue }
            bucketMap[d, default: [:]][e.category, default: 0] += e.activeSecs
        }
        return days.map { d in
            let cats = bucketMap[d] ?? [:]
            let secs = cats.values.reduce(0, +)
            let sorted = cats.sorted { $0.value > $1.value }.map { (cat: $0.key, secs: $0.value) }
            return (date: d, secs: secs, byCat: sorted)
        }
    }

    private var totalSecs: Int64 { dayBuckets.reduce(0) { $0 + $1.secs } }
    private var maxDaySecs: Int64 { dayBuckets.map(\.secs).max() ?? 0 }
    private var activeDays: Int { dayBuckets.filter { $0.secs > 0 }.count }
    private var bestDay: Date? { dayBuckets.max { $0.secs < $1.secs }?.date }

    private var categoryTotals: [(cat: String, secs: Int64, pct: Double)] {
        var map: [String: Int64] = [:]
        for day in dayBuckets {
            for entry in day.byCat {
                map[entry.cat, default: 0] += entry.secs
            }
        }
        let total = max(totalSecs, 1)
        return map.sorted { $0.value > $1.value }.map {
            (cat: $0.key, secs: $0.value, pct: Double($0.value) / Double(total) * 100)
        }
    }

    private var focusPct: Int {
        let deepSecs = categoryTotals.first { $0.cat.lowercased().contains("deep") || $0.cat.lowercased() == "focus" || $0.cat.lowercased() == "general" }?.secs ?? 0
        return Int(round(Double(deepSecs) / Double(max(totalSecs, 1)) * 100))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    title: "Stats",
                    caption: tlStatusCaption(),
                    right: {
                        MonoLabel(range.rawValue, color: TL.Palette.ink)
                    }
                )

                VStack(alignment: .leading, spacing: 20) {
                    rangeRow.padding(.top, 16)
                    kpiGrid
                    dailyBreakdown
                    categorySection
                }
                .padding(.horizontal, TL.Space.l)
                .padding(.bottom, TL.Space.l)
            }
        }
        .background(TL.Palette.bg)
        .scrollContentBackground(.hidden)
    }

    private var rangeRow: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases, id: \.self) { r in
                FilterPill(label: r.rawValue, isSelected: range == r) {
                    range = r
                }
            }
            Spacer()
        }
    }

    // MARK: - KPI grid

    private var kpiGrid: some View {
        let cells: [(String, String, String)] = [
            ("Tracked",  TL.clockShort(totalSecs),           "\(range.days) days"),
            ("Daily avg", TL.clockShort(totalSecs / Int64(range.days)), "\(activeDays)/\(range.days) active"),
            ("Best day",  TL.clockShort(maxDaySecs),        bestDay.map(formatShortDate) ?? "—"),
            ("Focus %",   "\(focusPct)%",                    "Deep work"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(cell.0)
                    MonoNum(cell.1, size: 22, weight: .semibold, color: TL.Palette.ink)
                    MonoNum(cell.2, size: 9, color: TL.Palette.dim)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if idx % 2 == 1 {
                        Rectangle().fill(TL.Palette.line).frame(width: 1)
                    }
                }
                .overlay(alignment: .top) {
                    if idx >= 2 {
                        Rectangle().fill(TL.Palette.line).frame(height: 1)
                    }
                }
            }
        }
        .background(TL.Palette.surface)
        .overlay {
            Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
        }
    }

    // MARK: - Daily breakdown

    private var dailyBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel("Daily breakdown")
                Spacer()
                MonoLabel("Stacked · hrs", color: TL.Palette.dim)
            }
            VStack(spacing: 6) {
                barChart.frame(height: 140)
                xAxisLabels
            }
            .padding(12)
            .surface(padding: 0)
        }
    }

    private var barChart: some View {
        let maxSecs = max(maxDaySecs, 1)
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(dayBuckets.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            ForEach(day.byCat, id: \.cat) { slice in
                                let ratio = day.secs > 0 ? Double(slice.secs) / Double(day.secs) : 0
                                let h = geo.size.height * (Double(day.secs) / Double(maxSecs)) * ratio
                                Rectangle()
                                    .fill(TL.categoryColor(slice.cat))
                                    .frame(height: max(h, 0))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var xAxisLabels: some View {
        let step = max(1, range.days / 7)
        return HStack(spacing: 3) {
            ForEach(Array(dayBuckets.enumerated()), id: \.offset) { i, day in
                Text(i % step == 0 ? "\(Calendar.current.component(.day, from: day.date))" : "")
                    .font(TL.TypeScale.mono(9))
                    .foregroundStyle(TL.Palette.dim)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Category breakdown

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoLabel("By category")
                Spacer()
                MonoLabel("Share", color: TL.Palette.dim)
            }

            // 100% ratio bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(categoryTotals, id: \.cat) { c in
                        Rectangle()
                            .fill(TL.categoryColor(c.cat))
                            .frame(width: geo.size.width * c.pct / 100)
                    }
                }
            }
            .frame(height: 8)
            .overlay {
                Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
            }

            // Rows
            VStack(spacing: 0) {
                ForEach(categoryTotals, id: \.cat) { c in
                    categoryRow(c)
                }
                if categoryTotals.isEmpty {
                    MonoLabel("No entries in range", color: TL.Palette.dim)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ c: (cat: String, secs: Int64, pct: Double)) -> some View {
        HStack(spacing: 10) {
            Circle().fill(TL.categoryColor(c.cat)).frame(width: 6, height: 6)
            Text(c.cat)
                .font(.system(size: 13))
                .foregroundStyle(TL.Palette.ink)
            Spacer()
            MonoNum(String(format: "%.1f%%", c.pct), size: 11, color: TL.Palette.mute)
                .frame(width: 56, alignment: .trailing)
            MonoNum(TL.clockShort(c.secs), size: 12, weight: .semibold, color: TL.Palette.ink)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }

    private func formatShortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        return df.string(from: d)
    }
}
