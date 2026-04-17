import ActivityKit
import SwiftUI
import WidgetKit

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let tint = WidgetPalette.color(for: context.state.category)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Circle().fill(tint).frame(width: 10, height: 10)
                        Text(context.state.category)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: context.state.isRunning ? "play.fill" : "pause.fill")
                            .foregroundStyle(tint)
                        Text(context.state.isRunning ? "Running" : "Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Started \(context.state.startedAt, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Circle().fill(tint).frame(width: 10, height: 10)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Circle().fill(tint).frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(tint.opacity(0.4), lineWidth: 2)
                    )
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
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: state.isRunning ? 0.78 : 0.08)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [tint, tint.opacity(0.5), tint]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: state.isRunning ? "timer" : "pause")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.category)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
