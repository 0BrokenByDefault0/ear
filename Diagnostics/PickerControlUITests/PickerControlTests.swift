import XCTest

@MainActor final class PickerControlTests: XCTestCase {
    func testPickFromOnMyiPhone() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["pick"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 90), app.debugDescription)
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "EAR Picker Check")).firstMatch
        if !file.waitForExistence(timeout: 5) {
            if app.buttons["Browse"].waitForExistence(timeout: 10) { app.buttons["Browse"].tap() }
            let back = app.buttons["BackButton"]
            for _ in 0..<3 where back.exists && !file.exists { back.tap() }
            if !file.waitForExistence(timeout: 3) {
                let local = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@ OR label BEGINSWITH %@", "On My iPhone", "On My iPhone")).firstMatch
                XCTAssertTrue(local.waitForExistence(timeout: 15), app.debugDescription)
                local.tap()
            }
        }
        XCTAssertTrue(file.waitForExistence(timeout: 20), app.debugDescription)
        let title = file.staticTexts["EAR Picker Check"]
        if title.exists { title.tap() } else { file.tap() }
        let open = app.buttons["Open"]
        if open.waitForExistence(timeout: 3), open.isEnabled { open.tap() }
        let picked = NSPredicate(format: "label BEGINSWITH %@", "Picked")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: picked, object: app.staticTexts["result"])], timeout: 30)
        print("PICKER CONTROL: \(app.staticTexts["result"].label)")
        XCTAssertEqual(result, .completed, app.debugDescription)
    }
}
