import SwiftUI
import SwiftData
import Charts

struct LogSummaryView: View {
    let syncEngine: SyncEngine

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeEntryLocal.endedAt, order: .reverse) private var allEntries: [TimeEntryLocal]

    private var todayEntries: [TimeEntryLocal] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return allEntries.filter { $0.endedAt >= startOfDay }
    }

    private var weekEntries: [TimeEntryLocal] {
        let weekAgo = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        return allEntries.filter { $0.endedAt >= weekAgo }
    }

    private var totalToday: Int64 {
        Int64(todayEntries.reduce(0) { $0 + $1.activeSecs })
    }

    private var totalWeek: Int64 {
        Int64(weekEntries.reduce(0) { $0 + $1.activeSecs })
    }

    /// [(category, total secs)] sorted by total desc.
    private var categoryTotals: [(String, Int64)] {
        var acc: [String: Int64] = [:]
        for e in weekEntries {
            acc[e.category, default: 0] += Int64(e.activeSecs)
        }
        return acc.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TL.Space.m) {
                header

                totalsRow

                if !categoryTotals.isEmpty {
                    byCategoryChart
                }

                recentList
            }
            .padding(.horizontal, TL.Space.s)
            .padding(.vertical, TL.Space.s)
        }
    }

    private var header: some View {
        HStack {
            Text("Log")
                .font(TL.TypeScale.title2)
            Spacer()
        }
    }

    private var totalsRow: some View {
        HStack(spacing: TL.Space.s) {
            totalCard("Today", secs: totalToday, tint: TL.Palette.citrine)
            totalCard("7 days", secs: totalWeek, tint: TL.Palette.iris)
        }
    }

    private func totalCard(_ title: String, secs: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)
            Text(TL.clockShort(secs))
                .font(TL.TypeScale.mono(18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    @ViewBuilder
    private var byCategoryChart: some View {
        let visible = Array(categoryTotals.prefix(4))
        VStack(alignment: .leading, spacing: 4) {
            Text("BY CATEGORY (7D)")
                .font(TL.TypeScale.caption2)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(visible, id: \.0) { cat, secs in
                    BarMark(
                        x: .value("Time", Double(secs) / 60),
                        y: .value("Category", cat)
                    )
                    .foregroundStyle(TL.categoryColor(cat).gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text(TL.clockShort(secs))
                            .font(TL.TypeScale.caption2)
                            .foregroundStyle(.primary.opacity(0.85))
                            .monospacedDigit()
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(TL.TypeScale.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: CGFloat(visible.count) * 24 + 8)
        }
        .glassCard(tint: TL.Palette.iris, cornerRadius: TL.Radius.m, padding: TL.Space.s)
    }

    @ViewBuilder
    private var recentList: some View {
        if todayEntries.isEmpty {
            Text("No entries today")
                .font(TL.TypeScale.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, TL.Space.s)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY")
                    .font(TL.TypeScale.caption2)
                    .foregroundStyle(.secondary)

                ForEach(todayEntries.prefix(8), id: \.localId) { entry in
                    HStack {
                        Circle()
                            .fill(TL.categoryColor(entry.category).gradient)
                            .frame(width: 6, height: 6)
                        Text(entry.name)
                            .font(TL.TypeScale.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(TL.clockShort(Int64(entry.activeSecs)))
                            .font(TL.TypeScale.mono(11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 4)
        }
    }
}
