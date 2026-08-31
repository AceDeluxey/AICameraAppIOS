import Foundation

enum BirdClassificationRuntimeFactory {
    static func loadBundledClassifier(bundle: Bundle = .main) throws -> any BirdClassifying {
        try CoreMLBirdClassifier.loadBundled(bundle: bundle)
    }
}
