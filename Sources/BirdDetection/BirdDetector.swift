import CoreVideo
import Foundation

struct BirdObservation: Equatable, Sendable {
    let boundingBox: CGRect
    let confidence: Float
}

protocol BirdDetecting: Sendable {
    func detectBirds(in pixelBuffer: CVPixelBuffer) async throws -> [BirdObservation]
}
