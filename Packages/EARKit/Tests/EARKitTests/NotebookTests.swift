import Foundation
import Testing
@testable import EARKit

@Suite struct NotebookTests {
    let folder: URL
    let study: Study

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metrics = try Signals.analyze(seconds: 4, Signals.sine(220, amplitude: 0.3))
        study = Study(title: "Check", filename: "study.caf", source: "Generated fixture", metrics: metrics)
    }

    var url: URL { folder.appendingPathComponent("notebook.json") }

    @Test func saveAndReloadKeepsEdits() throws {
        try NotebookFiles.save(Notebook(studies: [study]), to: url)
        var edited = study; edited.notes = "A saved listening note"; edited.tempoOverride = 96
        try NotebookFiles.save(Notebook(studies: [edited], labTried: ["drums.ghost-notes"]), to: url)
        let saved = try NotebookFiles.load(from: url)
        #expect(saved.notebook.studies[0].notes == edited.notes && !saved.recovered)
        #expect(saved.notebook.labTried == ["drums.ghost-notes"])
        #expect(saved.notebook.version == Notebook.currentVersion)
    }

    @Test func damagedIndexRecoversFromBackupAndIsPreserved() throws {
        try NotebookFiles.save(Notebook(studies: [study]), to: url)
        var edited = study; edited.notes = "newer"
        try NotebookFiles.save(Notebook(studies: [edited]), to: url)
        try Data("damaged index".utf8).write(to: url)
        let recovered = try NotebookFiles.load(from: url)
        #expect(recovered.recovered && recovered.notebook.studies[0].id == study.id)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.hasPrefix("notebook-damaged-") })
    }

    @Test func versionOneArrayStillOpens() throws {
        // EAR 1.x wrote a bare array of studies without the newer measurement fields.
        var legacy = study
        legacy.metrics.analysisVersion = nil; legacy.metrics.integratedLoudness = nil; legacy.metrics.truePeak = nil
        legacy.metrics.key = nil; legacy.metrics.spectrum = nil; legacy.metrics.loudnessTimeline = nil
        legacy.metrics.shortTermMax = nil; legacy.metrics.loudnessRange = nil
        let data = try JSONEncoder().encode([legacy])
        #expect(!String(decoding: data, as: UTF8.self).contains("integratedLoudness"))
        try data.write(to: url)
        let loaded = try NotebookFiles.load(from: url)
        #expect(loaded.notebook.studies.count == 1 && !loaded.recovered)
        #expect(loaded.notebook.studies[0].metrics.isCurrent == false)
        // Saving upgrades the file to the versioned envelope, keeping the old one as the backup.
        try NotebookFiles.save(loaded.notebook, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("{") && text.contains("\"version\":2"))
        let backup = try Data(contentsOf: url.appendingPathExtension("backup"))
        #expect(backup == data)
    }

    @Test func unknownFieldsFromTheFutureAreTolerated() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Notebook(studies: [study]))) as? [String: Any])
        object["somethingNew"] = ["a": 1]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        #expect(try NotebookFiles.load(from: url).notebook.studies.count == 1)
    }

    @Test func newerFormatIsNeverOverwritten() throws {
        try NotebookFiles.save(Notebook(studies: [study]), to: url)
        try NotebookFiles.save(Notebook(studies: [study]), to: url)
        let future = Data(#"{"version": 99, "studies": [], "labTried": []}"#.utf8)
        try future.write(to: url)
        #expect(throws: NotebookError.newerVersion(99)) { try NotebookFiles.load(from: url) }
        #expect(try Data(contentsOf: url) == future, "The newer notebook must be left untouched")
    }

    @Test(arguments: ["../outside.caf", "/outside.caf", "..", ""])
    func unsafeFilenamesAreRejected(name: String) throws {
        var invalid = study; invalid.filename = name
        #expect(throws: NotebookError.invalid) { try NotebookFiles.decode(JSONEncoder().encode([invalid])) }
    }

    @Test func invalidMeasurementsNeverReachTheInterface() throws {
        var invalid = study; invalid.metrics.bands = []
        #expect(throws: NotebookError.invalid) { try NotebookFiles.decode(JSONEncoder().encode([invalid])) }
        var loud = study; loud.metrics.integratedLoudness = .infinity
        #expect(throws: (any Error).self) { try NotebookFiles.decode(JSONEncoder().encode([loud])) }
        var duplicate = study; duplicate.title = "Copy"
        #expect(throws: NotebookError.invalid) { try NotebookFiles.decode(JSONEncoder().encode([study, duplicate])) }
    }

    @Test func emptyFolderStartsEmpty() throws {
        let loaded = try NotebookFiles.load(from: url)
        #expect(loaded.notebook.studies.isEmpty && !loaded.recovered)
    }
}
