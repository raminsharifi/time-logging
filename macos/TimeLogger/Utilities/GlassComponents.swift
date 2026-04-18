import SwiftUI

/// Shared transport enum (Mac doesn't have the iOS SyncEngine, so it's defined
/// here for cross-platform parity).
enum SyncTransport: String {
    case ble = "BLE", wifi = "Wi-Fi", icloud = "iCloud", offline = "Offline"
}

// MARK: - Surface (flat dark card)

/// Flat surface with 1pt line border and tight corner radius.
/// Replaces the blurred glass look with a grid-aligned, high-contrast surface.
struct SurfaceModifier: ViewModifier {
    var tint: Color = .clear
    var cornerRadius: CGFloat = TL.Radius.l
    var padding: CGFloat = TL.Space.l
    var border: Color = TL.Palette.line
    var background: Color = TL.Palette.surface
    var borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint == .clear ? border : tint.opacity(0.35),
                                  lineWidth: borderWidth)
            }
    }
}

extension View {
    /// Apply the flat-surface card style. `tint` optionally colors the border.
    func surface(
        tint: Color = .clear,
        cornerRadius: CGFloat = TL.Radius.l,
        padding: CGFloat = TL.Space.l,
        background: Color = TL.Palette.surface
    ) -> some View {
        modifier(SurfaceModifier(
            tint: tint, cornerRadius: cornerRadius,
            padding: padding, background: background
        ))
    }

    /// Legacy API — kept so existing views keep compiling. Now renders as a
    /// flat surface instead of a glass blur.
    func glassCard(
        tint: Color = .clear,
        cornerRadius: CGFloat = TL.Radius.l,
        padding: CGFloat = TL.Space.l,
        elevation: CGFloat = 8
    ) -> some View {
        _ = elevation
        return surface(tint: tint, cornerRadius: cornerRadius, padding: padding)
    }
}

// MARK: - Monospaced label (uppercase, tracked)

struct MonoLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = TL.Palette.mute

    init(_ text: String, size: CGFloat = 10, color: Color = TL.Palette.mute) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(TL.TypeScale.label(size))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

// MARK: - Tabular numeric

struct MonoNum: View {
    let text: String
    var size: CGFloat = 14
    var weight: Font.Weight = .medium
    var color: Color = TL.Palette.ink

    init(_ text: String, size: CGFloat = 14, weight: Font.Weight = .medium, color: Color = TL.Palette.ink) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(TL.TypeScale.mono(size, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

// MARK: - Category tag

/// Tiny uppercase, bordered tag colored by category hue.
struct CategoryTag: View {
    let name: String
    var compact: Bool = false

    var body: some View {
        let tint = TL.categoryColor(name)
        HStack(spacing: compact ? 4 : 6) {
            Circle()
                .fill(tint)
                .frame(width: compact ? 4 : 5, height: compact ? 4 : 5)
            Text(name.isEmpty ? "—" : name.uppercased())
                .font(TL.TypeScale.label(compact ? 9 : 10))
                .tracking(1.2)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background {
            RoundedRectangle(cornerRadius: TL.Radius.s, style: .continuous)
                .fill(tint.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: TL.Radius.s, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        }
    }
}

// Legacy alias so existing `CategoryChip` call sites keep compiling.
struct CategoryChip: View {
    let name: String
    var compact: Bool = false
    var body: some View { CategoryTag(name: name, compact: compact) }
}

// MARK: - Pulsing dot

/// Small dot with a radiating pulse aura. Used to signal "live/running".
struct PulsingDot: View {
    var color: Color = TL.Palette.accent
    var size: CGFloat = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.8) / 1.8
            let eased = 0.5 - 0.5 * cos(phase * 2 * .pi)
            let scale = 1 + eased * 1.8
            ZStack {
                Circle()
                    .fill(color.opacity(0.35 * (1 - eased * 0.7)))
                    .frame(width: size * 2.5, height: size * 2.5)
                    .scaleEffect(scale)
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
            .drawingGroup()
        }
        .frame(width: size * 2.5, height: size * 2.5)
    }
}

// MARK: - Buttons

/// Square-cornered, high-contrast button.
struct TLButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost, danger }
    var variant: Variant = .secondary
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg, border): (Color, Color, Color?) = {
            switch variant {
            case .primary:   return (TL.Palette.accent, TL.Palette.bg, nil)
            case .secondary: return (TL.Palette.raised, TL.Palette.ink, TL.Palette.line)
            case .ghost:     return (Color.clear,       TL.Palette.ink, TL.Palette.line)
            case .danger:    return (Color.clear,       TL.Palette.danger, TL.Palette.danger.opacity(0.4))
            }
        }()

