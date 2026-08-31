@testable import AICameraApp
import XCTest

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
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(125)

        XCTAssertEqual(VideoRecordingDurationFormatter.text(from: start, to: end), "02:05")
    }

    func testDurationFormatterAddsHoursWhenNeeded() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(3661)

        XCTAssertEqual(VideoRecordingDurationFormatter.text(from: start, to: end), "01:01:01")
    }

    func testDurationFormatterClampsNegativeIntervals() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(-5)

        XCTAssertEqual(VideoRecordingDurationFormatter.text(from: start, to: end), "00:00")
    }

    func testFormatOptionsOnlyContainSupportedCombinations() {
        let descriptors = [
            VideoFormatDescriptor(width: 4032, height: 3024, frameRateRanges: [24 ... 30]),
            VideoFormatDescriptor(width: 3840, height: 2160, frameRateRanges: [24 ... 60]),
            VideoFormatDescriptor(width: 1920, height: 1080, frameRateRanges: [24 ... 120]),
            VideoFormatDescriptor(width: 1280, height: 720, frameRateRanges: [24 ... 240]),
        ]

        let options = VideoFormatOptionBuilder.options(from: descriptors)

        XCTAssertTrue(options.contains(VideoFormatOption(
            resolution: .fullPixel,
            width: 4032,
            height: 3024,
            framesPerSecond: 30
        )))
        XCTAssertFalse(options.contains { $0.resolution == .fullPixel && $0.framesPerSecond == 60 })
        XCTAssertTrue(options.contains { $0.resolution == .fourK && $0.framesPerSecond == 60 })
        XCTAssertTrue(options.contains {
            $0.resolution == .fullHighDefinition && $0.framesPerSecond == 120
        })
        XCTAssertFalse(options.contains { $0.framesPerSecond == 240 })
    }

    func testFormatOptionsRemoveDuplicateDeviceFormats() {
        let descriptor = VideoFormatDescriptor(
            width: 1920,
            height: 1080,
            frameRateRanges: [24 ... 60]
        )

        XCTAssertEqual(VideoFormatOptionBuilder.options(from: [descriptor, descriptor]).count, 2)
    }

    func testHUDFormatterHandlesKnownAndUnavailableValues() {
        XCTAssertEqual(VideoRecordingHUDFormatter.batteryText(level: 0.526), "电量 53%")
        XCTAssertEqual(VideoRecordingHUDFormatter.batteryText(level: nil), "电量 --")
        XCTAssertEqual(VideoRecordingHUDFormatter.storageText(bytes: nil), "可用 --")
        XCTAssertTrue(VideoRecordingHUDFormatter.storageText(bytes: 1_000_000_000).hasPrefix("可用 "))
    }
}
