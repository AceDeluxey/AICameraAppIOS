@testable import AICameraApp
import AVFoundation
import XCTest

final class StabilizationModePolicyTests: XCTestCase {
    func testUsesRequestedSupportedMode() {
        let capability = StabilizationCapability(supportedModes: [.off, .auto, .cinematic])

        let mode = StabilizationModePolicy.preferredMode(
            for: .cinematic,
            capability: capability
        )

        XCTAssertEqual(mode, .cinematic)
    }

    func testUnsupportedInternalModeFallsBackToAuto() {
        let capability = StabilizationCapability(supportedModes: [.off, .standard, .auto])

        let mode = StabilizationModePolicy.preferredMode(
            for: .cinematicExtended,
            capability: capability
        )

        XCTAssertEqual(mode, .auto)
    }

    func testAutomaticFallsBackToStandard() {
        let capability = StabilizationCapability(supportedModes: [.off, .standard])

        let mode = StabilizationModePolicy.preferredMode(
            for: .automatic,
            capability: capability
        )

        XCTAssertEqual(mode, .standard)
    }

    func testOffNeverFallsForwardToAnotherMode() {
        let capability = StabilizationCapability(supportedModes: [.standard, .auto])

        let mode = StabilizationModePolicy.preferredMode(for: .off, capability: capability)

        XCTAssertEqual(mode, .off)
    }

    func testOnlyOffAndAutomaticArePublicModes() {
        let publicModes = StabilizationModeSelection.allCases.filter(\.isPublicMode)

        XCTAssertEqual(publicModes, [.off, .automatic])
    }

    func testResultDescriptionIncludesRequestedPreferredAndActiveModes() {
        let result = StabilizationApplicationResult(
            requestedMode: .cinematic,
            preferredMode: .auto,
            activeMode: .standard,
            usedFallback: true
        )

        XCTAssertTrue(result.textDescription.contains("请求：电影级（内部）"))
        XCTAssertTrue(result.textDescription.contains("首选：auto"))
        XCTAssertTrue(result.textDescription.contains("实际：standard"))
        XCTAssertTrue(result.textDescription.contains("降级：是"))
    }
}
