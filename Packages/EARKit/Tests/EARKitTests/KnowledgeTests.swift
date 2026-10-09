import Foundation
import Testing
@testable import EARKit

@Suite struct KnowledgeTests {
    @Test func catalogHas36UniqueExperiments() {
        let catalog = Lens.allCases.flatMap { Experiment.catalog($0, daw: .studio, tempo: 120) }
        #expect(catalog.count == 36 && Set(catalog.map(\.id)).count == 36)
    }

    @Test func searchFindsTechniques() {
        let catalog = Experiment.all(daw: .studio)
        #expect(catalog.filter { $0.matches("sidechain vocal") }.contains { $0.id == "space.ducked-bloom" })
        #expect(catalog.filter { $0.matches("808") }.contains { $0.id == "bass.harmonics" })
        #expect(catalog.filter { $0.matches("") }.count == 36)
    }

    @Test(arguments: DAW.allCases)
    func everyLensHasAGuideAndFourRecipes(daw: DAW) {
        for lens in Lens.allCases {
            let recipes = Experiment.catalog(lens, daw: daw, tempo: 90)
            #expect(recipes.count == 4 && recipes[0].id == lens.rawValue, "Existing completion IDs must remain valid")
            #expect(recipes.allSatisfy { $0.steps.count >= 4 && !$0.check.isEmpty && $0.minutes > 0 })
            #expect(ProductionGuide.make(lens).cues.count == 3)
            #expect(Experiment.make(lens, daw: daw, tempo: 120).steps.count >= 4)
        }
    }

    @Test func noPlaceholderIsLeftUnfilled() {
        for daw in DAW.allCases {
            for tempo in [nil, 30, 120, .nan] as [Double?] {
                for e in Lens.allCases.flatMap({ Experiment.catalog($0, daw: daw, tempo: tempo) }) {
                    let text = ([e.title, e.purpose, e.check] + e.steps).joined()
                    #expect(!text.contains("{") && !text.contains("}"), "\(e.id) has an unfilled token")
                }
            }
        }
    }

    /// The content moved from Swift literals to Knowledge.json. Every render must be identical to EAR 1.2.
    @Test func contentMatchesEAR12Exactly() throws {
        struct Render: Decodable { var id, daw, title, purpose, check: String; var tempo: Double?; var steps: [String] }
        let url = try #require(Bundle.module.url(forResource: "LegacyRenders", withExtension: "json", subdirectory: "Fixtures"))
        let renders = try JSONDecoder().decode([Render].self, from: Data(contentsOf: url))
        #expect(renders.count == 144)
        for expected in renders {
            let daw = try #require(DAW(rawValue: expected.daw))
            let actual = try #require(Experiment.all(daw: daw).first { $0.id == expected.id }.flatMap { found in
                Experiment.catalog(found.lens, daw: daw, tempo: expected.tempo).first { $0.id == expected.id }
            })
            #expect(actual.title == expected.title)
            #expect(actual.purpose == expected.purpose)
            #expect(actual.steps == expected.steps, "\(expected.id) \(expected.daw) \(String(describing: expected.tempo))")
            #expect(actual.check == expected.check)
        }
    }

    @Test func delayTimes() {
        let times = NoteTime.all.compactMap { $0.milliseconds(at: 120) }
        #expect(times.count == 5 && abs(times[0] - 500) < 0.001 && abs(times[1] - 375) < 0.001 && abs(times[3] - 166.6666667) < 0.001)
        #expect(NoteTime.all[0].milliseconds(at: 0) == nil && NoteTime.all[0].milliseconds(at: .nan) == nil)
    }

    @Test func findingsDescribeEveryLens() throws {
        var metrics = try Signals.analyze(seconds: 4, Signals.sine(220, amplitude: 0.3))
        let study = Study(title: "Check", filename: "a.caf", source: "Fixture", metrics: metrics)
        for lens in Lens.allCases { #expect(!Finding.make(lens, study: study).evidence.isEmpty) }
        #expect(Finding.make(.dynamics, study: study).evidence.contains("LUFS"))
        #expect(study.shareText.contains("LUFS") && study.shareText.contains("MY NOTES"))
        metrics.integratedLoudness = nil
        let legacy = Study(title: "Old", filename: "b.caf", source: "Fixture", metrics: metrics)
        #expect(Finding.make(.dynamics, study: legacy).evidence.contains("Re-measure"))
    }
}
