import AVFoundation
import Combine
import Foundation
import UIKit

final class CameraSessionController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case configuring
        case running
        case unauthorized
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var capabilityReport: CameraCapabilityReport?
    @Published var stabilizationResult: StabilizationApplicationResult?
    @Published var availableLenses: [CameraLensOption] = []
    @Published var activeLensID: String?
    @Published var zoomFactor: CGFloat = 1
    @Published var zoomRange: ClosedRange<CGFloat> = 1 ... 1
    @Published var captureStatus: CameraCaptureStatus = .idle
    @Published var latestThumbnail: UIImage?
    @Published var focusPoint: CGPoint?
    @Published var interruptionMessage: String?
    @Published var birdBoundingBox: CGRect?
    @Published var birdImageSize: CGSize = .zero
    @Published var birdModeStatus = BirdModeStatus.disabled
    @Published var aspectRatio: PhotoAspectRatio = .fourByThree
    @Published var includesLocationMetadata: Bool {
        didSet {
            UserDefaults.standard.set(includesLocationMetadata, forKey: Self.locationPreferenceKey)
        }
    }

    @Published var thermalState = ProcessInfo.processInfo.thermalState

    let session = AVCaptureSession()

    let sessionQueue = DispatchQueue(label: "com.acedeluxey.aicamera.camera-session")
    let capabilityProbe = CameraCapabilityProbe()
    let frameOutput = CameraFrameOutput()
    let stabilizationController = CameraStabilizationController()
    let photoLibrary = PhotoLibraryService()
    let photoLocationProvider = PhotoLocationProvider()
    var isConfigured = false
    var activeDeviceID: String?
    var activeDevice: AVCaptureDevice?
    var activeInput: AVCaptureDeviceInput?
    var photoOutput: AVCapturePhotoOutput?
    var photoProcessors: [Int64: PhotoCaptureProcessor] = [:]
    var requestedStabilizationMode = StabilizationModeSelection.automatic
    var notificationTokens: [NSObjectProtocol] = []
    let diagnosticsTimeline = DiagnosticsTimeline()
    var birdDetectionCoordinator: BirdDetectionCoordinator?
    var isBirdModeEnabled = false
    static let locationPreferenceKey = "includesPhotoLocationMetadata"

    init() {
        includesLocationMetadata = UserDefaults.standard.bool(forKey: Self.locationPreferenceKey)
        observeSessionNotifications()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    @MainActor
    func start() async {
        guard state != .running else { return }
        state = .requestingPermission

        let granted = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }

        guard granted else {
            state = .unauthorized
            return
        }

        state = .configuring
        configureAndStart()
    }

    @MainActor
    func stop() {
        state = .idle
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    @MainActor
    func focus(at devicePoint: CGPoint) {
        focusPoint = devicePoint
        let timestamp = CACurrentMediaTime()
        if let birdDetectionCoordinator {
            Task { await birdDetectionCoordinator.registerManualFocus(at: timestamp) }
        }
        sessionQueue.async { [weak self] in
            guard let self, let activeDevice else { return }
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                let point = CGPoint(
                    x: min(max(devicePoint.x, 0), 1),
                    y: min(max(devicePoint.y, 0), 1)
                )
                if activeDevice.isFocusPointOfInterestSupported {
                    activeDevice.focusPointOfInterest = point
                }
                if activeDevice.isFocusModeSupported(.autoFocus) {
                    activeDevice.focusMode = .autoFocus
                }
                if activeDevice.isExposurePointOfInterestSupported {
                    activeDevice.exposurePointOfInterest = point
                }
                if activeDevice.isExposureModeSupported(.continuousAutoExposure) {
                    activeDevice.exposureMode = .continuousAutoExposure
                }
            } catch {
                Task { @MainActor in self.captureStatus = .failed(error.localizedDescription) }
            }
        }
    }

    @MainActor
    func setBirdModeEnabled(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            isBirdModeEnabled = enabled
            if enabled {
                configureBirdDetectionIfAvailable()
            } else {
                frameOutput.frameHandler = nil
                if let birdDetectionCoordinator {
                    Task { await birdDetectionCoordinator.reset() }
                }
                Task { @MainActor in
                    self.birdBoundingBox = nil
                    self.birdModeStatus = .disabled
                }
            }
        }
    }

    @MainActor
    func refreshCapabilities() {
        generateCapabilityReport()
        sessionQueue.async { [weak self] in
            self?.applyStabilization()
        }
    }

    @MainActor
    func setStabilizationMode(_ mode: StabilizationModeSelection) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            requestedStabilizationMode = mode
            applyStabilization()
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                if !isConfigured {
                    try configureSession()
                    isConfigured = true
                }
                if !session.isRunning {
                    session.startRunning()
                }
                applyStabilization()
                Task { @MainActor in
                    self.state = .running
                    DiagnosticsLogger.camera.info("Camera session started")
                }
                generateCapabilityReport()
            } catch {
                Task { @MainActor in
                    self.state = .failed(error.localizedDescription)
                    DiagnosticsLogger.camera.error("Camera session configuration failed")
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.noBackCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)
        activeInput = input
        activeDeviceID = device.uniqueID
        activeDevice = device

        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddPhotoOutput
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        self.photoOutput = photoOutput

        guard session.canAddOutput(frameOutput.captureOutput) else {
            throw CameraError.cannotAddVideoOutput
        }
        session.addOutput(frameOutput.captureOutput)
        if let connection = frameOutput.captureOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        updateLensState(for: device)
    }
}

private enum CameraError: LocalizedError {
    case noBackCamera
    case cannotAddInput
    case cannotAddPhotoOutput
    case cannotAddVideoOutput

    var errorDescription: String? {
        switch self {
        case .noBackCamera:
            "未检测到后置相机"
        case .cannotAddInput:
            "无法连接相机输入"
        case .cannotAddPhotoOutput:
            "无法创建拍照输出"
        case .cannotAddVideoOutput:
            "无法创建视频帧分析输出"
        }
    }
}
