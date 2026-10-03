import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import EARKit

/// A branded portrait card (1080 × 1350) summarising a study, rendered only when it is shared.
struct StudyCardExport: Transferable {
    let study: Study

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { export in
            try await export.pngData()
        }
        .suggestedFileName { "\($0.study.title) — EAR.png" }
    }

    @MainActor func pngData() throws -> Data {
        let renderer = ImageRenderer(content: ShareCard(study: study))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw EarError.message("Could not render the study card.")
        }
        return data
    }
}

struct ShareCard: View {
    let study: Study

    var body: some View {
        let m = study.metrics
        ZStack {
            Ink.background
            RadialGradient(colors: [Ink.glow.opacity(0.35), .clear], center: .init(x: 0.9, y: 0.05), startRadius: 0, endRadius: 900)
            RadialGradient(colors: [Ink.accent.opacity(0.12), .clear], center: .init(x: 0.05, y: 0.6), startRadius: 0, endRadius: 700)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("EAR").font(.system(size: 34, weight: .semibold, design: .monospaced)).tracking(14)
                    Spacer()
                    Text("A CLOSER LISTEN").font(.system(size: 22, design: .monospaced)).tracking(5).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 60)
                Text(study.title).font(.custom("AeonNocturne-Regular", size: 120)).lineLimit(2).minimumScaleFactor(0.4)
                Waveform(values: m.waveform, progress: 1, played: Ink.accent, barWidth: 5).frame(height: 190).padding(.vertical, 60)
                HStack(spacing: 24) {
                    figure("TEMPO", study.tempo.map { decimal($0, 0) } ?? "—", "BPM")
                    figure("KEY", m.key?.shortName ?? "—", m.key?.camelot ?? "")
                    figure("LOUDNESS", m.integratedLoudness.map { decimal($0, 1) } ?? decimal(m.rms, 1), m.integratedLoudness == nil ? "dBFS" : "LUFS")
                    figure("PEAK", decimal(m.truePeak ?? m.peak, 1), m.truePeak == nil ? "dBFS" : "dBTP")
                }
                Spacer(minLength: 60)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach([Lens.stereo, .dynamics, .bass], id: \.self) { lens in
                        HStack(spacing: 20) {
                            Image(systemName: lens.symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Ink.accent).frame(width: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lens.rawValue.uppercased()).font(.system(size: 18, design: .monospaced)).tracking(3).foregroundStyle(Ink.secondary)
                                Text(Finding.make(lens, study: study).title).font(.system(size: 32))
                            }
                        }
                    }
                }
                Spacer(minLength: 40)
                Text("Measured on device with EAR · \(clock(m.duration)) · \(m.channels == 1 ? "mono" : "stereo")")
                    .font(.system(size: 20, design: .monospaced)).foregroundStyle(Ink.secondary)
            }
            .padding(80)
        }
        .foregroundStyle(Ink.primary)
        .frame(width: 1080, height: 1350)
        .environment(\.colorScheme, .dark)
    }

    private func figure(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 18, design: .monospaced)).tracking(3).foregroundStyle(Ink.secondary)
            Text(value).font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(unit).font(.system(size: 22, design: .monospaced)).foregroundStyle(Ink.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(26)
        .background(Ink.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Ink.line, lineWidth: 1))
    }
}
