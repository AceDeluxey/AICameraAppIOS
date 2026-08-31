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

    @Published private(set) var state: State = .idle
    @Published private(set) var capabilityReport: CameraCapabilityReport?
    @Published private(set) var stabilizationResult: StabilizationApplicationResult?
    @Published private(set) var availableLenses: [CameraLensOption] = []
    @Published private(set) var activeLensID: String?
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var zoomRange: ClosedRange<CGFloat> = 1 ... 1
    @Published private(set) var captureStatus: CameraCaptureStatus = .idle
    @Published private(set) var latestThumbnail: UIImage?
    @Published private(set) var focusPoint: CGPoint?
    @Published private(set) var interruptionMessage: String?
    @Published private(set) var birdBoundingBox: CGRect?
    @Published private(set) var birdImageSize: CGSize = .zero
    @Published private(set) var birdModeStatus = BirdModeStatus.disabled
    @Published var aspectRatio: PhotoAspectRatio = .fourByThree
    @Published var includesLocationMetadata: Bool {
        didSet {
            UserDefaults.standard.set(includesLocationMetadata, forKey: Self.locationPreferenceKey)
        }
    }
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.acedeluxey.aicamera.camera-session")
    private let capabilityProbe = CameraCapabilityProbe()
    private let frameOutput = CameraFrameOutput()
    private let stabilizationController = CameraStabilizationController()
    private let photoLibrary = PhotoLibraryService()
    private let photoLocationProvider = PhotoLocationProvider()
    private var isConfigured = false
    private var activeDeviceID: String?
    private var activeDevice: AVCaptureDevice?
    private var activeInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoProcessors: [Int64: PhotoCaptureProcessor] = [:]
    private var requestedStabilizationMode = StabilizationModeSelection.automatic
    private var notificationTokens: [NSObjectProtocol] = []
    private let diagnosticsTimeline = DiagnosticsTimeline()
    private var birdDetectionCoordinator: BirdDetectionCoordinator?
    private var isBirdModeEnabled = false
    private static let locationPreferenceKey = "includesPhotoLocationMetadata"

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
    func toggleAspectRatio() {
        aspectRatio = aspectRatio == .fourByThree ? .sixteenByNine : .fourByThree
    }

    @MainActor
    func capturePhoto() {
        guard state == .running, captureStatus != .capturing else { return }
        captureStatus = .capturing
        let selectedRatio = aspectRatio
        sessionQueue.async { [weak self] in
            guard let self, let photoOutput else {
                Task { @MainActor in
                    self?.captureStatus = .failed("拍照输出尚未就绪")
                }
                return
            }
            let settings = AVCapturePhotoSettings(format: [
                AVVideoCodecKey: AVVideoCodecType.jpeg,
            ])
            settings.photoQualityPrioritization = .quality
            if let connection = photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90)
            {
                connection.videoRotationAngle = 90
            }

            let processor = PhotoCaptureProcessor(aspectRatio: selectedRatio) { [weak self] result in
                self?.finishCapture(id: settings.uniqueID, result: result)
            }
            photoProcessors[settings.uniqueID] = processor
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    @MainActor
    func selectLens(id: String) {
        guard id != activeLensID else { return }
        sessionQueue.async { [weak self] in
            self?.switchLens(to: id)
        }
    }

    @MainActor
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            self?.applyZoomFactor(factor)
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
    func clearCaptureMessage() {
        if captureStatus != .capturing {
            captureStatus = .idle
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
        if let connection = frameOutput.captureOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90)
        {
            connection.videoRotationAngle = 90
        }
        updateLensState(for: device)
    }

    private func finishCapture(
        id: Int64,
        result: Result<(Data, UIImage), any Error>
    ) {
        sessionQueue.async { [weak self] in
            self?.photoProcessors[id] = nil
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch result {
            case let .success((data, image)):
                do {
                    let location = includesLocationMetadata
                        ? await photoLocationProvider.currentLocation()
                        : nil
                    try await photoLibrary.save(data, location: location)
                    latestThumbnail = image
                    captureStatus = .saved
                } catch {
                    captureStatus = .failed(error.localizedDescription)
                }
            case let .failure(error):
                captureStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func switchLens(to id: String) {
        let devices = physicalBackCameras()
        guard let device = devices.first(where: { $0.uniqueID == id }),
              let currentInput = activeInput
        else { return }

        do {
            let replacement = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.removeInput(currentInput)
            if session.canAddInput(replacement) {
                session.addInput(replacement)
                activeInput = replacement
                activeDevice = device
                activeDeviceID = device.uniqueID
                updateLensState(for: device)
            } else {
                session.addInput(currentInput)
            }
            session.commitConfiguration()
            applyStabilization()
            generateCapabilityReport()
        } catch {
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
        }
    }

    private func applyZoomFactor(_ requestedFactor: CGFloat) {
        guard let activeDevice else { return }
        let factor = min(
            max(requestedFactor, activeDevice.minAvailableVideoZoomFactor),
            activeDevice.maxAvailableVideoZoomFactor
        )
        do {
            try activeDevice.lockForConfiguration()
            activeDevice.videoZoomFactor = factor
            activeDevice.unlockForConfiguration()
            Task { @MainActor in self.zoomFactor = factor }
        } catch {
            Task { @MainActor in self.captureStatus = .failed(error.localizedDescription) }
        }
    }

    private func updateLensState(for device: AVCaptureDevice) {
        let devices = physicalBackCameras()
        let wideFieldOfView = devices.first(where: { $0.deviceType == .builtInWideAngleCamera })?
            .activeFormat.videoFieldOfView ?? device.activeFormat.videoFieldOfView
        let options = devices.map { camera -> CameraLensOption in
            let factor = max(0.1, CGFloat(wideFieldOfView / camera.activeFormat.videoFieldOfView))
            return CameraLensOption(
                id: camera.uniqueID,
                displayName: camera.localizedName,
                zoomLabel: Self.zoomLabel(for: factor),
                nominalZoomFactor: factor
            )
        }.sorted { $0.nominalZoomFactor < $1.nominalZoomFactor }
        let range = device.minAvailableVideoZoomFactor ... device.maxAvailableVideoZoomFactor
        Task { @MainActor in
            self.availableLenses = options
            self.activeLensID = device.uniqueID
            self.zoomRange = range
            self.zoomFactor = device.videoZoomFactor
        }
    }

    private func configureBirdDetectionIfAvailable() {
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

    private func processBirdFrame(_ frame: CameraFrame) {
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
    private func publishBirdResult(_ result: BirdFocusPipelineResult, imageSize: CGSize) {
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
    private func publishBirdFailure(_ error: any Error) {
        birdBoundingBox = nil
        birdModeStatus = .failed(error.localizedDescription)
        DiagnosticsLogger.detection.error("Bird detection failed: \(error.localizedDescription, privacy: .public)")
    }

    private func applyBirdFocusDecision(_ decision: BirdFocusDecision) {
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

    private func physicalBackCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        ).devices
    }

    private static func zoomLabel(for factor: CGFloat) -> String {
        if abs(factor.rounded() - factor) < 0.08 {
            return "\(Int(factor.rounded()))×"
        }
        return String(format: "%.1f×", factor)
    }

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            let reason = reasonValue.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            Task { @MainActor in
                self?.interruptionMessage = reason == .videoDeviceInUseByAnotherClient
                    ? "相机正在被其他应用使用"
                    : "相机会话已中断"
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.interruptionMessage = nil
                await self?.start()
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            Task { @MainActor in
                if error?.code == .mediaServicesWereReset {
                    self?.state = .idle
                    await self?.start()
                } else {
                    self?.state = .failed(error?.localizedDescription ?? "相机会话运行错误")
                }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: ProcessInfo.processInfo,
            queue: nil
        ) { [weak self] _ in
            self?.updateThermalPolicy()
        })
        notificationTokens.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self, let birdDetectionCoordinator else { return }
            Task {
                await birdDetectionCoordinator.reset()
                await MainActor.run {
                    self.birdBoundingBox = nil
                    if self.isBirdModeEnabled {
                        self.birdModeStatus = .searching
                    }
                }
            }
        })
    }

    private func updateThermalPolicy() {
        let state = ProcessInfo.processInfo.thermalState
        let interval = CameraLoadPolicy.detectionInterval(for: state)
        if let birdDetectionCoordinator {
            Task { await birdDetectionCoordinator.setMinimumInterval(interval) }
        }
        Task { @MainActor in self.thermalState = state }
    }

    private func applyStabilization() {
        guard
            let activeDevice,
            let connection = frameOutput.captureOutput.connection(with: .video)
        else {
            Task { @MainActor in
                self.stabilizationResult = nil
            }
            return
        }

        let result = stabilizationController.apply(
            requestedStabilizationMode,
            to: connection,
            device: activeDevice
        )
        Task { @MainActor in
            self.stabilizationResult = result
            let requestedName = result.requestedMode.rawValue
            let preferredName = result.preferredMode.diagnosticName
            let activeName = result.activeMode.diagnosticName
            DiagnosticsLogger.camera.info("Stabilization requested=\(requestedName, privacy: .public)")
            DiagnosticsLogger.camera.info("Stabilization preferred=\(preferredName, privacy: .public)")
            DiagnosticsLogger.camera.info("Stabilization active=\(activeName, privacy: .public)")
        }
    }

    private func generateCapabilityReport() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let report = capabilityProbe.makeReport(activeDeviceID: activeDeviceID)
            Task { @MainActor in
                self.capabilityReport = report
                DiagnosticsLogger.camera.info("Camera capability report generated")
            }
        }
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
