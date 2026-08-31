import Foundation

extension CameraSessionController {
    @MainActor
    func setBirdModeEnabled(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isBirdModeEnabled = enabled
            if enabled {
                configureBirdDetectionIfAvailable()
                refreshBirdRecognitionLocationIfNeeded()
            } else {
                frameOutput.frameHandler = nil
                if let birdDetectionCoordinator {
                    Task { await birdDetectionCoordinator.reset() }
                }
                if let birdClassificationCoordinator {
                    Task { await birdClassificationCoordinator.reset() }
                }
                Task { @MainActor in
                    self.birdBoundingBox = nil
                    self.birdModeStatus = .disabled
                    self.birdClassificationStatus = .unavailable
                }
            }
        }
    }

    @MainActor
    func setUsesLocationForBirdRecognition(_ enabled: Bool) {
        usesLocationForBirdRecognition = enabled
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                refreshBirdRecognitionLocationIfNeeded()
            } else {
                birdRegionPrior?.clear()
            }
        }
    }
}
