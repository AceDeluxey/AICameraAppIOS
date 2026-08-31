import AVFoundation
import Foundation

extension CameraSessionController {
    func configureBirdDetectionIfAvailable() {
        guard isBirdModeEnabled, movieOutput?.isRecording != true else { return }
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
        configureBirdClassificationIfAvailable()

        frameOutput.frameHandler = { [weak self] frame in
            self?.processBirdFrame(frame)
        }
        Task { @MainActor in self.birdModeStatus = .searching }
    }

    func processBirdFrame(_ frame: CameraFrame) {
        guard isBirdModeEnabled,
              movieOutput?.isRecording != true,
              let birdDetectionCoordinator
        else { return }
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
                if case .confirmed = result.trackingResult.state, let observation = result.trackingResult.observation {
                    await classifyBird(
                        in: frame,
                        boundingBox: observation.boundingBox
                    )
                } else if case .searching = result.trackingResult.state {
                    await clearBirdClassification()
                }
                sessionQueue.async { [weak self] in
                    self?.applyBirdFocusDecision(result.focusDecision)
                }
            } catch {
                await publishBirdFailure(error)
            }
        }
    }

    func configureBirdClassificationIfAvailable() {
        if birdClassificationCoordinator != nil {
            Task { @MainActor in self.birdClassificationStatus = .searching }
            return
        }
        guard !birdClassificationSetupAttempted else { return }
        birdClassificationSetupAttempted = true
        do {
            configureBirdRegionPriorIfAvailable()
            let classifier = try BirdClassificationRuntimeFactory.loadBundledClassifier(
                prior: birdRegionPrior
            )
            birdClassificationCoordinator = BirdClassificationCoordinator(classifier: classifier)
            Task { @MainActor in self.birdClassificationStatus = .searching }
        } catch {
            birdClassificationCoordinator = nil
            Task { @MainActor in self.birdClassificationStatus = .unavailable }
            DiagnosticsLogger.detection.info(
                "Bird classification unavailable: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func configureBirdRegionPriorIfAvailable() {
        guard !birdRegionPriorSetupAttempted else { return }
        birdRegionPriorSetupAttempted = true
        do {
            birdRegionPrior = try BirdRegionPrior.loadBundled()
        } catch {
            birdRegionPrior = nil
            DiagnosticsLogger.detection.info(
                "Bird region prior unavailable: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func refreshBirdRecognitionLocationIfNeeded() {
        guard isBirdModeEnabled, usesLocationForBirdRecognition else {
            birdRegionPrior?.clear()
            return
        }
        configureBirdRegionPriorIfAvailable()
        guard let birdRegionPrior else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let location = await photoLocationProvider.currentLocation() else {
                birdRegionPrior.clear()
                return
            }
            birdRegionPrior.update(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                month: Calendar.current.component(.month, from: Date())
            )
        }
    }

    func classifyBird(in frame: CameraFrame, boundingBox: CGRect) async {
        guard let birdClassificationCoordinator else { return }
        do {
            guard let candidates = try await birdClassificationCoordinator.submit(
                pixelBuffer: frame.pixelBuffer,
                birdBoundingBox: boundingBox,
                presentationTimeSeconds: frame.presentationTimeSeconds
            ) else { return }
            await MainActor.run {
                self.birdClassificationStatus = candidates.isEmpty
                    ? .searching : .candidates(candidates)
            }
        } catch {
            await MainActor.run {
                self.birdClassificationStatus = .failed(error.localizedDescription)
            }
            DiagnosticsLogger.detection.error(
                "Bird classification failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @MainActor
    func clearBirdClassification() async {
        birdClassificationStatus = birdClassificationCoordinator == nil ? .unavailable : .searching
        await birdClassificationCoordinator?.reset()
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
        birdClassificationStatus = birdClassificationCoordinator == nil ? .unavailable : .searching
        DiagnosticsLogger.detection.error(
            "Bird detection failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    func applyBirdFocusDecision(_ decision: BirdFocusDecision) {
        guard controlMode == .automatic, let activeDevice else { return }
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
