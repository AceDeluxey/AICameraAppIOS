import CoreVideo
import Foundation

struct BirdClassification: Equatable, Sendable {
    let identifier: String
    let displayName: String
    let confidence: Float
}

protocol BirdClassifying: Sendable {
    func classify(_ pixelBuffer: CVPixelBuffer) async throws -> [BirdClassification]
}
