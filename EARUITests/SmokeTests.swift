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
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), app.debugDescription)
        shot("00-File-picker")
        cancel.tap()
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: pick)
        waitForExpectations(timeout: 10)
        pick.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 20)); cancel.tap()
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
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
        app.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0.35)
        app.buttons["phraseLoop"].tap()
        app.buttons["Set loop end here"].tap()
        XCTAssertTrue(app.staticTexts["Looping · Your phrase"].waitForExistence(timeout: 5))
        expectPlayback("Pause", in: app)
        app.buttons["transportPlay"].tap()
        app.buttons["phraseLoop"].tap()
        app.buttons["Clear loop"].tap()

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
