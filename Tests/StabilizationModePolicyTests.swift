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
}
