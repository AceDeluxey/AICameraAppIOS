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

    var displayName: String {
        switch self {
        case .off:
            "关闭"
        case .automatic:
            "自动"
        case .standard:
            "标准（内部）"
        case .cinematic:
            "电影级（内部）"
        case .cinematicExtended:
            "扩展电影级（内部）"
        }
    }
}

struct StabilizationApplicationResult: Equatable, Sendable {
    let requestedMode: StabilizationModeSelection
    let preferredMode: AVCaptureVideoStabilizationMode
    let activeMode: AVCaptureVideoStabilizationMode
    let usedFallback: Bool

    var textDescription: String {
        [
            "请求：\(requestedMode.displayName)",
            "首选：\(preferredMode.diagnosticName)",
            "实际：\(activeMode.diagnosticName)",
            "降级：\(usedFallback ? "是" : "否")",
        ].joined(separator: "\n")
    }
}

extension AVCaptureVideoStabilizationMode {
    var diagnosticName: String {
        switch self {
        case .off:
            "off"
        case .standard:
            "standard"
        case .cinematic:
            "cinematic"
        case .cinematicExtended:
            "cinematicExtended"
        case .auto:
            "auto"
        case .previewOptimized:
            "previewOptimized"
        @unknown default:
            "unknown(\(rawValue))"
        }
    }
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
