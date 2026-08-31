import Foundation

enum BirdClassificationRuntimeFactory {
    static func loadBundledClassifier(
        bundle: Bundle = .main,
        prior: (any BirdPriorWeighting)? = nil
    ) throws -> any BirdClassifying {
        try CoreMLBirdClassifier.loadBundled(bundle: bundle, prior: prior)
    }
}
