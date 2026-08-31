import Foundation

struct MainTargetSelector: Sendable {
    func select(from observations: [BirdObservation]) -> BirdObservation? {
        observations.max { lhs, rhs in
            lhs.confidence < rhs.confidence
        }
    }
}

struct MainTargetTrackingConfiguration: Equatable, Sendable {
    let strongConfidence: Float
    let weakConfidence: Float
    let weakConfirmationFrames: Int
    let minimumMatchIoU: CGFloat
    let smoothingFactor: CGFloat

    init(
        strongConfidence: Float = 0.65,
        weakConfidence: Float = 0.30,
        weakConfirmationFrames: Int = 3,
        minimumMatchIoU: CGFloat = 0.20,
        smoothingFactor: CGFloat = 0.35
    ) {
        precondition((0 ... 1).contains(strongConfidence))
        precondition((0 ... strongConfidence).contains(weakConfidence))
        precondition(weakConfirmationFrames > 0)
        precondition((0 ... 1).contains(minimumMatchIoU))
        precondition((0 ... 1).contains(smoothingFactor))

        self.strongConfidence = strongConfidence
        self.weakConfidence = weakConfidence
        self.weakConfirmationFrames = weakConfirmationFrames
        self.minimumMatchIoU = minimumMatchIoU
        self.smoothingFactor = smoothingFactor
    }
}

enum MainTargetTrackingState: Equatable, Sendable {
    case searching
    case confirming(currentFrame: Int, requiredFrames: Int)
    case confirmed
}

struct MainTargetTrackingResult: Equatable, Sendable {
    let observation: BirdObservation?
    let focusPoint: CGPoint?
    let state: MainTargetTrackingState
}

struct MainTargetTracker: Sendable {
    private let selector: MainTargetSelector
    private let configuration: MainTargetTrackingConfiguration

    private var candidate: BirdObservation?
    private var candidateFrameCount = 0
    private var confirmedObservation: BirdObservation?

    init(
        selector: MainTargetSelector = MainTargetSelector(),
        configuration: MainTargetTrackingConfiguration = MainTargetTrackingConfiguration()
    ) {
        self.selector = selector
        self.configuration = configuration
    }

    mutating func update(with observations: [BirdObservation]) -> MainTargetTrackingResult {
        guard let selected = selector.select(from: observations),
              selected.confidence >= configuration.weakConfidence
        else {
            reset()
            return MainTargetTrackingResult(observation: nil, focusPoint: nil, state: .searching)
        }

        if selected.confidence >= configuration.strongConfidence {
            if let confirmedObservation,
               confirmedObservation.boundingBox.intersectionOverUnion(with: selected.boundingBox)
               < configuration.minimumMatchIoU
            {
                reset()
            }
            return confirm(selected)
        }

        if let confirmedObservation {
            guard confirmedObservation.boundingBox.intersectionOverUnion(with: selected.boundingBox)
                >= configuration.minimumMatchIoU
            else {
                reset()
                return beginConfirmation(with: selected)
            }

            return confirm(selected)
        }

        return continueConfirmation(with: selected)
    }

    mutating func reset() {
        candidate = nil
        candidateFrameCount = 0
        confirmedObservation = nil
    }

    private mutating func continueConfirmation(
        with selected: BirdObservation
    ) -> MainTargetTrackingResult {
        guard let candidate,
              candidate.boundingBox.intersectionOverUnion(with: selected.boundingBox)
              >= configuration.minimumMatchIoU
        else {
            return beginConfirmation(with: selected)
        }

        self.candidate = candidate.smoothed(toward: selected, factor: configuration.smoothingFactor)
        candidateFrameCount += 1

        if candidateFrameCount >= configuration.weakConfirmationFrames {
            return confirm(self.candidate ?? selected)
        }

        return MainTargetTrackingResult(
            observation: nil,
            focusPoint: nil,
            state: .confirming(
                currentFrame: candidateFrameCount,
                requiredFrames: configuration.weakConfirmationFrames
            )
        )
    }

    private mutating func beginConfirmation(
        with selected: BirdObservation
    ) -> MainTargetTrackingResult {
        candidate = selected
        candidateFrameCount = 1

        if configuration.weakConfirmationFrames == 1 {
            return confirm(selected)
        }

        return MainTargetTrackingResult(
            observation: nil,
            focusPoint: nil,
            state: .confirming(
                currentFrame: candidateFrameCount,
                requiredFrames: configuration.weakConfirmationFrames
            )
        )
    }

    private mutating func confirm(_ selected: BirdObservation) -> MainTargetTrackingResult {
        let observation: BirdObservation
        if let confirmedObservation {
            observation = confirmedObservation.smoothed(
                toward: selected,
                factor: configuration.smoothingFactor
            )
        } else {
            observation = selected
        }

        candidate = nil
        candidateFrameCount = 0
        confirmedObservation = observation

        return MainTargetTrackingResult(
            observation: observation,
            focusPoint: observation.boundingBox.normalizedCenter,
            state: .confirmed
        )
    }
}

private extension BirdObservation {
    func smoothed(toward next: BirdObservation, factor: CGFloat) -> BirdObservation {
        BirdObservation(
            boundingBox: boundingBox.interpolated(toward: next.boundingBox, factor: factor),
            confidence: next.confidence
        )
    }
}

private extension CGRect {
    var normalizedCenter: CGPoint {
        CGPoint(
            x: min(max(midX, 0), 1),
            y: min(max(midY, 0), 1)
        )
    }

    func intersectionOverUnion(with other: CGRect) -> CGFloat {
        let overlap = intersection(other)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return 0 }

        let overlapArea = overlap.width * overlap.height
        let unionArea = width * height + other.width * other.height - overlapArea
        return unionArea > 0 ? overlapArea / unionArea : 0
    }

    func interpolated(toward other: CGRect, factor: CGFloat) -> CGRect {
        CGRect(
            x: minX + (other.minX - minX) * factor,
            y: minY + (other.minY - minY) * factor,
            width: width + (other.width - width) * factor,
            height: height + (other.height - height) * factor
        )
    }
}
