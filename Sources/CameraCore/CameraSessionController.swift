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

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.acedeluxey.aicamera.camera-session")
    private let capabilityProbe = CameraCapabilityProbe()
    private var isConfigured = false
    private var activeDeviceID: String?

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

        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddPhotoOutput
        }
        session.addOutput(photoOutput)
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

    var errorDescription: String? {
        switch self {
        case .noBackCamera:
            "未检测到后置相机"
        case .cannotAddInput:
            "无法连接相机输入"
        case .cannotAddPhotoOutput:
            "无法创建拍照输出"
        }
    }
}
