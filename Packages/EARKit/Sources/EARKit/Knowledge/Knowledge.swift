import Foundation

public struct ProductionGuide: Codable, Sendable {
    public var principle: String
    public var cues: [String]
    public var trap: String

    public static func make(_ lens: Lens) -> ProductionGuide { Knowledge.content.guides[lens.key] ?? Knowledge.missingGuide }
}

public struct Experiment: Identifiable, Sendable {
    public var id: String
    public var lens: Lens
    public var title: String
    public var purpose: String
    public var minutes: Int
    public var steps: [String]
    public var check: String

    public func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        let content = ([title, purpose, lens.rawValue, check] + steps).joined(separator: " ")
        return words.allSatisfy { content.localizedStandardContains(String($0)) }
    }

    /// The four experiments for a lens. The first keeps the lens name as its ID so completions
    /// saved by EAR 1.0 still resolve.
    public static func catalog(_ lens: Lens, daw: DAW, tempo: Double?) -> [Experiment] {
        Knowledge.content.experiments.filter { $0.lens == lens.key }.map { $0.render(daw: daw, tempo: tempo) }
    }

    public static func make(_ lens: Lens, daw: DAW, tempo: Double?) -> Experiment {
        catalog(lens, daw: daw, tempo: tempo)[0]
    }

    public static func all(daw: DAW) -> [Experiment] { Lens.allCases.flatMap { catalog($0, daw: daw, tempo: nil) } }

    public func text(daw: DAW) -> String {
        "EAR EXPERIMENT — \(title)\n\(daw.rawValue) • \(minutes) min\n\n\(purpose)\n\n"
            + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
            + "\n\nCHECK\n\(check)"
    }
}

public struct NoteTime: Identifiable, Sendable {
    public var name: String
    public var beats: Double
    public var id: String { name }

    public func milliseconds(at bpm: Double) -> Double? {
        guard bpm.isFinite, (40...240).contains(bpm) else { return nil }
        return 60000 / bpm * beats
    }

    public static let all = [
        NoteTime(name: "Quarter", beats: 1), NoteTime(name: "Dotted eighth", beats: 0.75),
        NoteTime(name: "Eighth", beats: 0.5), NoteTime(name: "Eighth triplet", beats: 1.0 / 3),
        NoteTime(name: "Sixteenth", beats: 0.25),
    ]
}

/// Teaching content bundled as `Knowledge.json`. Templates use `{token}` placeholders for
/// DAW-specific routing and plug-in names and for tempo-derived timing.
enum Knowledge {
    struct Content: Decodable, Sendable {
        var version: Int
        var tokens: [String: [String: String]]
        var guides: [String: ProductionGuide]
        var experiments: [Entry]
    }

    /// A string, or a per-DAW pair of strings keyed by DAW name.
    enum Text: Decodable, Sendable {
        case plain(String)
        case perDAW([String: String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .plain(value) }
            else { self = .perDAW(try container.decode([String: String].self)) }
        }

        func value(for daw: DAW) -> String {
            switch self {
            case .plain(let value): value
            case .perDAW(let values): values[daw.rawValue] ?? values.values.first ?? ""
            }
        }
    }

    struct Entry: Decodable, Sendable {
        var id: String
        var lens: String
        var minutes: Int
        var title: Text
        var purpose: Text
        var steps: [Text]
        var check: Text

        func render(daw: DAW, tempo: Double?) -> Experiment {
            let bpm = tempo.flatMap { $0.isFinite && (40...240).contains($0) ? $0 : nil }
            func fill(_ text: Text) -> String { Knowledge.fill(text.value(for: daw), daw: daw, bpm: bpm) }
            return Experiment(id: id, lens: Lens.allCases.first { $0.key == lens } ?? .drums, title: fill(title),
                              purpose: fill(purpose), minutes: minutes, steps: steps.map(fill), check: fill(check))
        }
    }

    static let content: Content = {
        guard let url = Bundle.module.url(forResource: "Knowledge", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(Content.self, from: data) else {
            assertionFailure("Knowledge.json is missing or invalid")
            return Content(version: 0, tokens: [:], guides: [:], experiments: [])
        }
        return content
    }()

    static let missingGuide = ProductionGuide(principle: "", cues: [], trap: "")

    static func fill(_ template: String, daw: DAW, bpm: Double?) -> String {
        guard template.contains("{") else { return template }
        var text = template
        text = text.replacingOccurrences(of: "{tempo}", with: bpm.map {
            "At \(decimal($0, 0)) BPM, start at \(decimal(30000 / $0, 0)) ms (1/8 note)."
        } ?? "Tap or set the song tempo first, then start at a synced 1/8 note.")
        text = text.replacingOccurrences(of: "{eighth}", with: bpm.map {
            "At \(decimal($0, 0)) BPM, an eighth is \(decimal(30000 / $0, 0)) ms."
        } ?? "Set the session tempo first; use a synced eighth note as the starting offset.")
        for (token, values) in content.tokens {
            text = text.replacingOccurrences(of: "{\(token)}", with: values[daw.rawValue] ?? "")
        }
        return text
    }
}
