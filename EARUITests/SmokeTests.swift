import XCTest

@MainActor final class SmokeTests: XCTestCase {
    /// Skips onboarding through the user-defaults argument domain.
    func launch(_ extra: [String] = [], onboarded: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = (onboarded ? ["-ear.onboarded", "YES"] : ["--reset-onboarding"]) + extra
        app.launch()
        return app
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    /// Finds any element whose accessibility label contains the text, including text merged into buttons.
    func element(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func expectPlayback(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let state = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: state, object: app.buttons["transportPlay"])], timeout: timeout)
        XCTAssertEqual(result, .completed, app.debugDescription, file: file, line: line)
    }

    func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 10) {
        for _ in 0..<attempts where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    func testOnboardingLeadsToListen() {
        let app = launch(onboarded: false)
        let next = app.buttons["onboardingContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        shot("00-Onboarding-1")
        next.tap()
        shot("00-Onboarding-2")
        next.tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        shot("00-Onboarding-3")
        next.tap()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10))
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = []
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["importAudio"].waitForExistence(timeout: 15), "Onboarding is shown once")
        XCTAssertFalse(relaunched.buttons["onboardingContinue"].exists)
    }

    /// The system document browser itself. Selecting files is covered by testImportPipeline: the simulator's
    /// file provider intermittently fails to materialise picked items, which is outside EAR's control.
    func testFilePickerPresentsCancelsAndReopens() {
        let app = launch(["--import-ui-check"])
        let pick = app.buttons["importAudio"]
        XCTAssertTrue(pick.waitForExistence(timeout: 15)); pick.tap()
        let cancel = app.buttons["Cancel"]
        // The document browser runs in a separate process that can take a while to start on a freshly booted simulator.
        XCTAssertTrue(cancel.waitForExistence(timeout: 90), app.debugDescription)
        shot("00-File-picker")
        cancel.tap()
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: pick)
        waitForExpectations(timeout: 10)
        pick.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 45)); cancel.tap()
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
    }

    /// Opens Browse → On My iPhone in the system document browser and taps a file, as a person would.
    func chooseInPicker(_ name: String, in app: XCUIApplication) {
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if !file.waitForExistence(timeout: 5) {
            let browse = app.buttons["Browse"]
            if browse.waitForExistence(timeout: 10) { browse.tap() }
            // Browse may open inside a folder; walk back to the locations list.
            let back = app.buttons["BackButton"]
            for _ in 0..<3 where back.exists && !file.exists { back.tap() }
            if !file.waitForExistence(timeout: 3) {
                let local = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@ OR label BEGINSWITH %@", "On My iPhone", "On My iPhone")).firstMatch
                XCTAssertTrue(local.waitForExistence(timeout: 15), app.debugDescription)
                local.tap()
            }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 20), app.debugDescription)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: file)
        waitForExpectations(timeout: 10)
        shot("00-Picker-\(name)")
        let title = file.staticTexts[name]
        if title.exists { title.tap() } else { file.tap() }
        // Single selection returns on tap; some layouts still ask for Open.
        let open = app.buttons["Open"]
        if open.waitForExistence(timeout: 3), open.isEnabled { open.tap() }
    }

    /// The step that failed on device: choose a song in Files, tap it, and get a study.
    /// CI places "EAR Picker Check.wav" in On My iPhone before the tests run. Each picker
    /// configuration is tried so a failure says which ones the system accepts.
    func testFilePickerSelectionImportsAudio() {
        continueAfterFailure = true
        var results: [String] = []
        for mode in ["default", "copyAudio", "openAudio", "swiftui"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ear.onboarded", "YES", "-ear.pickerMode", mode]
            app.launch()
            let pick = app.buttons["importAudio"]
            guard pick.waitForExistence(timeout: 15) else { results.append("\(mode): no import button"); continue }
            pick.tap()
            guard app.buttons["Cancel"].waitForExistence(timeout: 90) else { results.append("\(mode): picker did not open"); continue }
            chooseInPicker("EAR Picker Check", in: app)
            let imported = app.staticTexts["studyTitle"].waitForExistence(timeout: 30)
            shot("10-Picker-\(mode)-\(imported ? "imported" : "stuck")")
            results.append("\(mode): \(imported ? "IMPORTED" : "nothing returned")")
            print("PICKER MODE \(results.last!)")
            app.terminate()
        }
        let summary = XCTAttachment(string: results.joined(separator: "\n"))
        summary.name = "Picker matrix"; summary.lifetime = .keepAlways; add(summary)
        print("PICKER MATRIX\n" + results.joined(separator: "\n"))
        XCTAssertTrue(results.first?.hasSuffix("IMPORTED") == true, "Production picker must import: \(results)")
    }

    func testImportPipelineAnalysesPlaysAndPersists() {
        let app = launch(["--import-fixture", "EAR Import Check.caf"])
        XCTAssertTrue(app.staticTexts["studyTitle"].waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertEqual(app.staticTexts["studyTitle"].label, "EAR Import Check")
        XCTAssertTrue(element("LUFS", in: app).exists, "Loudness is measured on import")
        app.buttons["transportPlay"].tap()
        expectPlayback("Pause", in: app)
        app.buttons["closeStudy"].tap()
        app.tabBars.buttons["Notebook"].tap()
        XCTAssertTrue(element("EAR Import Check", in: app).waitForExistence(timeout: 10))
        app.terminate()
        let relaunched = launch()
        relaunched.tabBars.buttons["Notebook"].tap()
        XCTAssertTrue(element("EAR Import Check", in: relaunched).waitForExistence(timeout: 10))
    }

    func testInvalidImportExplainsAndLeavesNotebookUnchanged() {
        let app = launch(["--import-fixture", "EAR Invalid Check.txt"])
        XCTAssertTrue(app.alerts["EAR"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "decoded as audio")).firstMatch.exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["importAudio"].isEnabled)
    }

    func testLabSearchAndProgress() {
        let app = launch()
        app.tabBars.buttons["Lab"].tap()
        shot("07-Lab")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("formant")
        let result = app.buttons["lab.vocals.formant-shadow"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        XCTAssertTrue(app.staticTexts["Put a formant shadow under a word"].waitForExistence(timeout: 10))
        shot("08-Experiment")
        let complete = app.buttons["completeExperiment"]
        scrollTo(complete, in: app)
        if complete.label != "Experiment tried" { complete.tap() }
        app.terminate()
        let relaunched = launch()
        relaunched.tabBars.buttons["Lab"].tap()
        let field = relaunched.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("formant")
        let saved = relaunched.buttons["lab.vocals.formant-shadow"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertEqual(saved.value as? String, "Tried")
    }

    func testListeningJourney() {
        let app = launch()
        XCTAssertTrue(app.buttons["demoStudy"].waitForExistence(timeout: 15))
        shot("01-Listen")
        app.buttons["demoStudy"].tap()
        XCTAssertTrue(app.staticTexts["studyTitle"].waitForExistence(timeout: 60))
        XCTAssertEqual(app.staticTexts["studyTitle"].label, "Afterglow")
        shot("02-Study")
        app.buttons["transportPlay"].tap()
        expectPlayback("Pause", in: app)
        app.buttons["monoAudition"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Switch to stereo"), evaluatedWith: app.buttons["monoAudition"])
        waitForExpectations(timeout: 30)
        expectPlayback("Pause", in: app)
        app.buttons["transportPlay"].tap()
        app.buttons["phraseLoop"].tap()
        app.buttons["Set loop start here"].tap()
        // Wait for the menu to finish dismissing so the slider drag is not swallowed by it.
        XCTAssertTrue(element("Start marked", in: app).waitForExistence(timeout: 5))
        let slider = app.sliders["playbackPosition"]
        let marked = slider.value as? String
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: slider)
        waitForExpectations(timeout: 5)
        for _ in 0..<3 where (slider.value as? String) == marked { slider.adjust(toNormalizedSliderPosition: 0.6) }
        XCTAssertNotEqual(slider.value as? String, marked, "Scrubbing must move the playhead")
        app.buttons["phraseLoop"].tap()
        app.buttons["Set loop end here"].tap()
        XCTAssertTrue(app.staticTexts["Looping · Your phrase"].waitForExistence(timeout: 5))
        expectPlayback("Pause", in: app)
        app.buttons["transportPlay"].tap()
        app.buttons["phraseLoop"].tap()
        // The menu item; the Moments section has its own "Clear loop" button too.
        let clear = app.collectionViews.buttons["Clear loop"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Looping · Your phrase"])
        waitForExpectations(timeout: 5)

        app.buttons["editTempo"].tap()
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()
        app.buttons["editTempo"].tap()
        XCTAssertTrue(app.buttons["restoreTempo"].waitForExistence(timeout: 5))
        app.buttons["restoreTempo"].tap()

        app.swipeUp()
        shot("03-Study-loudness")
        app.swipeUp()
        shot("04-Study-spectrum")
        let delay = element("Follow the repeats", in: app)
        scrollTo(delay, in: app)
        delay.tap()
        XCTAssertTrue(app.buttons["tryExperiment"].waitForExistence(timeout: 5))
        shot("05-Delay-lens")
        app.buttons["tryExperiment"].tap()
        XCTAssertTrue(app.staticTexts["Throw one word into orbit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transportPlay"].exists, "Playback must remain available inside the experiment")
        shot("06-Experiment")
        let complete = app.buttons["completeExperiment"]
        scrollTo(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.buttons["Experiment tried"].waitForExistence(timeout: 5))
        app.terminate()

        let relaunched = launch()
        relaunched.tabBars.buttons["Notebook"].tap()
        XCTAssertTrue(element("Afterglow", in: relaunched).waitForExistence(timeout: 8))
        XCTAssertTrue(element("1 tried", in: relaunched).exists)
        shot("09-Notebook")
    }

    func testNotesAndEndOfTrack() {
        let app = launch()
        XCTAssertTrue(app.buttons["demoStudy"].waitForExistence(timeout: 15))
        app.buttons["demoStudy"].tap()
        XCTAssertTrue(app.staticTexts["studyTitle"].waitForExistence(timeout: 60))
        let notes = app.buttons["editNotes"]
        scrollTo(notes, in: app, attempts: 14)
        notes.tap()
        let editor = app.textViews["notesEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Listen to the phrase ending.")
        app.buttons["Save"].tap()
        app.terminate()

        let relaunched = launch()
        relaunched.buttons["demoStudy"].tap()
        XCTAssertTrue(relaunched.staticTexts["studyTitle"].waitForExistence(timeout: 20))
        let savedNotes = relaunched.buttons["editNotes"]
        scrollTo(savedNotes, in: relaunched, attempts: 14)
        savedNotes.tap()
        let savedEditor = relaunched.textViews["notesEditor"]
        XCTAssertTrue(savedEditor.waitForExistence(timeout: 5))
        XCTAssertTrue((savedEditor.value as? String ?? "").contains("Listen to the phrase ending."))
        relaunched.buttons["Cancel"].tap()

        relaunched.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0.85)
        relaunched.buttons["transportPlay"].tap()
        expectPlayback("Pause", in: relaunched)
        expectPlayback("Play", in: relaunched, timeout: 15)
        XCTAssertEqual(relaunched.sliders["playbackPosition"].value as? String, "0:30")
        relaunched.buttons["transportPlay"].tap()
        expectPlayback("Pause", in: relaunched)
    }
}
