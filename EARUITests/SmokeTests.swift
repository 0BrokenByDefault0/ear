import XCTest

final class SmokeTests: XCTestCase {
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
        app.buttons["editTempo"].tap()
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()
        let delay = app.staticTexts["Follow the repeats"]
        for _ in 0..<5 { if delay.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(delay.isHittable)
        delay.tap()
        XCTAssertTrue(app.buttons["tryExperiment"].waitForExistence(timeout: 5))
        shot("03-Delay-lens")
        app.buttons["tryExperiment"].tap()
        XCTAssertTrue(app.staticTexts["Throw one word into orbit"].waitForExistence(timeout: 5))
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
}
