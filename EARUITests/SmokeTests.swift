import XCTest

@MainActor final class SmokeTests: XCTestCase {
    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testListeningJourney() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["demoStudy"].waitForExistence(timeout: 15))
        shot("01-Listen")
        app.buttons["demoStudy"].tap()
        XCTAssertTrue(app.staticTexts["studyTitle"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["Afterglow"].exists)
        shot("02-Study")
        app.buttons["transportPlay"].tap()
        XCTAssertEqual(app.buttons["transportPlay"].label, "Pause")
        app.buttons["monoAudition"].tap()
        let mono = NSPredicate(format: "label == %@", "Switch to stereo")
        expectation(for: mono, evaluatedWith: app.buttons["monoAudition"])
        waitForExpectations(timeout: 30)
        app.buttons["transportPlay"].tap()
        app.buttons["phraseLoop"].tap()
        app.buttons["Set loop start here"].tap()
        app.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0.35)
        app.buttons["phraseLoop"].tap()
        app.buttons["Set loop end here"].tap()
        XCTAssertTrue(app.staticTexts["Looping · Your phrase"].waitForExistence(timeout: 5))
        app.buttons["transportPlay"].tap()
        app.buttons["phraseLoop"].tap()
        app.buttons["Clear loop"].tap()
        app.buttons["editTempo"].tap()
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()
        app.buttons["editTempo"].tap()
        XCTAssertTrue(app.buttons["restoreTempo"].waitForExistence(timeout: 5))
        app.buttons["restoreTempo"].tap()
        let delay = app.staticTexts["Follow the repeats"]
        for _ in 0..<5 { if delay.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(delay.isHittable)
        delay.tap()
        XCTAssertTrue(app.buttons["tryExperiment"].waitForExistence(timeout: 5))
        shot("03-Delay-lens")
        app.buttons["tryExperiment"].tap()
        XCTAssertTrue(app.staticTexts["Throw one word into orbit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transportPlay"].exists, "Playback must remain available inside the experiment")
        shot("04-Experiment")
        let complete = app.buttons["completeExperiment"]
        for _ in 0..<7 { if complete.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(complete.isHittable); complete.tap()
        XCTAssertTrue(app.buttons["Experiment tried"].exists || complete.exists)
        app.terminate(); app.launch()
        app.tabBars.buttons["Notebook"].tap()
        XCTAssertTrue(app.staticTexts["Afterglow"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["1 tried"].exists)
        shot("05-Notebook")
    }

    func testNotesAndEndOfTrack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["demoStudy"].tap()
        XCTAssertTrue(app.staticTexts["studyTitle"].waitForExistence(timeout: 45))
        let notes = app.buttons["editNotes"]
        for _ in 0..<10 { if notes.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(notes.isHittable); notes.tap()
        let editor = app.textViews["notesEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Listen to the phrase ending.")
        app.buttons["Save"].tap()
        app.terminate(); app.launch()
        app.buttons["demoStudy"].tap()
        XCTAssertTrue(app.staticTexts["studyTitle"].waitForExistence(timeout: 10))
        for _ in 0..<10 { if notes.isHittable { break }; app.swipeUp() }
        notes.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("Listen to the phrase ending."))
        app.buttons["Cancel"].tap()
        app.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0.97)
        app.buttons["transportPlay"].tap()
        let stopped = NSPredicate(format: "label == %@", "Play")
        expectation(for: stopped, evaluatedWith: app.buttons["transportPlay"])
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.sliders["playbackPosition"].value as? String, "0:30")
        app.buttons["transportPlay"].tap()
        XCTAssertEqual(app.buttons["transportPlay"].label, "Pause")
    }
}
