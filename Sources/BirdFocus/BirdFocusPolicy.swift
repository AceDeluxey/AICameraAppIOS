import Foundation

struct BirdFocusPolicyConfiguration: Equatable, Sendable {
    let minimumRefocusInterval: TimeInterval
    let minimumTargetMovement: CGFloat
    let manualFocusHoldDuration: TimeInterval

    init(
        minimumRefocusInterval: TimeInterval = 0.75,
        minimumTargetMovement: CGFloat = 0.08,
        manualFocusHoldDuration: TimeInterval = 2.0
    ) {
        precondition(minimumRefocusInterval >= 0)
        precondition(minimumTargetMovement >= 0)
        precondition(manualFocusHoldDuration >= 0)

        self.minimumRefocusInterval = minimumRefocusInterval
        self.minimumTargetMovement = minimumTargetMovement
        self.manualFocusHoldDuration = manualFocusHoldDuration
    }
}

enum BirdFocusDecision: Equatable, Sendable {
    case none
    case focus(at: CGPoint)
    case resumeContinuousAutoFocus
}

struct BirdFocusPolicy: Sendable {
    private let configuration: BirdFocusPolicyConfiguration

    private var lastAIFocusPoint: CGPoint?
    private var lastAIFocusTimestamp: TimeInterval?
    private var manualFocusHoldUntil: TimeInterval?
    private var hadConfirmedTarget = false

    init(configuration: BirdFocusPolicyConfiguration = BirdFocusPolicyConfiguration()) {
        self.configuration = configuration
    }

    mutating func registerManualFocus(at timestamp: TimeInterval) {
        manualFocusHoldUntil = timestamp + configuration.manualFocusHoldDuration
    }

    mutating func decision(
        for trackingResult: MainTargetTrackingResult,
        at timestamp: TimeInterval
    ) -> BirdFocusDecision {
        switch trackingResult.state {
        case .confirmed:
            guard let focusPoint = trackingResult.focusPoint else { return .none }
            hadConfirmedTarget = true
            guard !isManualFocusProtected(at: timestamp) else { return .none }
            return focusDecision(for: focusPoint, at: timestamp)

        case .temporarilyLost, .confirming:
            return .none

        case .searching:
            guard hadConfirmedTarget else { return .none }
            guard !isManualFocusProtected(at: timestamp) else { return .none }
            hadConfirmedTarget = false
            lastAIFocusPoint = nil
            lastAIFocusTimestamp = nil
            return .resumeContinuousAutoFocus
        }
    }

    mutating func reset() {
        lastAIFocusPoint = nil
        lastAIFocusTimestamp = nil
        manualFocusHoldUntil = nil
        hadConfirmedTarget = false
    }

    private func isManualFocusProtected(at timestamp: TimeInterval) -> Bool {
        guard let manualFocusHoldUntil else { return false }
        return timestamp < manualFocusHoldUntil
    }

    private mutating func focusDecision(
        for focusPoint: CGPoint,
        at timestamp: TimeInterval
    ) -> BirdFocusDecision {
        if let lastAIFocusTimestamp {
            let elapsed = timestamp - lastAIFocusTimestamp
            if elapsed < configuration.minimumRefocusInterval {
                return .none
            }
        }

        if let lastAIFocusPoint {
            let movement = lastAIFocusPoint.distance(to: focusPoint)
            if movement < configuration.minimumTargetMovement {
                return .none
            }
        }

        lastAIFocusPoint = focusPoint
        lastAIFocusTimestamp = timestamp
        return .focus(at: focusPoint)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
