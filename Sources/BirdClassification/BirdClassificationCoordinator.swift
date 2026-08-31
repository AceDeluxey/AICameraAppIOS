import CoreVideo
import Foundation

actor BirdClassificationCoordinator {
    private let classifier: any BirdClassifying
    private let minimumInterval: TimeInterval
    private let requiredStableResults: Int

    private var isProcessing = false
    private var lastAcceptedTimestamp: TimeInterval?
    private var displayed: [BirdClassification] = []
    private var pendingIdentifier: String?
    private var pendingCount = 0
    private var generation = 0

    init(
        classifier: any BirdClassifying,
        minimumInterval: TimeInterval = 1,
        requiredStableResults: Int = 2
    ) {
        precondition(requiredStableResults > 0)
        self.classifier = classifier
        self.minimumInterval = max(0, minimumInterval)
        self.requiredStableResults = requiredStableResults
    }

    func submit(
        pixelBuffer: CVPixelBuffer,
        birdBoundingBox: CGRect,
        presentationTimeSeconds: TimeInterval
    ) async throws -> [BirdClassification]? {
        guard !isProcessing, shouldAccept(presentationTimeSeconds) else { return nil }

        isProcessing = true
        lastAcceptedTimestamp = presentationTimeSeconds
        defer { isProcessing = false }
        let submittedGeneration = generation

        let candidates = try await classifier.classify(
            pixelBuffer,
            birdBoundingBox: birdBoundingBox
        )
        guard submittedGeneration == generation else { return nil }
        return consume(candidates)
    }

    func reset() {
        lastAcceptedTimestamp = nil
        displayed = []
        pendingIdentifier = nil
        pendingCount = 0
        generation += 1
    }

    private func shouldAccept(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp, timestamp >= lastAcceptedTimestamp else { return true }
        return timestamp - lastAcceptedTimestamp >= minimumInterval
    }

    private func consume(_ candidates: [BirdClassification]) -> [BirdClassification] {
        guard let top = candidates.first else {
            displayed = []
            pendingIdentifier = nil
            pendingCount = 0
            return []
        }

        if pendingIdentifier == top.identifier {
            pendingCount += 1
        } else {
            pendingIdentifier = top.identifier
            pendingCount = 1
        }

        if displayed.isEmpty || displayed.first?.identifier == top.identifier
            || pendingCount >= requiredStableResults {
            displayed = Array(candidates.prefix(3))
        }
        return displayed
    }
}
