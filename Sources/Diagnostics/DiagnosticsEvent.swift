import Foundation
import OSLog

struct DiagnosticsEvent: Equatable, Sendable {
    enum Kind: String, Sendable {
        case cameraStarted
        case detectionCompleted
        case focusRequested
        case focusCompleted
        case targetLost
        case error
    }

    let kind: Kind
    let timestamp: Date
    let durationMilliseconds: Double?
    let details: String?

    init(
        kind: Kind,
        timestamp: Date = Date(),
        durationMilliseconds: Double? = nil,
        details: String? = nil
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.durationMilliseconds = durationMilliseconds
        self.details = details
    }
}

actor DiagnosticsTimeline {
    private let capacity: Int
    private var events: [DiagnosticsEvent] = []

    init(capacity: Int = 500) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func record(_ event: DiagnosticsEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    func snapshot() -> [DiagnosticsEvent] {
        events
    }

    func reset() {
        events.removeAll(keepingCapacity: true)
    }
}

enum DiagnosticsLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.acedeluxey.aicamera"

    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let detection = Logger(subsystem: subsystem, category: "bird-detection")
    static let focus = Logger(subsystem: subsystem, category: "bird-focus")
}
