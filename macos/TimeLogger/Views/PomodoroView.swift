import SwiftUI
import UserNotifications

enum PomodoroMode: String, CaseIterable {
    case focus = "Focus"
    case short = "Short Break"
    case long  = "Long Break"

    var defaultMinutes: Int {
        switch self {
        case .focus: 25
        case .short: 5
        case .long: 15
        }
    }

    var tint: Color {
        switch self {
        case .focus: TL.Palette.ember
        case .short: TL.Palette.emerald
        case .long:  TL.Palette.iris
        }
    }

    var icon: String {
        switch self {
        case .focus: "flame.fill"
        case .short: "leaf.fill"
        case .long:  "moon.fill"
        }
    }
}

struct PomodoroView: View {
    @State private var mode: PomodoroMode = .focus
    @State private var duration: Int = 25
    @State private var endDate: Date?
    @State private var roundsCompleted: Int = 0

    private var totalSecs: Int { duration * 60 }
    private var isRunning: Bool { endDate != nil }

    private func remaining(at now: Date) -> Int {
        guard let end = endDate else { return totalSecs }
        return max(0, Int(end.timeIntervalSince(now).rounded()))
    }

    private func progress(at now: Date) -> Double {
        guard totalSecs > 0 else { return 0 }
        return 1.0 - Double(remaining(at: now)) / Double(totalSecs)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isRunning ? 1 : 60)) { context in
            let now = context.date
            let rem = remaining(at: now)
            let prog = progress(at: now)

            ScrollView {
                VStack(spacing: TL.Space.l) {
                    modeSelector
                        .padding(.top, TL.Space.m)

                    ringHero(remaining: rem, progress: prog)
                        .padding(.vertical, TL.Space.m)

                    roundDots

                    if !isRunning {
                        presetRow
                        startButton
                    } else {
                        cancelButton
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, TL.Space.l)
                .padding(.bottom, TL.Space.l)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: rem) { _, newValue in
                if isRunning && newValue == 0 { finishPomodoro() }
            }
        }
        .onChange(of: mode) { _, newMode in
            if !isRunning {
                duration = newMode.defaultMinutes
            }
        }
        .onDisappear { cancelPomodoro() }
    }

    @ViewBuilder
    private var modeSelector: some View {
        HStack(spacing: TL.Space.s) {
            ForEach(PomodoroMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                        Text(m.rawValue)
                    }
                    .font(TL.TypeScale.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(mode == m ? .white : .primary.opacity(0.75))
                    .background {
                        if mode == m {
                            Capsule().fill(m.tint.gradient)
                        } else {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
        }
    }

    @ViewBuilder
    private func ringHero(remaining: Int, progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(mode.tint.opacity(0.15), lineWidth: 14)
                .padding(7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [mode.tint, mode.tint.opacity(0.5), mode.tint]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(7)
                .shadow(color: mode.tint.opacity(0.4), radius: 16)

            VStack(spacing: 6) {
                let mins = remaining / 60
                let secs = remaining % 60
                Text(String(format: "%02d:%02d", mins, secs))
                    .font(TL.TypeScale.mono(56, weight: .semibold))
                    .foregroundStyle(mode.tint)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(mode.rawValue.uppercased())
                    .font(TL.TypeScale.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, height: 280)
    }

    @ViewBuilder
    private var roundDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < roundsCompleted ? mode.tint : Color.primary.opacity(0.15))
                    .frame(width: 10, height: 10)
            }
        }
    }

    @ViewBuilder
    private var presetRow: some View {
        HStack(spacing: TL.Space.s) {
            ForEach([5, 15, 25, 30, 45, 60], id: \.self) { m in
                Button("\(m)m") {
                    duration = m
                }
                .buttonStyle(.bordered)
                .tint(duration == m ? mode.tint : .secondary)
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        Button {
            startPomodoro()
        } label: {
            Label("Start \(mode.rawValue)", systemImage: "play.fill")
                .frame(minWidth: 180)
        }
        .buttonStyle(.borderedProminent)
        .tint(mode.tint)
        .controlSize(.extraLarge)
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button(role: .destructive) {
            cancelPomodoro()
        } label: {
            Label("Cancel", systemImage: "xmark")
                .frame(minWidth: 180)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func startPomodoro() {
        endDate = Date().addingTimeInterval(TimeInterval(totalSecs))
    }

    private func finishPomodoro() {
        endDate = nil
        if mode == .focus {
            roundsCompleted = (roundsCompleted + 1) % 5
        }
        sendNotification()
    }

    private func cancelPomodoro() {
        endDate = nil
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "\(mode.rawValue) complete"
        content.body = "\(duration) minute \(mode.rawValue.lowercased()) finished."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
