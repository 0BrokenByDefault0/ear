import SwiftUI
import EARKit

/// EAR's nocturne palette. Dark by design: the app is used beside a DAW, often late, often in a dim room.
enum Ink {
    static let background = Color(red: 0.018, green: 0.025, blue: 0.04)
    static let surface = Color(red: 0.045, green: 0.06, blue: 0.082)
    static let raised = Color(red: 0.07, green: 0.088, blue: 0.115)
    static let primary = Color(red: 0.91, green: 0.93, blue: 0.96)
    static let secondary = Color(red: 0.66, green: 0.71, blue: 0.77)
    static let accent = Color(red: 0.66, green: 0.85, blue: 0.91)
    static let glow = Color(red: 0.42, green: 0.68, blue: 0.86)
    static let warm = Color(red: 0.96, green: 0.76, blue: 0.47)
    static let alert = Color(red: 0.98, green: 0.52, blue: 0.47)
    static let line = Color.white.opacity(0.10)

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("AeonNocturne-Regular", size: size, relativeTo: style)
    }
    static let number = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
    static let mono = Font.system(.caption, design: .monospaced)
}

struct EarErrorAlert: ViewModifier {
    @Environment(EarStore.self) private var store
    var active = true
    func body(content: Content) -> some View {
        content.alert("EAR", isPresented: Binding(get: { active && store.error != nil }, set: { if !$0 && active { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct Eyebrow: View {
    let text: String
    var color = Ink.secondary
    init(_ text: String, color: Color = Ink.secondary) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.system(.caption2, design: .monospaced)).tracking(1.8).foregroundStyle(color)
    }
}

struct Rule: View {
    var body: some View { Rectangle().fill(Ink.line).frame(height: 0.5).accessibilityHidden(true) }
}

/// A quiet raised surface with a hairline edge.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ink.line, lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 22) -> some View { modifier(CardStyle(padding: padding, radius: radius)) }

    /// Standard page frame: readable width on iPad, consistent gutters on iPhone.
    func page(maxWidth: CGFloat = 720) -> some View {
        padding(.horizontal, 22).padding(.bottom, 28).frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

/// Section header used throughout the study and lab.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(title)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Ink.secondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// A compact capsule of facts: "96 BPM", "C major · 8B".
struct Chip: View {
    let text: String
    var symbol: String?
    var tint = Ink.secondary
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.system(.caption2, design: .monospaced).weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
    }
}

/// One figure in the at-a-glance grid.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String?
    var detail: String?
    var tint = Ink.primary
    var symbol: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(Ink.accent) }
                Eyebrow(label)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Ink.number).foregroundStyle(tint).minimumScaleFactor(0.7).lineLimit(1)
                if let unit { Text(unit).font(.caption).foregroundStyle(Ink.secondary) }
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(Ink.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .card(padding: 14, radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(unit ?? "")\(detail.map { ", \($0)" } ?? "")")
    }
}

struct LensRow: View {
    let lens: Lens
    let title: String
    var detail: String?
    var done = false
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: lens.symbol)
                .font(.system(size: 18, weight: .light)).foregroundStyle(Ink.accent)
                .frame(width: 40, height: 40).background(Ink.accent.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(lens.rawValue)
                Text(title).font(.body).foregroundStyle(Ink.primary).multilineTextAlignment(.leading)
                if let detail { Text(detail).font(.caption).foregroundStyle(Ink.secondary) }
            }
            Spacer(minLength: 4)
            if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.accent).accessibilityLabel("Experiment tried") }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.secondary)
        }
        .padding(.vertical, 12).frame(minHeight: 64).contentShape(Rectangle())
    }
}

/// Soft background atmosphere behind hero areas.
struct Atmosphere: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Ink.glow.opacity(0.20), .clear], center: .init(x: 0.85, y: 0.0), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Ink.accent.opacity(0.08), .clear], center: .init(x: 0.0, y: 0.35), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension Study {
    /// Short facts for list rows and cards.
    var chips: [String] {
        var values: [String] = []
        if let tempo { values.append("\(decimal(tempo, 0)) BPM") }
        if let key = metrics.key { values.append(key.shortName) }
        if let lufs = metrics.integratedLoudness { values.append("\(decimal(lufs, 1)) LUFS") }
        values.append(clock(metrics.duration))
        return values
    }
}
