import ActivityKit
import SwiftUI
import WidgetKit

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(WidgetTokens.bg)
                .activitySystemActionForegroundColor(WidgetTokens.ink)
        } dynamicIsland: { context in
            let tint = WidgetPalette.color(for: context.state.category)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Rectangle().fill(tint).frame(width: 5, height: 5)
                        Text(context.state.category.uppercased())
                            .font(WidgetTokens.label(9))
                            .tracking(1.2)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(WidgetTokens.mono(18, weight: .semibold))
                        .foregroundStyle(WidgetTokens.ink)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetTokens.ink)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.isRunning {
                            HStack(spacing: 4) {
                                Circle().fill(tint).frame(width: 4, height: 4)
                                Text("RUNNING")
                                    .font(WidgetTokens.label(8))
                                    .tracking(1.2)
                                    .foregroundStyle(tint)
                            }
                        } else {
                            Text("PAUSED")
                                .font(WidgetTokens.label(8))
                                .tracking(1.2)
                                .foregroundStyle(WidgetTokens.mute)
                        }
                        Spacer()
                        Text("Started \(context.state.startedAt, style: .time)")
                            .font(WidgetTokens.mono(9))
                            .foregroundStyle(WidgetTokens.dim)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Rectangle().fill(tint).frame(width: 6, height: 6)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .font(WidgetTokens.mono(11, weight: .semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                ZStack {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
            }
            .keylineTint(tint)
        }
    }
}

private struct LockScreenView: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        let tint = WidgetPalette.color(for: state.category)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Rectangle().fill(tint).frame(width: 6, height: 6)
                    Text(state.category.uppercased())
                        .font(WidgetTokens.label(9))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                }
                Text(state.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTokens.ink)
                    .lineLimit(1)
                Text(state.isRunning ? "RUNNING" : "PAUSED")
                    .font(WidgetTokens.label(8))
                    .tracking(1.2)
                    .foregroundStyle(state.isRunning ? tint : WidgetTokens.mute)
            }
            Spacer()
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .font(WidgetTokens.mono(26, weight: .semibold))
                .foregroundStyle(WidgetTokens.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
