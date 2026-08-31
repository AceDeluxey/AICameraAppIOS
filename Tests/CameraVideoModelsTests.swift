import XCTest
@testable import AICameraApp

final class CameraVideoModelsTests: XCTestCase {
    func testRecordingStatusBusyState() {
        XCTAssertFalse(VideoRecordingStatus.idle.isBusy)
        XCTAssertTrue(VideoRecordingStatus.preparing.isBusy)
        XCTAssertTrue(VideoRecordingStatus.recording(startedAt: Date()).isBusy)
        XCTAssertTrue(VideoRecordingStatus.saving.isBusy)
        XCTAssertFalse(VideoRecordingStatus.saved.isBusy)
        XCTAssertFalse(VideoRecordingStatus.failed("error").isBusy)
    }

    func testRecordingStatusOnlyReportsActiveRecording() {
        XCTAssertFalse(VideoRecordingStatus.preparing.isRecording)
        XCTAssertTrue(VideoRecordingStatus.recording(startedAt: Date()).isRecording)
        XCTAssertFalse(VideoRecordingStatus.saving.isRecording)
    }

    func testDurationFormatterUsesMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(125)

        XCTAssertEqual(VideoRecordingDurationFormatter.text(from: start, to: end), "02:05")
    }

    func testDurationFormatterAddsHoursWhenNeeded() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_661)

        XCTAssertEqual(VideoRecordingDurationFormatter.text(from: start, to: end), "01:01:01")
    }

    func testDurationFormatterClampsNegativeIntervals() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(-5)

        XCTAssertEqual(VideoRecordingDurationFormatter.text(from: start, to: end), "00:00")
    }
}