        configuration.label
            .font(TL.TypeScale.label(12))
            .tracking(0.6)
            .foregroundStyle(fg)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, TL.Space.m)
            .padding(.horizontal, TL.Space.l)
            .background {
                RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous)
                    .fill(bg)
            }
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: TL.Radius.m, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(TL.Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TLButtonStyle {
    static func tl(_ variant: TLButtonStyle.Variant, fullWidth: Bool = false) -> TLButtonStyle {
        TLButtonStyle(variant: variant, fullWidth: fullWidth)
    }
}

/// Legacy `.glass(tint:prominent:)` — back-ends to the new `tl()` style so old
/// call sites keep rendering.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = TL.Palette.accent
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let variant: TLButtonStyle.Variant = prominent ? .primary : .secondary
        return configuration.label
            .modifier(LegacyButtonAdapter(variant: variant, isPressed: configuration.isPressed))
    }
}

private struct LegacyButtonAdapter: ViewModifier {
    var variant: TLButtonStyle.Variant
    var isPressed: Bool

    func body(content: Content) -> some View {
        let (bg, fg, border): (Color, Color, Color?) = {
            switch variant {
            case .primary:   return (TL.Palette.accent, TL.Palette.bg, nil)
            case .secondary: return (TL.Palette.raised, TL.Palette.ink, TL.Palette.line)
            case .ghost:     return (Color.clear,       TL.Palette.ink, TL.Palette.line)
            case .danger:    return (Color.clear,       TL.Palette.danger, TL.Palette.danger.opacity(0.4))
            }
        }()
        content
            .font(TL.TypeScale.label(12))
            .tracking(0.6)
            .foregroundStyle(fg)
            .padding(.vertical, TL.Space.m)
            .padding(.horizontal, TL.Space.l)
            .background {
                RoundedRectangle(cornerRadius: TL.Radius.m).fill(bg)
            }
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: TL.Radius.m).strokeBorder(border, lineWidth: 1)
                }
            }
            .scaleEffect(isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glass(tint: Color = TL.Palette.accent, prominent: Bool = false) -> GlassButtonStyle {
        GlassButtonStyle(tint: tint, prominent: prominent)
    }
}

// MARK: - Status strip (page header)

/// Large title with a mono caption above. Replaces the iOS NavigationBar.
struct StatusStrip<Right: View>: View {
    let title: String
    var caption: String
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(caption, size: 10, color: TL.Palette.dim)
                    .tracking(1.6)
                Text(title)
                    .font(TL.TypeScale.display)
                    .foregroundStyle(TL.Palette.ink)
                    .tracking(-1)
            }
            Spacer()
            right()
        }
        .padding(.horizontal, TL.Space.l)
        .padding(.top, TL.Space.xxl + TL.Space.l)
        .padding(.bottom, TL.Space.m + 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TL.Palette.line).frame(height: 1)
        }
    }
}

extension StatusStrip where Right == EmptyView {
    init(title: String, caption: String) {
        self.init(title: title, caption: caption, right: { EmptyView() })
    }
}

/// Default caption = "Weekday · Month Day · Wxx".
func tlStatusCaption(_ date: Date = Date()) -> String {
    let df = DateFormatter()
    df.dateFormat = "EEE MMM d"
    let iso = Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
    return "\(df.string(from: date)) · W\(iso)"
}

// MARK: - Filter pill

