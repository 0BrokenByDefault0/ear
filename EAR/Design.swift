import SwiftUI

enum Ink {
    static let background = Color(red: 0.018, green: 0.025, blue: 0.04)
    static let surface = Color(red: 0.041, green: 0.055, blue: 0.075)
    static let primary = Color(red: 0.91, green: 0.93, blue: 0.96)
    static let secondary = Color(red: 0.66, green: 0.71, blue: 0.77)
    static let accent = Color(red: 0.66, green: 0.85, blue: 0.91)
    static let line = Color.white.opacity(0.12)
    static func display(_ size: CGFloat) -> Font { .custom("AeonNocturne-Regular", size: size, relativeTo: .largeTitle) }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.system(.caption2, design: .monospaced)).tracking(2).foregroundStyle(Ink.secondary) }
}

struct Rule: View {
    var body: some View { Rectangle().fill(Ink.line).frame(height: 0.5).accessibilityHidden(true) }
}

struct Orbit: View {
    var animate = true
    var amplitude = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || !animate)) { timeline in
            let phase = reduceMotion || !animate ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.15
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width * 0.35, size.height * 0.40)
                let halo = CGRect(x: center.x - radius * 1.3, y: center.y - radius * 1.3, width: radius * 2.6, height: radius * 2.6)
                context.fill(Path(ellipseIn: halo), with: .radialGradient(Gradient(colors: [Ink.accent.opacity(0.12), .clear]), center: center, startRadius: 0, endRadius: radius * 1.3))
                for j in 0..<6 {
                    var path = Path()
                    for i in 0...240 {
                        let angle = Double(i) / 240 * .pi * 2
                        let modulation = sin(angle * 7 + phase + Double(j) * 0.65) * (3 + amplitude * 12)
                        let r = radius + Double(j - 3) * 5 + modulation
                        let x = center.x + cos(angle) * r
                        let y = center.y + sin(angle) * r * (0.74 + Double(j) * 0.025)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(Ink.accent.opacity(j == 3 ? 0.75 : 0.15 + Double(j) * 0.03)), lineWidth: j == 3 ? 1.2 : 0.6)
                }
                var wave = Path()
                for i in 0...180 {
                    let x = Double(i) / 180
                    let envelope = pow(sin(x * .pi), 5)
                    let y = sin(x * 77 + phase * 4) * envelope * (20 + amplitude * 28)
                    let point = CGPoint(x: center.x - radius * 0.73 + x * radius * 1.46, y: center.y + y)
                    if i == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
                }
                context.stroke(wave, with: .color(Ink.primary.opacity(0.9)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                for i in 0..<22 {
                    let x = Double((i * 97 + 13) % 347) / 347 * size.width
                    let y = Double((i * 71 + 37) % 233) / 233 * size.height
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: i % 4 == 0 ? 1.6 : 0.8, height: i % 4 == 0 ? 1.6 : 0.8)), with: .color(Ink.primary.opacity(0.18)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct Waveform: View {
    var values: [Double]
    var progress: Double
    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let count = min(values.count, max(1, Int(size.width / 3)))
            for i in 0..<count {
                let value = values[min(values.count - 1, i * values.count / count)]
                let height = max(2, pow(value, 0.65) * size.height)
                let x = Double(i) / Double(count) * size.width
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: 1.5, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Double(i) / Double(count) <= progress ? Ink.accent : Ink.primary.opacity(0.22)))
            }
        }.accessibilityHidden(true)
    }
}

struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(.system(.title3, design: .monospaced)).foregroundStyle(Ink.primary)
            Text(label).font(.caption).foregroundStyle(Ink.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LensRow: View {
    let lens: Lens
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: lens.symbol).font(.system(size: 19, weight: .light)).foregroundStyle(Ink.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(lens.rawValue.uppercased()).font(.system(.caption2, design: .monospaced)).tracking(1.3).foregroundStyle(Ink.secondary)
                Text(title).font(.body).foregroundStyle(Ink.primary).multilineTextAlignment(.leading)
                if let detail { Text(detail).font(.caption).foregroundStyle(Ink.secondary) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.secondary)
        }.padding(.vertical, 17).frame(minHeight: 70).contentShape(Rectangle())
    }
}
