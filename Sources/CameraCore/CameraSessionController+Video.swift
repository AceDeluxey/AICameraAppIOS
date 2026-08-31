import AVFoundation
import Foundation

extension CameraSessionController {
    @MainActor
    func setCaptureMode(_ mode: CameraCaptureMode) {
        guard !videoRecordingStatus.isBusy else { return }
        captureMode = mode
        clearCaptureMessage()
        clearVideoMessage()
        sessionQueue.async { [weak self] in
            self?.applyStabilization()
        }
    }

    @MainActor
    func toggleVideoRecording() {
        if videoRecordingStatus.isRecording {
            sessionQueue.async { [weak self] in
                self?.movieOutput?.stopRecording()
            }
        } else {
            prepareVideoRecording()
        }
    }

    @MainActor
    func clearVideoMessage() {
        guard !videoRecordingStatus.isBusy else { return }
        videoRecordingStatus = .idle
    }

    @MainActor
    private func prepareVideoRecording() {
        guard state == .running,
              captureMode == .video,
              !videoRecordingStatus.isBusy
        else { return }

        videoRecordingStatus = .preparing
        Task { [weak self] in
            let audioAuthorized = await Self.requestMicrophoneAccess()
            self?.sessionQueue.async { [weak self] in
                self?.beginVideoRecording(includeAudio: audioAuthorized)
            }
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private func beginVideoRecording(includeAudio: Bool) {
        guard let movieOutput, !movieOutput.isRecording else {
            Task { @MainActor in
                videoRecordingStatus = .failed("视频录制输出尚未就绪")
            }
            return
        }

        do {
            let audioEnabled = try configureAudioInputIfNeeded(includeAudio: includeAudio)
            configureMovieConnection(movieOutput)
            pauseBirdDetectionForVideo()

            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            let processor = VideoRecordingProcessor(
                didStart: { [weak self] in
                    Task { @MainActor in
                        self?.videoRecordingStatus = .recording(startedAt: Date())
                        self?.isRecordingAudioEnabled = audioEnabled
                    }
                },
                completion: { [weak self] result in
                    self?.finishVideoRecording(result)
                }
            )
            videoRecordingProcessor = processor
            movieOutput.startRecording(to: fileURL, recordingDelegate: processor)
        } catch {
            resumeBirdDetectionAfterVideo()
            Task { @MainActor in
                self.videoRecordingStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func configureAudioInputIfNeeded(includeAudio: Bool) throws -> Bool {
        guard includeAudio else { return false }
        if audioInput != nil {
            return true
        }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            return false
        }

        let input = try AVCaptureDeviceInput(device: microphone)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        audioInput = input
        return true
    }

    private func configureMovieConnection(_ movieOutput: AVCaptureMovieFileOutput) {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if let activeDevice {
            _ = stabilizationController.apply(
                requestedStabilizationMode,
                to: connection,
                device: activeDevice
            )
        }
    }

    private func finishVideoRecording(_ result: Result<URL, any Error>) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            videoRecordingProcessor = nil
            isRecordingAudioEnabled = false

            switch result {
            case let .success(fileURL):
                videoRecordingStatus = .saving
                defer { try? FileManager.default.removeItem(at: fileURL) }
                do {
                    try await photoLibrary.saveVideo(at: fileURL)
                    videoRecordingStatus = .saved
                } catch {
                    videoRecordingStatus = .failed(error.localizedDescription)
                }
            case let .failure(error):
                videoRecordingStatus = .failed(error.localizedDescription)
            }

            sessionQueue.async { [weak self] in
                self?.completeVideoSessionCleanup()
            }
        }
    }

    private func pauseBirdDetectionForVideo() {
        frameOutput.frameHandler = nil
        Task { @MainActor in
            birdBoundingBox = nil
            if isBirdModeEnabled {
                birdModeStatus = .pausedForRecording
            }
        }
    }

    private func resumeBirdDetectionAfterVideo() {
        guard isBirdModeEnabled else { return }
        configureBirdDetectionIfAvailable()
    }

    private func completeVideoSessionCleanup() {
        if stopsSessionAfterRecording {
            stopsSessionAfterRecording = false
            if session.isRunning {
                session.stopRunning()
            }
        } else {
            resumeBirdDetectionAfterVideo()
        }
    }
}
