import AVFoundation
import Combine
import Foundation

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

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.acedeluxey.aicamera.camera-session")
    private let capabilityProbe = CameraCapabilityProbe()
    private let frameOutput = CameraFrameOutput()
    private let stabilizationController = CameraStabilizationController()
    private var isConfigured = false
    private var activeDeviceID: String?
    private var activeDevice: AVCaptureDevice?
    private var requestedStabilizationMode = StabilizationModeSelection.automatic

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
        activeDeviceID = device.uniqueID
        activeDevice = device

        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddPhotoOutput
        }
        session.addOutput(photoOutput)

        guard session.canAddOutput(frameOutput.captureOutput) else {
            throw CameraError.cannotAddVideoOutput
        }
        session.addOutput(frameOutput.captureOutput)
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
