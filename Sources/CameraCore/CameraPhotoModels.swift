import Foundation

enum PhotoAspectRatio: String, CaseIterable, Codable, Sendable {
    case fourByThree = "4:3"
    case sixteenByNine = "16:9"

    var landscapeValue: CGFloat {
        switch self {
        case .fourByThree:
            4 / 3
        case .sixteenByNine:
            16 / 9
        }
    }

    var portraitValue: CGFloat {
        1 / landscapeValue
    }
}

struct CameraLensOption: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let zoomLabel: String
    let nominalZoomFactor: CGFloat
}

enum CameraCaptureStatus: Equatable, Sendable {
    case idle
    case capturing
    case saved
    case failed(String)
}

enum BirdModeStatus: Equatable, Sendable {
    case disabled
    case unavailable(String)
    case searching
    case confirming
    case locked(confidence: Float)
    case temporarilyLost
    case failed(String)
}

enum CameraLoadPolicy {
    static func detectionInterval(for thermalState: ProcessInfo.ThermalState) -> TimeInterval {
        switch thermalState {
        case .nominal:
            0.1
        case .fair:
            0.15
        case .serious:
            0.3
        case .critical:
            0.6
        @unknown default:
            0.3
        }
    }
}
