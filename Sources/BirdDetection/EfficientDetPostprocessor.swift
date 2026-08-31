import Foundation

struct EfficientDetRawOutput: Equatable, Sendable {
    let locations: [Float]
    let classes: [Float]
    let scores: [Float]
    let numberOfDetections: Float
}

struct EfficientDetPostprocessingConfiguration: Equatable, Sendable {
    let birdClassID: Int
    let catClassID: Int
    let birdConfidenceThreshold: Float
    let catAsBirdConfidenceThreshold: Float
    let nonMaximumSuppressionThreshold: CGFloat
    let maximumResults: Int

    init(
        birdClassID: Int = 14,
        catClassID: Int = 15,
        birdConfidenceThreshold: Float = 0.10,
        catAsBirdConfidenceThreshold: Float = 0.30,
        nonMaximumSuppressionThreshold: CGFloat = 0.45,
        maximumResults: Int = 1
    ) {
        precondition((0 ... 1).contains(birdConfidenceThreshold))
        precondition((0 ... 1).contains(catAsBirdConfidenceThreshold))
        precondition((0 ... 1).contains(nonMaximumSuppressionThreshold))
        precondition(maximumResults > 0)

        self.birdClassID = birdClassID
        self.catClassID = catClassID
        self.birdConfidenceThreshold = birdConfidenceThreshold
        self.catAsBirdConfidenceThreshold = catAsBirdConfidenceThreshold
        self.nonMaximumSuppressionThreshold = nonMaximumSuppressionThreshold
        self.maximumResults = maximumResults
    }
}

struct EfficientDetPostprocessor: Sendable {
    private let configuration: EfficientDetPostprocessingConfiguration

    init(configuration: EfficientDetPostprocessingConfiguration = .init()) {
        self.configuration = configuration
    }

    func observations(from output: EfficientDetRawOutput) -> [BirdObservation] {
        let tensorCapacity = [
            output.locations.count / 4,
            output.classes.count,
            output.scores.count,
        ].min() ?? 0
        let availableCount = if output.numberOfDetections.isFinite {
            Int(min(max(output.numberOfDetections, 0), Float(tensorCapacity)))
        } else {
            0
        }

        let candidates = (0 ..< availableCount).compactMap { index in
            observation(at: index, output: output)
        }
        let sorted = candidates.sorted { $0.confidence > $1.confidence }

        var kept: [BirdObservation] = []
        for candidate in sorted {
            let overlapsKeptResult = kept.contains {
                candidate.boundingBox.intersectionOverUnion(with: $0.boundingBox)
                    > configuration.nonMaximumSuppressionThreshold
            }
            if !overlapsKeptResult {
                kept.append(candidate)
            }
            if kept.count == configuration.maximumResults {
                break
            }
        }
        return kept
    }

    private func observation(
        at index: Int,
        output: EfficientDetRawOutput
    ) -> BirdObservation? {
        let classValue = output.classes[index]
        let score = output.scores[index]
        guard classValue.isFinite, score.isFinite else { return nil }

        let classID = Int(classValue)
        let threshold: Float

        if classID == configuration.birdClassID {
            threshold = configuration.birdConfidenceThreshold
        } else if classID == configuration.catClassID {
            threshold = configuration.catAsBirdConfidenceThreshold
        } else {
            return nil
        }
        guard score >= threshold else { return nil }

        let locationOffset = index * 4
        let coordinates = Array(output.locations[locationOffset ..< locationOffset + 4])
        guard coordinates.allSatisfy(\.isFinite) else { return nil }

        let minimumY = coordinates[0].clampedToUnitInterval
        let minimumX = coordinates[1].clampedToUnitInterval
        let maximumY = coordinates[2].clampedToUnitInterval
        let maximumX = coordinates[3].clampedToUnitInterval
        guard maximumX > minimumX, maximumY > minimumY else { return nil }

        return BirdObservation(
            boundingBox: CGRect(
                x: CGFloat(minimumX),
                y: CGFloat(minimumY),
                width: CGFloat(maximumX - minimumX),
                height: CGFloat(maximumY - minimumY)
            ),
            confidence: score
        )
    }
}

enum BirdDetectionCoordinateMapper {
    static func originalFrameBox(
        fromUprightBox box: CGRect,
        clockwiseRotationDegrees: Int
    ) -> CGRect {
        let normalizedRotation = ((clockwiseRotationDegrees % 360) + 360) % 360
        let mappedBox = switch normalizedRotation {
        case 90:
            CGRect(
                x: box.minY,
                y: 1 - box.maxX,
                width: box.height,
                height: box.width
            )
        case 180:
            CGRect(
                x: 1 - box.maxX,
                y: 1 - box.maxY,
                width: box.width,
                height: box.height
            )
        case 270:
            CGRect(
                x: 1 - box.maxY,
                y: box.minX,
                width: box.height,
                height: box.width
            )
        default:
            box
        }
        return mappedBox.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

private extension Float {
    var clampedToUnitInterval: Float {
        min(max(self, 0), 1)
    }
}

private extension CGRect {
    func intersectionOverUnion(with other: CGRect) -> CGFloat {
        let overlap = intersection(other)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return 0 }

        let overlapArea = overlap.width * overlap.height
        let unionArea = width * height + other.width * other.height - overlapArea
        return unionArea > 0 ? overlapArea / unionArea : 0
    }
}
