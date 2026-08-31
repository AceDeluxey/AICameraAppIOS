import Foundation

struct MainTargetSelector: Sendable {
    func select(from observations: [BirdObservation]) -> BirdObservation? {
        observations.max { lhs, rhs in
            lhs.confidence < rhs.confidence
        }
    }
}
