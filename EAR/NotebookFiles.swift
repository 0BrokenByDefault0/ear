import Foundation

/// Keeps a last-good index without changing the format of existing EAR notebooks.
enum NotebookFiles {
    static func decode(_ data: Data) throws -> [Study] {
        let studies = try JSONDecoder().decode([Study].self, from: data)
        guard Set(studies.map(\.id)).count == studies.count,
              studies.allSatisfy({ $0.isValid }) else {
            throw EarError.message("The notebook contains an invalid study.")
        }
        return studies
    }

    static func load(from url: URL) throws -> (studies: [Study], recovered: Bool) {
        let backup = url.appendingPathExtension("backup")
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists && !FileManager.default.fileExists(atPath: backup.path) { return ([], false) }
        do {
            return (try decode(Data(contentsOf: url)), false)
        } catch {
            let studies = try decode(Data(contentsOf: backup))
            if exists {
                // Preserve the damaged index for recovery before allowing another save.
                try FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent()
                    .appendingPathComponent("notebook-damaged-\(UUID().uuidString).json"))
            }
            try JSONEncoder().encode(studies).write(to: url, options: .atomic)
            return (studies, true)
        }
    }

    static func save(_ studies: [Study], to url: URL) throws {
        let data = try JSONEncoder().encode(studies)
        _ = try decode(data)
        let backup = url.appendingPathExtension("backup")
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            _ = try decode(previous)
            try previous.write(to: backup, options: .atomic)
        } else {
            try data.write(to: backup, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

extension Study {
    var isValid: Bool {
        let m = metrics
        let fractions = m.bands + m.waveform + [m.sideFraction, m.lowSideFraction, m.midSideFraction, m.nearFullScale, m.tempoStrength]
        return !filename.isEmpty && filename != "." && filename != ".."
            && !filename.contains("/") && !filename.contains("\\")
            && m.duration.isFinite && (3...900).contains(m.duration)
            && m.sampleRate.isFinite && (8000...192000).contains(m.sampleRate)
            && (1...2).contains(m.channels) && m.bands.count == 5
            && !m.waveform.isEmpty && m.waveform.count <= 420
            && fractions.allSatisfy { $0.isFinite && (0...1.000001).contains($0) }
            && [m.peak, m.rms, m.crest, m.transientRate].allSatisfy { $0.isFinite }
            && m.correlation.isFinite && (-1...1).contains(m.correlation)
            && m.balance.isFinite && (-1...1).contains(m.balance)
            && [m.bpm, tempoOverride].allSatisfy { $0 == nil || ($0!.isFinite && (40...240).contains($0!)) }
            && m.moments.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.level.isFinite && $0.change.isFinite
                && $0.start >= 0 && $0.end > $0.start && $0.end <= m.duration + 0.02 }
            && Set(m.moments.map(\.id)).count == m.moments.count
    }
}
