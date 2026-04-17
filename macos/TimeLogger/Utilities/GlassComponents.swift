import SwiftUI

// MARK: - Glass card modifier

struct GlassCardModifier: ViewModifier {
    var tint: Color = .clear
    var cornerRadius: CGFloat = TL.Radius.l
    var padding: CGFloat = TL.Space.l
    var strokeOpacity: Double = 0.12
    var elevation: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.22), tint.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(strokeOpacity * 2),
                                        Color.white.opacity(strokeOpacity * 0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(color: tint.opacity(0.25), radius: elevation, x: 0, y: elevation / 2)
            }
    }
}

extension View {
    func glassCard(
        tint: Color = .clear,
        cornerRadius: CGFloat = TL.Radius.l,
        padding: CGFloat = TL.Space.l,
        elevation: CGFloat = 8
    ) -> some View {
        modifier(GlassCardModifier(
            tint: tint,
            cornerRadius: cornerRadius,
            padding: padding,
            elevation: elevation
        ))
    }
}

// MARK: - Glass button style

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TL.TypeScale.headline)
            .padding(.vertical, TL.Space.s + 2)
            .padding(.horizontal, TL.Space.l)
            .foregroundStyle(prominent ? Color.white : tint)
            .background {
                Capsule()
                    .fill(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(prominent ? 0.25 : 0.18),
                                lineWidth: 0.8
                            )
                    }
                    .overlay {
                        if !prominent {
                            Capsule().fill(tint.opacity(0.08))
                        }
                    }
                    .shadow(color: tint.opacity(prominent ? 0.35 : 0), radius: 8, x: 0, y: 3)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(TL.Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glass(tint: Color = .accentColor, prominent: Bool = false) -> GlassButtonStyle {
        GlassButtonStyle(tint: tint, prominent: prominent)
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    let name: String
    var compact: Bool = false

    var body: some View {
        let tint = TL.categoryColor(name)
        HStack(spacing: TL.Space.xs) {
            Circle()
                .fill(tint.gradient)
                .frame(width: 6, height: 6)
            Text(name.isEmpty ? "—" : name)
                .font(compact ? TL.TypeScale.caption2 : TL.TypeScale.caption)
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background {
            Capsule().fill(tint.opacity(0.16))
        }
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.6)
        }
    }
}

// MARK: - RingProgress

/// Circular gradient ring. Pass `progress` 0…1 (or nil for an indeterminate/full ring).
/// Used as the hero across all three platforms.
struct RingProgress<Content: View>: View {
    var progress: Double? = nil
    var tint: Color = TL.Palette.sky
    var lineWidth: CGFloat = 14
    var glow: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: progress.map { max(0.001, min(1, $0)) } ?? 1)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.35), tint, tint.opacity(0.8), tint.opacity(0.35)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? tint.opacity(0.55) : .clear, radius: 12)

            content()
                .padding(lineWidth * 1.3)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Animated mesh background (iOS 18+/macOS 15+/watchOS 11+)

/// Breathing mesh gradient anchored to a tint color. Falls back to a plain radial
/// gradient on older OS versions.
struct AnimatedMesh: View {
    var tint: Color = TL.Palette.sky
    var animated: Bool = true

    var body: some View {
        RadialGradient(
            colors: [tint.opacity(0.45), tint.opacity(0.05), .clear],
            center: .topLeading,
            startRadius: 20,
            endRadius: 600
        )
    }
}

// MARK: - Transport badge (BLE / Wi-Fi / iCloud / Offline)

struct TransportBadge: View {
    enum Kind { case ble, wifi, cloud, offline }
    var kind: Kind
    var detail: String?

    var body: some View {
        let (icon, label, color): (String, String, Color) = switch kind {
            case .ble:     ("dot.radiowaves.left.and.right", "BLE",     TL.Palette.sky)
            case .wifi:    ("wifi",                           "Wi-Fi",  TL.Palette.emerald)
            case .cloud:   ("icloud.fill",                    "iCloud", TL.Palette.iris)
            case .offline: ("wifi.slash",                     "Offline",TL.Palette.ember)
        }
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
            Text(detail.map { "\(label) · \($0)" } ?? label)
                .font(TL.TypeScale.caption2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(color.opacity(0.15))
        }
        .overlay {
            Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.6)
        }
    }
}

// MARK: - Pulsing dot (for "LIVE / running" status)

struct PulsingDot: View {
    var color: Color = TL.Palette.ember

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            let eased = 0.5 - 0.5 * cos(phase * 2 * .pi)
            let scale = 1 + eased * 1.4
            ZStack {
                Circle()
                    .fill(color.opacity(0.35 * (1 - eased * 0.7)))
                    .frame(width: 16, height: 16)
                    .scaleEffect(scale)
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            .drawingGroup()
        }
        .frame(width: 24, height: 24)
    }
}
