import Foundation

/// The saved notebook. Version 1 files were a bare `[Study]` array; version 2 adds an envelope
/// so the format can evolve without locking anyone out of their notes.
public struct Notebook: Codable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var studies: [Study]
    /// Experiment IDs marked as tried from the Lab (outside a particular study).
    public var labTried: [String]

    public init(studies: [Study] = [], labTried: [String] = []) {
        self.version = Self.currentVersion
        self.studies = studies
        self.labTried = labTried
    }
}

public enum NotebookError: LocalizedError, Equatable {
    case invalid
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalid: "The notebook contains an invalid study."
        case .newerVersion(let version):
            "This notebook was saved by a newer version of EAR (format \(version)). Update EAR to open it. Nothing has been changed."
        }
    }
}

/// Keeps a validated last-good copy of the notebook beside the live file.
public enum NotebookFiles {
    public static func decode(_ data: Data) throws -> Notebook {
        let first = data.first { !$0.isWhitespace }
        let notebook: Notebook
        if first == UInt8(ascii: "[") {
            notebook = Notebook(studies: try JSONDecoder().decode([Study].self, from: data))
        } else {
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.version <= Notebook.currentVersion else { throw NotebookError.newerVersion(header.version) }
            notebook = try JSONDecoder().decode(Notebook.self, from: data)
        }
        guard Set(notebook.studies.map(\.id)).count == notebook.studies.count,
              notebook.studies.allSatisfy(\.isValid) else { throw NotebookError.invalid }
        var current = notebook
        current.version = Notebook.currentVersion
        return current
    }

    public static func encode(_ notebook: Notebook) throws -> Data {
        var current = notebook
        current.version = Notebook.currentVersion
        let data = try JSONEncoder().encode(current)
        _ = try decode(data)
        return data
    }

    public static func load(from url: URL) throws -> (notebook: Notebook, recovered: Bool) {
        let backup = url.appendingPathExtension("backup")
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists && !FileManager.default.fileExists(atPath: backup.path) { return (Notebook(), false) }
        do {
            return (try decode(Data(contentsOf: url)), false)
        } catch let error as NotebookError where error != .invalid {
            // A newer format is not damage. Never fall back to an older copy and overwrite it.
            throw error
        } catch {
            let notebook = try decode(Data(contentsOf: backup))
            if exists {
                // Preserve the damaged index for recovery before allowing another save.
                try FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent()
                    .appendingPathComponent("notebook-damaged-\(UUID().uuidString).json"))
            }
            try encode(notebook).write(to: url, options: .atomic)
            return (notebook, true)
        }
    }

    public static func save(_ notebook: Notebook, to url: URL) throws {
        let data = try encode(notebook)
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

    private struct Header: Decodable { var version: Int }
}

private extension UInt8 {
    var isWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}

extension Study {
    public var isValid: Bool {
        let m = metrics
        let fractions = m.bands + m.waveform + [m.sideFraction, m.lowSideFraction, m.midSideFraction, m.nearFullScale, m.tempoStrength]
        func finite(_ values: [Double]?, max count: Int) -> Bool {
            guard let values else { return true }
            return values.count <= count && values.allSatisfy(\.isFinite)
        }
        func inRange(_ value: Double?, _ range: ClosedRange<Double>) -> Bool {
            guard let value else { return true }
            return value.isFinite && range.contains(value)
        }
        return !filename.isEmpty && filename != "." && filename != ".."
            && !filename.contains("/") && !filename.contains("\\")
            && m.duration.isFinite && (3...900).contains(m.duration)
            && m.sampleRate.isFinite && (8000...192000).contains(m.sampleRate)
            && (1...2).contains(m.channels) && m.bands.count == 5
            && !m.waveform.isEmpty && m.waveform.count <= 420
            && fractions.allSatisfy { $0.isFinite && (0...1.000001).contains($0) }
            && [m.peak, m.rms, m.crest, m.transientRate].allSatisfy(\.isFinite)
            && m.correlation.isFinite && (-1...1).contains(m.correlation)
            && m.balance.isFinite && (-1...1).contains(m.balance)
            && [m.bpm, tempoOverride].allSatisfy { inRange($0, 40...240) }
            && m.moments.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.level.isFinite && $0.change.isFinite
                && $0.start >= 0 && $0.end > $0.start && $0.end <= m.duration + 0.02 }
            && Set(m.moments.map(\.id)).count == m.moments.count
            && inRange(m.integratedLoudness, -120...20) && inRange(m.shortTermMax, -120...20)
            && inRange(m.loudnessRange, 0...120) && inRange(m.truePeak, -160...40)
            && finite(m.spectrum, max: 64) && finite(m.loudnessTimeline, max: 600)
            && (m.key.map { (0...11).contains($0.tonic) && $0.confidence.isFinite } ?? true)
    }
}
