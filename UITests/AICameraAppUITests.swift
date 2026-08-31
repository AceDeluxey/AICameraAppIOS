import XCTest

final class AICameraAppUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testPrimaryCameraControlsArePresent() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["aspectRatioButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shutterButton"].exists)
        XCTAssertTrue(app.buttons["birdModeButton"].exists)
    }
}
