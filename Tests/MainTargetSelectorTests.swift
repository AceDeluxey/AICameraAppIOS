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

    func testStrongObservationConfirmsImmediately() {
        var tracker = MainTargetTracker()
        let observation = makeObservation(confidence: 0.8)

        let result = tracker.update(with: [observation])

        XCTAssertEqual(result.state, .confirmed)
        XCTAssertEqual(result.observation, observation)
        XCTAssertEqual(result.focusPoint?.x ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(result.focusPoint?.y ?? -1, 0.3, accuracy: 0.0001)
    }

    func testWeakObservationRequiresConsecutiveMatchingFrames() {
        var tracker = MainTargetTracker()
        let first = makeObservation(x: 0.10, confidence: 0.4)
        let second = makeObservation(x: 0.12, confidence: 0.45)
        let third = makeObservation(x: 0.14, confidence: 0.5)

        XCTAssertEqual(
            tracker.update(with: [first]).state,
            .confirming(currentFrame: 1, requiredFrames: 3)
        )
        XCTAssertEqual(
            tracker.update(with: [second]).state,
            .confirming(currentFrame: 2, requiredFrames: 3)
        )

        let confirmed = tracker.update(with: [third])
        XCTAssertEqual(confirmed.state, .confirmed)
        XCTAssertNotNil(confirmed.observation)
    }

    func testDifferentWeakTargetRestartsConfirmation() {
        var tracker = MainTargetTracker()
        let first = makeObservation(x: 0.05, confidence: 0.4)
        let different = makeObservation(x: 0.7, confidence: 0.5)

        _ = tracker.update(with: [first])
        let result = tracker.update(with: [different])

        XCTAssertEqual(result.state, .confirming(currentFrame: 1, requiredFrames: 3))
        XCTAssertNil(result.observation)
    }

    func testLowConfidenceOrMissingTargetReturnsToSearching() {
        var tracker = MainTargetTracker()
        _ = tracker.update(with: [makeObservation(confidence: 0.8)])

        let lowConfidence = tracker.update(with: [makeObservation(confidence: 0.2)])
        XCTAssertEqual(lowConfidence.state, .searching)
        XCTAssertNil(lowConfidence.observation)
        XCTAssertNil(lowConfidence.focusPoint)

        let missing = tracker.update(with: [])
        XCTAssertEqual(missing.state, .searching)
    }

    func testConfirmedBoxIsSmoothedAcrossFrames() throws {
        let configuration = MainTargetTrackingConfiguration(smoothingFactor: 0.5)
        var tracker = MainTargetTracker(configuration: configuration)

        _ = tracker.update(with: [makeObservation(x: 0.1, confidence: 0.8)])
        let result = tracker.update(with: [makeObservation(x: 0.2, confidence: 0.8)])
        let box = try XCTUnwrap(result.observation?.boundingBox)

        XCTAssertEqual(box.minX, 0.15, accuracy: 0.0001)
        XCTAssertEqual(box.width, 0.4, accuracy: 0.0001)
    }

    func testHighestConfidenceObservationDrivesTracker() throws {
        var tracker = MainTargetTracker()
        let lower = makeObservation(x: 0.1, confidence: 0.7)
        let higher = makeObservation(x: 0.5, confidence: 0.9)

        let result = tracker.update(with: [lower, higher])

        XCTAssertEqual(try XCTUnwrap(result.observation), higher)
    }

    func testStrongDifferentTargetDoesNotSmoothAcrossTargets() throws {
        var tracker = MainTargetTracker()
        _ = tracker.update(with: [makeObservation(x: 0.05, confidence: 0.8)])
        let different = makeObservation(x: 0.55, confidence: 0.9)

        let result = tracker.update(with: [different])

        XCTAssertEqual(try XCTUnwrap(result.observation), different)
    }

    private func makeObservation(
        x: CGFloat = 0.1,
        y: CGFloat = 0.1,
        width: CGFloat = 0.4,
        height: CGFloat = 0.4,
        confidence: Float
    ) -> BirdObservation {
        BirdObservation(
            boundingBox: CGRect(x: x, y: y, width: width, height: height),
            confidence: confidence
        )
    }
}
