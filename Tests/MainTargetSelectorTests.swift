@testable import AICameraApp
import CoreGraphics
import XCTest

final class MainTargetSelectorTests: XCTestCase {
    func testSelectsHighestConfidenceObservation() {
        let low = BirdObservation(
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            confidence: 0.4
        )
        let high = BirdObservation(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
            confidence: 0.9
        )

        XCTAssertEqual(MainTargetSelector().select(from: [low, high]), high)
    }

    func testReturnsNilForEmptyObservations() {
        XCTAssertNil(MainTargetSelector().select(from: []))
    }
}
