import SwiftUI
import EARKit

/// The listening "orbit": animated linework that breathes with the microphone level while capturing.
struct Orbit: View {
    var animate = true
    var amplitude = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !animate)) { timeline in
            let phase = reduceMotion || !animate ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.15
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width * 0.35, size.height * 0.40)
                let halo = CGRect(x: center.x - radius * 1.4, y: center.y - radius * 1.4, width: radius * 2.8, height: radius * 2.8)
                context.fill(Path(ellipseIn: halo), with: .radialGradient(
                    Gradient(colors: [Ink.glow.opacity(0.22 + amplitude * 0.2), .clear]),
                    center: center, startRadius: 0, endRadius: radius * 1.4))
                for j in 0..<7 {
                    var path = Path()
                    for i in 0...240 {
                        let angle = Double(i) / 240 * .pi * 2
                        let modulation = sin(angle * 7 + phase + Double(j) * 0.65) * (3 + amplitude * 14)
                        let r = radius + Double(j - 3) * 5 + modulation
                        let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r * (0.74 + Double(j) * 0.025))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(Ink.accent.opacity(j == 3 ? 0.8 : 0.12 + Double(j) * 0.03)), lineWidth: j == 3 ? 1.3 : 0.6)
                }
                var wave = Path()
                for i in 0...180 {
                    let x = Double(i) / 180
                    let envelope = pow(sin(x * .pi), 5)
                    let y = sin(x * 77 + phase * 4) * envelope * (20 + amplitude * 30)
                    let point = CGPoint(x: center.x - radius * 0.73 + x * radius * 1.46, y: center.y + y)
                    if i == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
                }
                context.stroke(wave, with: .color(Ink.primary.opacity(0.92)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                for i in 0..<26 {
                    let x = Double((i * 97 + 13) % 347) / 347 * size.width
                    let y = Double((i * 71 + 37) % 233) / 233 * size.height
                    let dot = i % 4 == 0 ? 1.6 : 0.8
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)), with: .color(Ink.primary.opacity(0.2)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Static waveform bars, used in lists and cards.
struct Waveform: View {
    var values: [Double]
    var progress: Double = 0
    var played = Ink.accent
    var unplayed = Ink.primary.opacity(0.22)
    var barWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let spacing = barWidth + 1.2
            let count = min(values.count, max(1, Int(size.width / spacing)))
            for i in 0..<count {
                let value = values[min(values.count - 1, i * values.count / count)]
                let height = max(2, pow(value, 0.65) * size.height)
                let x = Double(i) / Double(count) * size.width
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                let color = Double(i) / Double(count) < progress ? played : unplayed
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The study's main waveform: tap or drag to seek, with section markers and the active loop shaded.
struct WaveformScrubber: View {
    let study: Study
    let position: Double
    var loop: ClosedRange<Double>?
    var onSeek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        let duration = max(0.001, study.metrics.duration)
        let shown = dragging ?? position
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if let loop {
                    let x0 = loop.lowerBound / duration * width, x1 = loop.upperBound / duration * width
                    RoundedRectangle(cornerRadius: 6).fill(Ink.accent.opacity(0.12))
                        .frame(width: max(2, x1 - x0)).offset(x: x0)
                }
                Waveform(values: study.metrics.waveform, progress: shown / duration)
                ForEach(study.metrics.moments.dropFirst()) { moment in
                    Rectangle().fill(Ink.primary.opacity(0.18)).frame(width: 1)
                        .offset(x: moment.start / duration * width)
                }
                Capsule().fill(Ink.primary).frame(width: 2).shadow(color: Ink.accent.opacity(0.6), radius: 4)
                    .offset(x: min(width - 2, max(0, shown / duration * width - 1)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in dragging = min(duration, max(0, value.location.x / width * duration)) }
                .onEnded { value in
                    onSeek(min(duration, max(0, value.location.x / width * duration)))
                    dragging = nil
                })
        }
        .accessibilityElement()
        .accessibilityLabel("Waveform")
        .accessibilityValue("\(clock(shown)) of \(clock(duration))")
        .accessibilityAdjustableAction { direction in
            onSeek(min(duration, max(0, position + (direction == .increment ? 5 : -5))))
        }
    }
}

/// Third-octave spectrum as a smooth filled curve.
struct SpectrumCurve: View {
    let values: [Double]
    var floor = -48.0

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let points = values.enumerated().map { index, value in
                CGPoint(x: Double(index) / Double(values.count - 1) * size.width,
                        y: (1 - (max(floor, value) - floor) / -floor) * (size.height - 4) + 2)
            }
            var line = Path()
            line.move(to: points[0])
            for i in 1..<points.count {
                let previous = points[i - 1], point = points[i]
                let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                line.addQuadCurve(to: mid, control: previous)
                if i == points.count - 1 { line.addQuadCurve(to: point, control: point) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            for fraction in [0.25, 0.5, 0.75] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(grid, with: .color(Ink.line), lineWidth: 0.5)
            }
            context.fill(area, with: .linearGradient(Gradient(colors: [Ink.accent.opacity(0.35), Ink.accent.opacity(0.02)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(Ink.accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Short-term loudness across the track, with a reference line for the integrated value.
struct LoudnessTimeline: View {
    let values: [Double]
    let integrated: Double?
    var floor = -40.0
    var ceiling = 0.0

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            func y(_ lufs: Double) -> Double { (1 - (min(ceiling, max(floor, lufs)) - floor) / (ceiling - floor)) * size.height }
            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: Double(index) / Double(values.count - 1) * size.width, y: y(value))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [Ink.warm.opacity(0.28), Ink.warm.opacity(0.0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(Ink.warm), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            if let integrated {
                var reference = Path()
                reference.move(to: CGPoint(x: 0, y: y(integrated)))
                reference.addLine(to: CGPoint(x: size.width, y: y(integrated)))
                context.stroke(reference, with: .color(Ink.primary.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Correlation from −1 (antiphase) to +1 (mono-identical).
struct CorrelationMeter: View {
    let value: Double
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let x = (value + 1) / 2 * proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [Ink.alert.opacity(0.55), Ink.warm.opacity(0.4), Ink.accent.opacity(0.6)],
                                                  startPoint: .leading, endPoint: .trailing)).frame(height: 6)
                    Rectangle().fill(Ink.primary.opacity(0.3)).frame(width: 1, height: 12).offset(x: proxy.size.width / 2)
                    Circle().fill(Ink.primary).frame(width: 14, height: 14).shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(x: min(proxy.size.width - 14, max(0, x - 7)))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            HStack {
                Text("−1  Opposed"); Spacer(); Text("0"); Spacer(); Text("Mono-safe  +1")
            }
            .font(.caption2).foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stereo correlation")
        .accessibilityValue(decimal(value, 2))
    }
}
