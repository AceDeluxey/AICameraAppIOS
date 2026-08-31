import Foundation

struct BirdFocusPipelineResult: Equatable, Sendable {
    let trackingResult: MainTargetTrackingResult
    let focusDecision: BirdFocusDecision
}

actor BirdFocusPipeline {
    private var tracker: MainTargetTracker
    private var focusPolicy: BirdFocusPolicy
    private let timeline: DiagnosticsTimeline
    private var retainedTarget = false
    private var pendingFocusRequest = false

    init(
        tracker: MainTargetTracker = MainTargetTracker(),
        focusPolicy: BirdFocusPolicy = BirdFocusPolicy(),
        timeline: DiagnosticsTimeline
    ) {
        self.tracker = tracker
        self.focusPolicy = focusPolicy
        self.timeline = timeline
    }

    func process(
        observations: [BirdObservation],
        presentationTimeSeconds: TimeInterval,
        detectionDurationMilliseconds: Double
    ) async -> BirdFocusPipelineResult {
        await timeline.record(
            DiagnosticsEvent(
                kind: .detectionCompleted,
                durationMilliseconds: max(0, detectionDurationMilliseconds),
                details: "observations=\(observations.count)"
            )
        )

        let trackingResult = tracker.update(with: observations)
        let currentlyRetained = trackingResult.retainsTarget
        if retainedTarget, !currentlyRetained {
            await timeline.record(DiagnosticsEvent(kind: .targetLost))
        }
        retainedTarget = currentlyRetained

        let focusDecision = focusPolicy.decision(
            for: trackingResult,
            at: presentationTimeSeconds
        )
        if case let .focus(point) = focusDecision {
            pendingFocusRequest = true
            await timeline.record(
                DiagnosticsEvent(
                    kind: .focusRequested,
                    details: String(format: "x=%.4f,y=%.4f", point.x, point.y)
                )
            )
        }

        return BirdFocusPipelineResult(
            trackingResult: trackingResult,
            focusDecision: focusDecision
        )
    }

    func registerManualFocus(at timestamp: TimeInterval) {
        focusPolicy.registerManualFocus(at: timestamp)
    }

    func recordFocusCompleted(durationMilliseconds: Double? = nil) async {
        guard pendingFocusRequest else { return }
        pendingFocusRequest = false
        await timeline.record(
            DiagnosticsEvent(
                kind: .focusCompleted,
                durationMilliseconds: durationMilliseconds.map { max(0, $0) }
            )
        )
    }

    func recordFocusFailure(_ description: String) async {
        guard pendingFocusRequest else { return }
        pendingFocusRequest = false
        await timeline.record(
            DiagnosticsEvent(kind: .error, details: "focus: \(description)")
        )
    }

    func reset() {
        tracker.reset()
        focusPolicy.reset()
        retainedTarget = false
        pendingFocusRequest = false
    }
}

private extension MainTargetTrackingResult {
    var retainsTarget: Bool {
        switch state {
        case .confirmed, .temporarilyLost:
            true
        case .searching, .confirming:
            false
        }
    }
}
