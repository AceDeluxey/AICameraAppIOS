import AVFoundation
import Foundation
import UIKit

extension CameraSessionController {
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

    func observeSessionNotifications() {
        observeInterruptionNotifications()
        observeRuntimeErrorNotifications()
        observeLoadNotifications()
    }

    private func observeInterruptionNotifications() {
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
    }

    private func observeRuntimeErrorNotifications() {
        notificationTokens.append(NotificationCenter.default.addObserver(
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
    }

    private func observeLoadNotifications() {
        let center = NotificationCenter.default
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
            self?.handleMemoryWarning()
        })
    }

    private func handleMemoryWarning() {
        guard let birdDetectionCoordinator else { return }
        Task {
            await birdDetectionCoordinator.reset()
            await MainActor.run {
                self.birdBoundingBox = nil
                if self.isBirdModeEnabled {
                    self.birdModeStatus = .searching
                }
            }
        }
    }

    func updateThermalPolicy() {
        let state = ProcessInfo.processInfo.thermalState
        let interval = CameraLoadPolicy.detectionInterval(for: state)
        if let birdDetectionCoordinator {
            Task { await birdDetectionCoordinator.setMinimumInterval(interval) }
        }
        Task { @MainActor in self.thermalState = state }
    }

    func applyStabilization() {
        let selectedConnection = if captureMode == .video {
            movieOutput?.connection(with: .video)
        } else {
            frameOutput.captureOutput.connection(with: .video)
        }
        guard
            let activeDevice,
            let connection = selectedConnection
        else {
            Task { @MainActor in self.stabilizationResult = nil }
            return
        }

        let result = stabilizationController.apply(
            requestedStabilizationMode,
            to: connection,
            device: activeDevice
        )
        Task { @MainActor in
            self.stabilizationResult = result
            logStabilization(result)
        }
    }

    func generateCapabilityReport() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let report = capabilityProbe.makeReport(activeDeviceID: activeDeviceID)
            Task { @MainActor in
                self.capabilityReport = report
                DiagnosticsLogger.camera.info("Camera capability report generated")
            }
        }
    }

    @MainActor
    private func logStabilization(_ result: StabilizationApplicationResult) {
        let requestedName = result.requestedMode.rawValue
        let preferredName = result.preferredMode.diagnosticName
        let activeName = result.activeMode.diagnosticName
        DiagnosticsLogger.camera.info("Stabilization requested=\(requestedName, privacy: .public)")
        DiagnosticsLogger.camera.info("Stabilization preferred=\(preferredName, privacy: .public)")
        DiagnosticsLogger.camera.info("Stabilization active=\(activeName, privacy: .public)")
    }
}
