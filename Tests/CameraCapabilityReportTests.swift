@testable import AICameraApp
import XCTest

final class CameraCapabilityReportTests: XCTestCase {
    func testTextDescriptionIncludesDeviceAndFormatDetails() {
        let report = CameraCapabilityReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            operatingSystem: "Test OS",
            activeDeviceID: "wide-camera",
            devices: [sampleDevice]
        )

        XCTAssertTrue(report.textDescription.contains("Active device: wide-camera"))
        XCTAssertTrue(report.textDescription.contains("Back Wide Camera"))
        XCTAssertTrue(report.textDescription.contains("1920x1080 420v"))
        XCTAssertTrue(report.textDescription.contains("stabilization=off,standard"))
    }

    func testReportRoundTripsThroughJSON() throws {
        let report = CameraCapabilityReport(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            operatingSystem: "Test OS",
            activeDeviceID: nil,
            devices: [sampleDevice]
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CameraCapabilityReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
    }

    private var sampleDevice: CameraDeviceCapability {
        CameraDeviceCapability(
            id: "wide-camera",
            name: "Back Wide Camera",
            type: "builtInWideAngleCamera",
            position: "back",
            isVirtual: false,
            constituentDeviceIDs: [],
            focusModes: ["autoFocus", "continuousAutoFocus"],
            exposureModes: ["autoExpose"],
            supportsFocusPoint: true,
            supportsExposurePoint: true,
            minimumZoomFactor: 1,
            maximumZoomFactor: 8,
            formats: [
                CameraFormatCapability(
                    width: 1920,
                    height: 1080,
                    mediaSubtype: "420v",
                    fieldOfView: 70,
                    isVideoBinned: false,
                    supportsHDR: true,
                    autofocusSystem: "phaseDetection",
                    minimumISO: 20,
                    maximumISO: 2_000,
                    minimumExposureSeconds: 0.0001,
                    maximumExposureSeconds: 1,
                    maximumZoomFactor: 8,
                    frameRateRanges: [CameraFrameRateRange(minimum: 24, maximum: 60)],
                    stabilizationModes: ["off", "standard"]
                ),
            ]
        )
    }
}
