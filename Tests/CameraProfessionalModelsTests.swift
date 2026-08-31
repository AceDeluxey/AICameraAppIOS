@testable import AICameraApp
import XCTest

final class CameraProfessionalModelsTests: XCTestCase {
    func testSettingsAreConstrainedToDeviceCapabilities() {
        let capabilities = CameraProfessionalCapabilities(
            exposureBiasRange: -2 ... 2,
            isoRange: 50 ... 800,
            exposureDurationRange: 1 / 8_000 ... 1,
            supportsManualFocus: true
        )
        let settings = CameraProfessionalSettings(
            exposureBias: 4,
            iso: 1_600,
            exposureDuration: 2,
            lensPosition: -1
        ).constrained(to: capabilities)

        XCTAssertEqual(settings.exposureBias, 2)
        XCTAssertEqual(settings.iso, 800)
        XCTAssertEqual(settings.exposureDuration, 1)
        XCTAssertEqual(settings.lensPosition, 0)
    }

    func testProfessionalModeRequiresAtLeastOneManualControl() {
        let unavailable = CameraProfessionalCapabilities(
            exposureBiasRange: -2 ... 2,
            isoRange: nil,
            exposureDurationRange: nil,
            supportsManualFocus: false
        )
        let available = CameraProfessionalCapabilities(
            exposureBiasRange: nil,
            isoRange: nil,
            exposureDurationRange: nil,
            supportsManualFocus: true
        )

        XCTAssertFalse(unavailable.supportsProfessionalMode)
        XCTAssertTrue(available.supportsProfessionalMode)

        let incompleteExposure = CameraProfessionalCapabilities(
            exposureBiasRange: nil,
            isoRange: 50 ... 800,
            exposureDurationRange: nil,
            supportsManualFocus: false
        )
        XCTAssertFalse(incompleteExposure.supportsProfessionalMode)
    }

    func testLogarithmicScaleRoundTripsExposureDuration() {
        let range = 1 / 8_000.0 ... 1.0
        let duration = 1 / 125.0
        let normalized = CameraProfessionalScale.normalized(duration, in: range)

        XCTAssertEqual(CameraProfessionalScale.value(normalized, in: range), duration, accuracy: 0.000_001)
    }

    func testLogarithmicScaleConstrainsOutOfRangeValues() {
        let range = 50.0 ... 1_600.0

        XCTAssertEqual(CameraProfessionalScale.normalized(10, in: range), 0, accuracy: 0.000_001)
        XCTAssertEqual(CameraProfessionalScale.value(2, in: range), 1_600, accuracy: 0.000_001)
    }

    func testProfessionalValueFormatting() {
        XCTAssertEqual(CameraProfessionalFormatter.exposureBias(0.7), "+0.7 EV")
        XCTAssertEqual(CameraProfessionalFormatter.iso(199.6), "ISO 200")
        XCTAssertEqual(CameraProfessionalFormatter.shutter(1 / 250), "1/250 s")
        XCTAssertEqual(CameraProfessionalFormatter.focus(1), "∞")
    }
}
