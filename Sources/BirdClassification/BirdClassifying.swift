import CoreVideo
import Foundation

struct BirdClassification: Equatable, Sendable {
    let identifier: String
    let displayName: String
    let confidence: Float
}

protocol BirdClassifying: Sendable {
    func classify(
        _ pixelBuffer: CVPixelBuffer,
        birdBoundingBox: CGRect
    ) async throws -> [BirdClassification]
}

enum BirdClassificationStatus: Equatable, Sendable {
    case unavailable
    case searching
    case candidates([BirdClassification])
    case failed(String)
}
