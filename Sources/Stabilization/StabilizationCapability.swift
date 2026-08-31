import AVFoundation
import Foundation

struct StabilizationCapability: Equatable, Sendable {
    let supportedModes: Set<AVCaptureVideoStabilizationMode>

    func supports(_ mode: AVCaptureVideoStabilizationMode) -> Bool {
        supportedModes.contains(mode)
    }
}

enum StabilizationModeSelection: String, CaseIterable, Sendable {
    case off
    case automatic
    case standard
    case cinematic
    case cinematicExtended

    var avFoundationMode: AVCaptureVideoStabilizationMode {
        switch self {
        case .off:
            .off
        case .automatic:
            .auto
        case .standard:
            .standard
        case .cinematic:
            .cinematic
        case .cinematicExtended:
            .cinematicExtended
        }
    }

    var isPublicMode: Bool {
        self == .off || self == .automatic
    }
}

struct StabilizationApplicationResult: Equatable, Sendable {
    let requestedMode: StabilizationModeSelection
    let preferredMode: AVCaptureVideoStabilizationMode
    let activeMode: AVCaptureVideoStabilizationMode
    let usedFallback: Bool
}

enum StabilizationModePolicy {
    static func preferredMode(
        for requestedMode: StabilizationModeSelection,
        capability: StabilizationCapability
    ) -> AVCaptureVideoStabilizationMode {
        let requestedAVMode = requestedMode.avFoundationMode
        if capability.supports(requestedAVMode) {
            return requestedAVMode
        }

        if requestedMode != .off, capability.supports(.auto) {
            return .auto
        }
        if requestedMode != .off, capability.supports(.standard) {
            return .standard
        }
        return .off
    }
}

struct CameraStabilizationController {
    private let knownModes: [AVCaptureVideoStabilizationMode] = [
        .off,
        .standard,
        .cinematic,
        .cinematicExtended,
        .auto,
    ]

    func capability(for device: AVCaptureDevice) -> StabilizationCapability {
        let format = device.activeFormat
        let supportedModes = knownModes.filter(format.isVideoStabilizationModeSupported)
        return StabilizationCapability(supportedModes: Set(supportedModes))
    }

    func apply(
        _ requestedMode: StabilizationModeSelection,
        to connection: AVCaptureConnection,
        device: AVCaptureDevice
    ) -> StabilizationApplicationResult {
        let capability = capability(for: device)
        let preferredMode = if connection.isVideoStabilizationSupported {
            StabilizationModePolicy.preferredMode(
                for: requestedMode,
                capability: capability
            )
        } else {
            AVCaptureVideoStabilizationMode.off
        }

        connection.preferredVideoStabilizationMode = preferredMode

        return StabilizationApplicationResult(
            requestedMode: requestedMode,
            preferredMode: preferredMode,
            activeMode: connection.activeVideoStabilizationMode,
            usedFallback: preferredMode != requestedMode.avFoundationMode
        )
    }
}
