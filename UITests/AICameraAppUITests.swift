import XCTest

final class AICameraAppUITests: XCTestCase {
    private func makeApp(cameraUnauthorized: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AICAMERA_UI_TEST_STATE"] = cameraUnauthorized
            ? "unauthorized"
            : "running"
        return app
    }

    func testAppLaunches() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testPrimaryCameraControlsArePresent() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["aspectRatioButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shutterButton"].exists)
        XCTAssertTrue(app.buttons["birdModeButton"].exists)
        XCTAssertTrue(app.buttons["photoModeButton"].exists)
        XCTAssertTrue(app.buttons["videoModeButton"].exists)
    }

    func testCameraPermissionDenialShowsSettingsRecovery() {
        let app = makeApp(cameraUnauthorized: true)
        app.launch()

        let permissionMessage = app.staticTexts["需要相机权限"]
        XCTAssertTrue(permissionMessage.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["shutterButton"].isEnabled)
    }

    func testBackgroundAndForegroundPreservePrimaryControls() {
        let app = makeApp()
        app.launch()
        let videoButton = app.buttons["videoModeButton"]
        XCTAssertTrue(videoButton.waitForExistence(timeout: 5))
        videoButton.tap()
        XCTAssertEqual(videoButton.value as? String, "已选择")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertEqual(videoButton.value as? String, "已选择")
        XCTAssertTrue(app.buttons["birdModeButton"].exists)
    }

    func testSwitchesBetweenPhotoAndVideoModes() {
        let app = makeApp()
        app.launch()

        let photoButton = app.buttons["photoModeButton"]
        let videoButton = app.buttons["videoModeButton"]
        XCTAssertTrue(videoButton.waitForExistence(timeout: 5))
        XCTAssertEqual(photoButton.value as? String, "已选择")

        videoButton.tap()
        XCTAssertEqual(videoButton.value as? String, "已选择")
        XCTAssertEqual(app.buttons["shutterButton"].label, "开始录像")

        photoButton.tap()
        XCTAssertEqual(photoButton.value as? String, "已选择")
        XCTAssertEqual(app.buttons["shutterButton"].label, "拍照")
    }
}
