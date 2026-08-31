import AVFoundation
import Foundation

extension CameraSessionController {
    func configureBirdDetectionIfAvailable() {
        guard isBirdModeEnabled else { return }
        if birdDetectionCoordinator == nil {
            do {
                let detector = try BirdDetectionRuntimeFactory.loadBundledDetector()
                birdDetectionCoordinator = BirdDetectionCoordinator(
                    detector: detector,
                    timeline: diagnosticsTimeline,
                    minimumInterval: CameraLoadPolicy.detectionInterval(
                        for: ProcessInfo.processInfo.thermalState
                    )
                )
            } catch {
                frameOutput.frameHandler = nil
                Task { @MainActor in
                    self.birdBoundingBox = nil
                    self.birdModeStatus = .unavailable(error.localizedDescription)
                }
                return
            }
        }

        frameOutput.frameHandler = { [weak self] frame in
            self?.processBirdFrame(frame)
        }
        Task { @MainActor in self.birdModeStatus = .searching }
    }

    func processBirdFrame(_ frame: CameraFrame) {
        guard isBirdModeEnabled, let birdDetectionCoordinator else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let result = try await birdDetectionCoordinator.process(frame) else { return }
                await publishBirdResult(
                    result,
                    imageSize: CGSize(
                        width: CVPixelBufferGetWidth(frame.pixelBuffer),
                        height: CVPixelBufferGetHeight(frame.pixelBuffer)
                    )
                )
                sessionQueue.async { [weak self] in
                    self?.applyBirdFocusDecision(result.focusDecision)
                }
            } catch {
                await publishBirdFailure(error)
            }
        }
    }

    @MainActor
    func publishBirdResult(_ result: BirdFocusPipelineResult, imageSize: CGSize) {
        birdBoundingBox = result.trackingResult.observation?.boundingBox
        birdImageSize = imageSize
        switch result.trackingResult.state {
        case .searching:
            birdModeStatus = .searching
        case .confirming:
            birdModeStatus = .confirming
        case .confirmed:
            birdModeStatus = .locked(
                confidence: result.trackingResult.observation?.confidence ?? 0
            )
        case .temporarilyLost:
            birdModeStatus = .temporarilyLost
        }
    }

    @MainActor
    func publishBirdFailure(_ error: any Error) {
        birdBoundingBox = nil
        birdModeStatus = .failed(error.localizedDescription)
        DiagnosticsLogger.detection.error(
            "Bird detection failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    func applyBirdFocusDecision(_ decision: BirdFocusDecision) {
        guard let activeDevice else { return }
        do {
            switch decision {
            case .none:
                return
            case let .focus(point):
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                if activeDevice.isFocusPointOfInterestSupported {
                    activeDevice.focusPointOfInterest = point
                }
                if activeDevice.isFocusModeSupported(.autoFocus) {
                    activeDevice.focusMode = .autoFocus
                }
            case .resumeContinuousAutoFocus:
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                if activeDevice.isFocusModeSupported(.continuousAutoFocus) {
                    activeDevice.focusMode = .continuousAutoFocus
                }
            }
        } catch {
            Task { @MainActor in self.birdModeStatus = .failed(error.localizedDescription) }
        }
    }
}
