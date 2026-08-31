@testable import AICameraApp
import CoreGraphics
import XCTest

final class BirdFocusPolicyTests: XCTestCase {
    func testConfirmedTargetRequestsInitialFocus() {
        var policy = BirdFocusPolicy()

        let decision = policy.decision(for: confirmedResult(at: CGPoint(x: 0.4, y: 0.5)), at: 1)

        XCTAssertEqual(decision, .focus(at: CGPoint(x: 0.4, y: 0.5)))
    }

    func testMinimumIntervalPreventsRapidRefocus() {
        var policy = BirdFocusPolicy()
        _ = policy.decision(for: confirmedResult(at: CGPoint(x: 0.2, y: 0.2)), at: 1)

        let decision = policy.decision(for: confirmedResult(at: CGPoint(x: 0.8, y: 0.8)), at: 1.5)

        XCTAssertEqual(decision, .none)
    }

    func testMovementThresholdPreventsRefocusForStableTarget() {
        var policy = BirdFocusPolicy()
        _ = policy.decision(for: confirmedResult(at: CGPoint(x: 0.2, y: 0.2)), at: 1)

        let decision = policy.decision(for: confirmedResult(at: CGPoint(x: 0.22, y: 0.22)), at: 2)

        XCTAssertEqual(decision, .none)
    }

    func testMovedTargetRefocusesAfterMinimumInterval() {
        var policy = BirdFocusPolicy()
        _ = policy.decision(for: confirmedResult(at: CGPoint(x: 0.2, y: 0.2)), at: 1)

        let decision = policy.decision(for: confirmedResult(at: CGPoint(x: 0.5, y: 0.5)), at: 2)

        XCTAssertEqual(decision, .focus(at: CGPoint(x: 0.5, y: 0.5)))
    }

    func testManualFocusSuppressesAIUntilHoldExpires() {
        var policy = BirdFocusPolicy()
        policy.registerManualFocus(at: 1)

        XCTAssertEqual(
            policy.decision(for: confirmedResult(at: CGPoint(x: 0.4, y: 0.4)), at: 2),
            .none
        )
        XCTAssertEqual(
            policy.decision(for: confirmedResult(at: CGPoint(x: 0.4, y: 0.4)), at: 3),
            .focus(at: CGPoint(x: 0.4, y: 0.4))
        )
    }

    func testTemporaryLossDoesNotRefocusOrFallback() {
        var policy = BirdFocusPolicy()
        _ = policy.decision(for: confirmedResult(at: CGPoint(x: 0.4, y: 0.4)), at: 1)

        let decision = policy.decision(for: temporarilyLostResult(), at: 2)

        XCTAssertEqual(decision, .none)
    }

    func testConfirmedTargetLossResumesContinuousAutoFocusOnce() {
        var policy = BirdFocusPolicy()
        _ = policy.decision(for: confirmedResult(at: CGPoint(x: 0.4, y: 0.4)), at: 1)

        XCTAssertEqual(policy.decision(for: searchingResult(), at: 2), .resumeContinuousAutoFocus)
        XCTAssertEqual(policy.decision(for: searchingResult(), at: 3), .none)
    }

    func testManualFocusAlsoDefersContinuousAutoFocusFallback() {
        var policy = BirdFocusPolicy()
        _ = policy.decision(for: confirmedResult(at: CGPoint(x: 0.4, y: 0.4)), at: 1)
        policy.registerManualFocus(at: 2)

        XCTAssertEqual(policy.decision(for: searchingResult(), at: 3), .none)
        XCTAssertEqual(policy.decision(for: searchingResult(), at: 4), .resumeContinuousAutoFocus)
    }

    func testCoordinateMapperClampsAndMapsToLayerBounds() {
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 400)
        let imageSize = CGSize(width: 200, height: 400)

        XCTAssertEqual(
            BirdFocusCoordinateMapper.layerPoint(
                fromNormalizedImagePoint: CGPoint(x: 0.25, y: 0.75),
                imageSize: imageSize,
                in: bounds
            ),
            CGPoint(x: 60, y: 320)
        )
        XCTAssertEqual(
            BirdFocusCoordinateMapper.layerPoint(
                fromNormalizedImagePoint: CGPoint(x: -1, y: 2),
                imageSize: imageSize,
                in: bounds
            ),
            CGPoint(x: 10, y: 420)
        )
    }

    func testCoordinateMapperAccountsForAspectFillCrop() {
        let point = BirdFocusCoordinateMapper.layerPoint(
            fromNormalizedImagePoint: CGPoint(x: 0.5, y: 0.5),
            imageSize: CGSize(width: 400, height: 300),
            in: CGRect(x: 0, y: 0, width: 200, height: 400)
        )

        XCTAssertEqual(point.x, 100, accuracy: 0.0001)
        XCTAssertEqual(point.y, 200, accuracy: 0.0001)
    }

    func testCoordinateMapperUsesCenterForInvalidImageSize() {
        let point = BirdFocusCoordinateMapper.layerPoint(
            fromNormalizedImagePoint: CGPoint(x: 0.1, y: 0.2),
            imageSize: .zero,
            in: CGRect(x: 10, y: 20, width: 200, height: 400)
        )

        XCTAssertEqual(point, CGPoint(x: 110, y: 220))
    }

    private func confirmedResult(at point: CGPoint) -> MainTargetTrackingResult {
        MainTargetTrackingResult(
            observation: BirdObservation(
                boundingBox: CGRect(x: point.x - 0.1, y: point.y - 0.1, width: 0.2, height: 0.2),
                confidence: 0.8
            ),
            focusPoint: point,
            state: .confirmed
        )
    }

    private func temporarilyLostResult() -> MainTargetTrackingResult {
        MainTargetTrackingResult(
            observation: nil,
            focusPoint: nil,
            state: .temporarilyLost(currentFrame: 1, toleratedFrames: 2)
        )
    }

    private func searchingResult() -> MainTargetTrackingResult {
        MainTargetTrackingResult(observation: nil, focusPoint: nil, state: .searching)
    }
}
