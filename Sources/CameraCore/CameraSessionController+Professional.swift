import AVFoundation
import CoreMedia
import Foundation

extension CameraSessionController {
    @MainActor
    func setControlMode(_ mode: CameraControlMode) {
        guard !videoRecordingStatus.isBusy, mode != controlMode else { return }
        sessionQueue.async { [weak self] in
            self?.applyControlMode(mode)
        }
    }

    @MainActor
    func setProfessionalControl(_ control: CameraProfessionalControl) {
        guard !videoRecordingStatus.isBusy else { return }
        sessionQueue.async { [weak self] in
            self?.applyProfessionalControl(control)
        }
    }

    func refreshProfessionalState(for device: AVCaptureDevice) {
        let capabilities = professionalCapabilities(for: device)
        let settings = CameraProfessionalSettings(
            exposureBias: device.exposureTargetBias,
            iso: device.iso,
            exposureDuration: safeExposureSeconds(device.exposureDuration),
            lensPosition: device.lensPosition
        ).constrained(to: capabilities)

        Task { @MainActor in
            self.professionalCapabilities = capabilities
            self.professionalSettings = settings
            self.professionalStatus = capabilities.supportsProfessionalMode
                ? .ready
                : .unavailable("当前镜头不支持专业参数")
        }
    }

    func restoreControlMode(for _: AVCaptureDevice) {
        applyControlMode(controlMode)
    }

    private func applyControlMode(_ mode: CameraControlMode) {
        guard let activeDevice else { return }
        let capabilities = professionalCapabilities(for: activeDevice)
        if mode == .professional {
            guard capabilities.supportsProfessionalMode else {
                publishProfessionalFailure("当前镜头不支持 Pro 模式", device: activeDevice)
                return
            }
        }

        do {
            try activeDevice.lockForConfiguration()
            defer { activeDevice.unlockForConfiguration() }
            var settings: CameraProfessionalSettings
            if mode == .automatic {
                applyAutomaticControls(to: activeDevice)
                settings = settingsFromDevice(activeDevice, capabilities: capabilities)
                settings.exposureBias = 0
            } else {
                settings = professionalSettings.constrained(to: capabilities)
                applyProfessionalSettings(settings, to: activeDevice, capabilities: capabilities)
            }
            Task { @MainActor in
                self.controlMode = mode
                self.professionalCapabilities = capabilities
                self.professionalSettings = settings
                self.professionalStatus = .ready
            }
        } catch {
            publishProfessionalFailure("模式切换失败：\(error.localizedDescription)", device: activeDevice)
        }
    }

    private func applyProfessionalControl(_ control: CameraProfessionalControl) {
        guard let activeDevice else { return }
        let capabilities = professionalCapabilities(for: activeDevice)
        var settings = professionalSettings
        switch control {
        case let .exposureBias(value): settings.exposureBias = value
        case let .iso(value): settings.iso = value
        case let .exposureDuration(value): settings.exposureDuration = value
        case let .lensPosition(value): settings.lensPosition = value
        }
        settings = settings.constrained(to: capabilities)

        do {
            try activeDevice.lockForConfiguration()
            defer { activeDevice.unlockForConfiguration() }
            switch control {
            case .exposureBias:
                guard capabilities.exposureBiasRange != nil else { return }
                activeDevice.setExposureTargetBias(settings.exposureBias)
            case .iso, .exposureDuration:
                guard controlMode == .professional,
                      capabilities.isoRange != nil,
                      capabilities.exposureDurationRange != nil
                else { return }
                let duration = CMTime(seconds: settings.exposureDuration, preferredTimescale: 1_000_000_000)
                activeDevice.setExposureModeCustom(duration: duration, iso: settings.iso)
            case .lensPosition:
                guard controlMode == .professional, capabilities.supportsManualFocus else { return }
                activeDevice.setFocusModeLocked(lensPosition: settings.lensPosition)
            }
            Task { @MainActor in
                self.professionalSettings = settings
                self.professionalStatus = .ready
            }
        } catch {
            publishProfessionalFailure("参数设置失败：\(error.localizedDescription)", device: activeDevice)
        }
    }

    private func applyProfessionalSettings(
        _ settings: CameraProfessionalSettings,
        to device: AVCaptureDevice,
        capabilities: CameraProfessionalCapabilities
    ) {
        if capabilities.exposureBiasRange != nil {
            device.setExposureTargetBias(settings.exposureBias)
        }
        if capabilities.isoRange != nil, capabilities.exposureDurationRange != nil {
            let duration = CMTime(seconds: settings.exposureDuration, preferredTimescale: 1_000_000_000)
            device.setExposureModeCustom(duration: duration, iso: settings.iso)
        }
        if capabilities.supportsManualFocus {
            device.setFocusModeLocked(lensPosition: settings.lensPosition)
        }
    }

    private func applyAutomaticControls(to device: AVCaptureDevice) {
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.minExposureTargetBias <= 0, device.maxExposureTargetBias >= 0 {
            device.setExposureTargetBias(0)
        }
    }

    private func professionalCapabilities(for device: AVCaptureDevice) -> CameraProfessionalCapabilities {
        let format = device.activeFormat
        let minimumDuration = safeExposureSeconds(format.minExposureDuration)
        var maximumDuration = safeExposureSeconds(format.maxExposureDuration)
        if captureMode == .video {
            maximumDuration = min(maximumDuration, safeExposureSeconds(device.activeVideoMaxFrameDuration))
        }
        let biasRange = device.maxExposureTargetBias > device.minExposureTargetBias
            ? device.minExposureTargetBias ... device.maxExposureTargetBias
            : nil
        let isoRange = device.isExposureModeSupported(.custom) && format.maxISO > format.minISO
            ? format.minISO ... format.maxISO
            : nil
        let durationRange = device.isExposureModeSupported(.custom) && maximumDuration > minimumDuration
            ? minimumDuration ... maximumDuration
            : nil
        return CameraProfessionalCapabilities(
            exposureBiasRange: biasRange,
            isoRange: isoRange,
            exposureDurationRange: durationRange,
            supportsManualFocus: device.isLockingFocusWithCustomLensPositionSupported
        )
    }

    private func settingsFromDevice(
        _ device: AVCaptureDevice,
        capabilities: CameraProfessionalCapabilities
    ) -> CameraProfessionalSettings {
        CameraProfessionalSettings(
            exposureBias: device.exposureTargetBias,
            iso: device.iso,
            exposureDuration: safeExposureSeconds(device.exposureDuration),
            lensPosition: device.lensPosition
        ).constrained(to: capabilities)
    }

    private func safeExposureSeconds(_ time: CMTime) -> Double {
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? seconds : 1 / 60
    }

    private func publishProfessionalFailure(_ message: String, device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            applyAutomaticControls(to: device)
            device.unlockForConfiguration()
        } catch {
            DiagnosticsLogger.camera.error("Failed to restore automatic camera controls")
        }
        Task { @MainActor in
            self.controlMode = .automatic
            self.professionalStatus = .failed(message)
        }
    }
}
