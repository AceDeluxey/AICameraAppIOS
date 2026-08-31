import AVFoundation
import CoreMedia
import Foundation

struct CameraCapabilityProbe {
    private let discoveryDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInUltraWideCamera,
        .builtInWideAngleCamera,
        .builtInTelephotoCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInTripleCamera,
    ]

    private let stabilizationModes: [(name: String, value: AVCaptureVideoStabilizationMode)] = [
        ("off", .off),
        ("standard", .standard),
        ("cinematic", .cinematic),
        ("cinematicExtended", .cinematicExtended),
        ("auto", .auto),
    ]

    func makeReport(activeDeviceID: String?) -> CameraCapabilityReport {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: discoveryDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        let devices = discovery.devices
            .map(makeDeviceCapability)
            .sorted { lhs, rhs in
                if lhs.position == rhs.position {
                    return lhs.name < rhs.name
                }
                return lhs.position < rhs.position
            }

        return CameraCapabilityReport(
            generatedAt: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            activeDeviceID: activeDeviceID,
            devices: devices
        )
    }

    private func makeDeviceCapability(_ device: AVCaptureDevice) -> CameraDeviceCapability {
        CameraDeviceCapability(
            id: device.uniqueID,
            name: device.localizedName,
            type: device.deviceType.rawValue,
            position: positionName(device.position),
            isVirtual: device.isVirtualDevice,
            constituentDeviceIDs: device.constituentDevices.map(\.uniqueID),
            focusModes: supportedFocusModes(for: device),
            exposureModes: supportedExposureModes(for: device),
            supportsFocusPoint: device.isFocusPointOfInterestSupported,
            supportsExposurePoint: device.isExposurePointOfInterestSupported,
            minimumZoomFactor: Double(device.minAvailableVideoZoomFactor),
            maximumZoomFactor: Double(device.maxAvailableVideoZoomFactor),
            formats: device.formats.map(makeFormatCapability)
        )
    }

    private func makeFormatCapability(_ format: AVCaptureDevice.Format) -> CameraFormatCapability {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)

        return CameraFormatCapability(
            width: dimensions.width,
            height: dimensions.height,
            mediaSubtype: fourCharacterCode(subtype),
            fieldOfView: format.videoFieldOfView,
            isVideoBinned: format.isVideoBinned,
            supportsHDR: format.isVideoHDRSupported,
            autofocusSystem: autofocusSystemName(format.autoFocusSystem),
            minimumISO: format.minISO,
            maximumISO: format.maxISO,
            minimumExposureSeconds: finiteSeconds(format.minExposureDuration),
            maximumExposureSeconds: finiteSeconds(format.maxExposureDuration),
            maximumZoomFactor: Double(format.videoMaxZoomFactor),
            frameRateRanges: format.videoSupportedFrameRateRanges.map {
                CameraFrameRateRange(minimum: $0.minFrameRate, maximum: $0.maxFrameRate)
            },
            stabilizationModes: stabilizationModes.compactMap { mode in
                format.isVideoStabilizationModeSupported(mode.value) ? mode.name : nil
            }
        )
    }

    private func supportedFocusModes(for device: AVCaptureDevice) -> [String] {
        [
            ("locked", AVCaptureDevice.FocusMode.locked),
            ("autoFocus", .autoFocus),
            ("continuousAutoFocus", .continuousAutoFocus),
        ].compactMap { name, mode in
            device.isFocusModeSupported(mode) ? name : nil
        }
    }

    private func supportedExposureModes(for device: AVCaptureDevice) -> [String] {
        [
            ("locked", AVCaptureDevice.ExposureMode.locked),
            ("autoExpose", .autoExpose),
            ("continuousAutoExposure", .continuousAutoExposure),
            ("custom", .custom),
        ].compactMap { name, mode in
            device.isExposureModeSupported(mode) ? name : nil
        }
    }

    private func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back:
            "back"
        case .front:
            "front"
        case .unspecified:
            "unspecified"
        @unknown default:
            "unknown"
        }
    }

    private func autofocusSystemName(_ system: AVCaptureDevice.Format.AutoFocusSystem) -> String {
        switch system {
        case .none:
            "none"
        case .contrastDetection:
            "contrastDetection"
        case .phaseDetection:
            "phaseDetection"
        @unknown default:
            "unknown"
        }
    }

    private func finiteSeconds(_ time: CMTime) -> Double {
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : 0
    }

    private func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", code)
    }
}
