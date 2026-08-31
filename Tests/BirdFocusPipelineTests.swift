@testable import AICameraApp
import XCTest

final class BirdFocusPipelineTests: XCTestCase {
    func testRecordsDetectionBeforeFocusRequest() async {
        let timeline = DiagnosticsTimeline()
        let pipeline = BirdFocusPipeline(timeline: timeline)

        let result = await pipeline.process(
            observations: [observation(confidence: 0.8)],
            presentationTimeSeconds: 1,
            detectionDurationMilliseconds: 24
        )

        XCTAssertEqual(result.focusDecision, .focus(at: CGPoint(x: 0.5, y: 0.5)))
        let events = await timeline.snapshot()
        XCTAssertEqual(events.map(\.kind), [.detectionCompleted, .focusRequested])
        XCTAssertEqual(events.first?.durationMilliseconds, 24)
        XCTAssertEqual(events.first?.details, "observations=1")
    }

    func testTemporaryLossOnlyRecordsLossAfterToleranceExpires() async {
        let timeline = DiagnosticsTimeline()
        let pipeline = BirdFocusPipeline(timeline: timeline)
        _ = await pipeline.process(
            observations: [observation(confidence: 0.8)],
            presentationTimeSeconds: 1,
            detectionDurationMilliseconds: 10
        )

        for timestamp in [2.0, 3.0] {
            _ = await pipeline.process(
                observations: [],
                presentationTimeSeconds: timestamp,
                detectionDurationMilliseconds: 10
            )
        }
        let temporaryLossEvents = await timeline.snapshot()
        XCTAssertFalse(temporaryLossEvents.contains { $0.kind == .targetLost })

        let result = await pipeline.process(
            observations: [],
            presentationTimeSeconds: 4,
            detectionDurationMilliseconds: 10
        )

        XCTAssertEqual(result.focusDecision, .resumeContinuousAutoFocus)
        let events = await timeline.snapshot()
        XCTAssertEqual(events.filter { $0.kind == .targetLost }.count, 1)
    }

    func testRecordsFocusCompletionOnlyForPendingRequest() async {
        let timeline = DiagnosticsTimeline()
        let pipeline = BirdFocusPipeline(timeline: timeline)

        await pipeline.recordFocusCompleted(durationMilliseconds: 8)
        _ = await pipeline.process(
            observations: [observation(confidence: 0.8)],
            presentationTimeSeconds: 1,
            detectionDurationMilliseconds: 10
        )
        await pipeline.recordFocusCompleted(durationMilliseconds: 42)
        await pipeline.recordFocusCompleted(durationMilliseconds: 50)

        let completions = await timeline.snapshot().filter { $0.kind == .focusCompleted }
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.durationMilliseconds, 42)
    }

    func testRecordsFocusFailureAndClearsPendingRequest() async {
        let timeline = DiagnosticsTimeline()
        let pipeline = BirdFocusPipeline(timeline: timeline)
        _ = await pipeline.process(
            observations: [observation(confidence: 0.8)],
            presentationTimeSeconds: 1,
            detectionDurationMilliseconds: 10
        )

        await pipeline.recordFocusFailure("device busy")
        await pipeline.recordFocusCompleted()

        let events = await timeline.snapshot()
        XCTAssertEqual(events.map(\.kind), [.detectionCompleted, .focusRequested, .error])
        XCTAssertEqual(events.last?.details, "focus: device busy")
    }

    func testManualFocusProtectionFlowsThroughPipeline() async {
        let timeline = DiagnosticsTimeline()
        let pipeline = BirdFocusPipeline(timeline: timeline)
        await pipeline.registerManualFocus(at: 1)

        let protected = await pipeline.process(
            observations: [observation(confidence: 0.8)],
            presentationTimeSeconds: 2,
            detectionDurationMilliseconds: 10
        )
        let released = await pipeline.process(
            observations: [observation(originX: 0.7, confidence: 0.8)],
            presentationTimeSeconds: 3,
            detectionDurationMilliseconds: 10
        )

        XCTAssertEqual(protected.focusDecision, .none)
        guard case let .focus(point) = released.focusDecision else {
            return XCTFail("Expected focus decision")
        }
        XCTAssertEqual(point.x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.0001)
    }

    private func observation(originX: CGFloat = 0.4, confidence: Float) -> BirdObservation {
        BirdObservation(
            boundingBox: CGRect(x: originX, y: 0.4, width: 0.2, height: 0.2),
            confidence: confidence
        )
    }
}
