import Foundation
import OSLog

struct DiagnosticsEvent: Equatable, Sendable {
    enum Kind: String, Sendable {
        case cameraStarted
        case detectionCompleted
        case focusRequested
        case targetLost
        case error
    }

    let kind: Kind
    let timestamp: Date
    let durationMilliseconds: Double?
}

enum DiagnosticsLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.acedeluxey.aicamera"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let detection = Logger(subsystem: subsystem, category: "bird-detection")
    static let focus = Logger(subsystem: subsystem, category: "bird-focus")
}
