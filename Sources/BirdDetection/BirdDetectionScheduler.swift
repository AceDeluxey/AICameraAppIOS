import CoreVideo
import Foundation

actor BirdDetectionScheduler {
    private let detector: any BirdDetecting
    private let minimumInterval: TimeInterval

    private var isProcessing = false
    private var lastAcceptedTimestamp: TimeInterval?

    init(detector: any BirdDetecting, minimumInterval: TimeInterval = 0.1) {
        self.detector = detector
        self.minimumInterval = max(0, minimumInterval)
    }

    func submit(
        pixelBuffer: CVPixelBuffer,
        presentationTimeSeconds: TimeInterval
    ) async throws -> [BirdObservation]? {
        guard !isProcessing else { return nil }

        if shouldThrottle(presentationTimeSeconds) {
            return nil
        }

        isProcessing = true
        lastAcceptedTimestamp = presentationTimeSeconds
        defer { isProcessing = false }

        return try await detector.detectBirds(in: pixelBuffer)
    }

    private func shouldThrottle(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp, timestamp >= lastAcceptedTimestamp else {
            return false
        }
        return timestamp - lastAcceptedTimestamp < minimumInterval
    }
}
