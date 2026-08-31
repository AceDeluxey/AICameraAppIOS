import Foundation

actor BirdDetectionCoordinator {
    private let scheduler: BirdDetectionScheduler
    private let focusPipeline: BirdFocusPipeline

    init(
        detector: any BirdDetecting,
        timeline: DiagnosticsTimeline,
        minimumInterval: TimeInterval = 0.1
    ) {
        scheduler = BirdDetectionScheduler(
            detector: detector,
            minimumInterval: minimumInterval
        )
        focusPipeline = BirdFocusPipeline(timeline: timeline)
    }

    func process(_ frame: CameraFrame) async throws -> BirdFocusPipelineResult? {
        let clock = ContinuousClock()
        let startedAt = clock.now
        guard let observations = try await scheduler.submit(
            pixelBuffer: frame.pixelBuffer,
            presentationTimeSeconds: frame.presentationTimeSeconds
        ) else {
            return nil
        }
        let duration = startedAt.duration(to: clock.now)
        let milliseconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        return await focusPipeline.process(
            observations: observations,
            presentationTimeSeconds: frame.presentationTimeSeconds,
            detectionDurationMilliseconds: milliseconds
        )
    }

    func registerManualFocus(at timestamp: TimeInterval) async {
        await focusPipeline.registerManualFocus(at: timestamp)
    }

    func setMinimumInterval(_ interval: TimeInterval) async {
        await scheduler.setMinimumInterval(interval)
    }

    func reset() async {
        await focusPipeline.reset()
    }
}