/// Monospace-label toggle pill, used in filter rows across the app.
struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(TL.TypeScale.label(10))
                .tracking(1.2)
                .foregroundStyle(isSelected ? TL.Palette.bg : TL.Palette.mute)
                .padding(.horizontal, TL.Space.m)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: TL.Radius.m)
                        .fill(isSelected ? TL.Palette.ink : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TL.Radius.m)
                        .strokeBorder(isSelected ? TL.Palette.ink : TL.Palette.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Horizon bar — 24h timeline

/// Horizontal 24h bar. Draws a segment per completed entry at its real time,
/// plus an optional "active now" overlay that grows in real time, with a
/// "now" marker. Hour gridlines every hour; thicker every 6h.
struct HorizonSegment: Identifiable {
    let id: String
    let startedAt: Int64
    let endedAt: Int64
    let category: String
}

struct HorizonBar: View {
    var entries: [HorizonSegment]
    var activeStartedAt: Int64?
    var activeCategory: String?
    var dayStart: Int64            // unix secs of 00:00 local
    var height: CGFloat = 56
    var showScale: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let dayLen: Double = 24 * 3600
                let nowTs = Date().timeIntervalSince1970
                let nowPct = max(0, min(1, (nowTs - Double(dayStart)) / dayLen))

                ZStack(alignment: .topLeading) {
                    // Base surface
                    Rectangle()
                        .fill(TL.Palette.surface)

                    // Elapsed-day tint
                    Rectangle()
                        .fill(Color.white.opacity(0.02))
                        .frame(width: geo.size.width * nowPct)

                    // Gridlines
                    ForEach(0..<25) { i in
                        let x = geo.size.width * CGFloat(Double(i) / 24.0)
                        let isMajor = i % 6 == 0
                        Rectangle()
                            .fill(isMajor ? TL.Palette.lineHi : TL.Palette.line)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .offset(x: x)
                            .opacity((i == 0 || i == 24) ? 0 : 1)
                    }

                    // Completed entries
                    ForEach(entries) { e in
                        let startPct = (Double(e.startedAt - dayStart)) / dayLen
                        let widthPct = (Double(e.endedAt - e.startedAt)) / dayLen
                        Rectangle()
                            .fill(TL.categoryColor(e.category))
                            .opacity(0.85)
                            .frame(
                                width: max(1, geo.size.width * CGFloat(widthPct)),
                                height: geo.size.height - 16
                            )
                            .offset(x: geo.size.width * CGFloat(startPct), y: 8)
                    }

                    // Active timer
                    if let start = activeStartedAt, let cat = activeCategory {
                        let startPct = Double(start - dayStart) / dayLen
                        let widthPct = max(0, (nowTs - Double(start)) / dayLen)
                        let color = TL.categoryColor(cat)
                        Rectangle()
                            .fill(color)
                            .frame(
                                width: max(1, geo.size.width * CGFloat(widthPct)),
                                height: geo.size.height - 8
                            )
                            .offset(x: geo.size.width * CGFloat(startPct), y: 4)
                            .shadow(color: color.opacity(0.6), radius: 8)
                    }

                    // Now marker
                    if activeStartedAt != nil {
                        Rectangle()
                            .fill(TL.Palette.ink)
                            .frame(width: 2, height: geo.size.height + 4)
                            .offset(x: geo.size.width * nowPct - 1, y: -2)
                            .shadow(color: TL.Palette.ink.opacity(0.8), radius: 6)
                        Circle()
                            .fill(TL.Palette.ink)
                            .frame(width: 10, height: 10)
                            .offset(x: geo.size.width * nowPct - 5, y: -5)
                            .shadow(color: TL.Palette.ink.opacity(0.6), radius: 6)
                    }
                }
            }
            .frame(height: height)
            .overlay {
                Rectangle().strokeBorder(TL.Palette.line, lineWidth: 1)
            }

            if showScale {
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hr in
                        Text(String(format: "%02d", hr))
                            .font(TL.TypeScale.mono(9))
                            .foregroundStyle(TL.Palette.dim)
                        if hr != 24 { Spacer() }
                    }
                }
            }
        }
    }
}

// MARK: - Transport badge (re-themed)

struct TransportBadge: View {
    enum Kind { case ble, wifi, cloud, offline }
    var kind: Kind
    var detail: String?

    init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }

    init(transport: SyncTransport, detail: String? = nil) {
        switch transport {
        case .ble:     self.kind = .ble
        case .wifi:    self.kind = .wifi
        case .icloud:  self.kind = .cloud
        case .offline: self.kind = .offline
        }
        self.detail = detail
    }

    var body: some View {
        let (icon, label, color): (String, String, Color) = switch kind {
            case .ble:     ("dot.radiowaves.left.and.right", "BLE",     TL.Palette.sky)
            case .wifi:    ("wifi",                           "WI-FI",  TL.Palette.accent)
            case .cloud:   ("icloud.fill",                    "ICLOUD", TL.Palette.violet)
            case .offline: ("wifi.slash",                     "OFFLINE",TL.Palette.mute)
        }
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(detail.map { "\(label) · \($0)" } ?? label)
                .font(TL.TypeScale.label(9))
                .tracking(1.2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: TL.Radius.s)
                .fill(color.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: TL.Radius.s)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - Ring progress (re-themed, muted accent only)

struct RingProgress<Content: View>: View {
    var progress: Double? = nil
    var tint: Color = TL.Palette.accent
    var lineWidth: CGFloat = 10
    var glow: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(TL.Palette.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.map { max(0.001, min(1, $0)) } ?? 1)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            content().padding(lineWidth * 1.3)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - AnimatedMesh (retired — returns an empty view so old callers layout correctly)

/// The animated mesh background has been removed in the flat redesign. Kept as
/// an empty passthrough so existing view hierarchies keep compiling until
/// their call sites are updated.
struct AnimatedMesh: View {
    var tint: Color = TL.Palette.accent
    var animated: Bool = true
    var body: some View { Color.clear }
}
