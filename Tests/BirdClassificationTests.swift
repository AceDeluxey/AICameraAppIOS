@testable import AICameraApp
import CoreVideo
import XCTest

final class BirdClassificationTests: XCTestCase {
    func testPostprocessorAppliesStableSoftmaxAndReturnsTopThree() {
        let labels = [
            BirdClassificationLabel(identifier: "a", displayName: "甲"),
            BirdClassificationLabel(identifier: "b", displayName: "乙"),
            BirdClassificationLabel(identifier: "c", displayName: "丙"),
            BirdClassificationLabel(identifier: "d", displayName: "丁"),
        ]

        let result = BirdClassificationPostprocessor().classifications(
            logits: [1001, 1003, 1002, -.infinity],
            labels: labels
        )

        XCTAssertEqual(result.map(\.identifier), ["b", "c", "a"])
        XCTAssertEqual(result.reduce(0) { $0 + $1.confidence }, 1, accuracy: 0.0001)
    }

    func testPostprocessorRejectsMismatchedLabelCount() {
        let labels = [BirdClassificationLabel(identifier: "a", displayName: "甲")]
        XCTAssertTrue(
            BirdClassificationPostprocessor().classifications(
                logits: [1, 2],
                labels: labels
            ).isEmpty
        )
    }

    func testPostprocessorAppliesPriorAndRenormalizesCandidates() {
        let labels = [
            BirdClassificationLabel(identifier: "a", displayName: "甲"),
            BirdClassificationLabel(identifier: "b", displayName: "乙"),
        ]
        let result = BirdClassificationPostprocessor().classifications(
            logits: [2, 1],
            labels: labels,
            prior: StubBirdPrior(weights: [0.05, 7])
        )

        XCTAssertEqual(result.map(\.identifier), ["b", "a"])
        XCTAssertEqual(result.reduce(0) { $0 + $1.confidence }, 1, accuracy: 0.0001)
    }

    func testRegionPriorMatchesProvinceAndAndroidMonthSmoothingWeights() throws {
        let prior = try makeRegionPrior()
        prior.update(latitude: 5, longitude: 5, month: 1)

        XCTAssertEqual(prior.activeRegion, BirdRegionMatch(code: "110000", name: "测试省"))
        XCTAssertEqual(prior.weight(for: 0), 1 + 6 * 64 / 255, accuracy: 0.0001)
        XCTAssertEqual(prior.weight(for: 1), 0.22, accuracy: 0.0001)
        XCTAssertEqual(prior.weight(for: 2), 0.05, accuracy: 0.0001)
    }

    func testRegionPriorFallsBackToNoWeightOutsideChinaOrAfterClear() throws {
        let prior = try makeRegionPrior()
        prior.update(latitude: 50, longitude: 50, month: 6)
        XCTAssertNil(prior.activeRegion)
        XCTAssertEqual(prior.weight(for: 0), 1)

        prior.update(latitude: 5, longitude: 5, month: 6)
        prior.clear()
        XCTAssertEqual(prior.weight(for: 0), 1)
    }

    func testRegionPriorRejectsDamagedResources() {
        XCTAssertThrowsError(
            try BirdRegionPrior(priorContents: "v2|GBIF", polygonContents: "v1")
        )
        XCTAssertThrowsError(
            try BirdRegionPrior(priorContents: "v1|GBIF|test", polygonContents: "v1\ninvalid")
        )
    }

    func testLabelParserUsesChineseAndScientificNames() {
        let labels = BirdClassificationLabelParser.parse(
            "麻雀|Eurasian Tree Sparrow|Passer montanus\n喜鹊||Pica pica\n"
        )

        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels[0].displayName, "麻雀")
        XCTAssertEqual(labels[0].identifier, "Passer montanus")
        XCTAssertEqual(labels[1].displayName, "喜鹊")
    }

    func testCoordinatorThrottlesAndRequiresTwoResultsBeforeSwitchingSpecies() async throws {
        let classifier = StubBirdClassifier(results: [
            [candidate("sparrow", "麻雀", 0.8)],
            [candidate("magpie", "喜鹊", 0.7)],
            [candidate("magpie", "喜鹊", 0.75)],
        ])
        let coordinator = BirdClassificationCoordinator(
            classifier: classifier,
            minimumInterval: 1,
            requiredStableResults: 2
        )
        let buffer = try makePixelBuffer()

        let first = try await coordinator.submit(
            pixelBuffer: buffer,
            birdBoundingBox: unitBox,
            presentationTimeSeconds: 1
        )
        let throttled = try await coordinator.submit(
            pixelBuffer: buffer,
            birdBoundingBox: unitBox,
            presentationTimeSeconds: 1.5
        )
        let pending = try await coordinator.submit(
            pixelBuffer: buffer,
            birdBoundingBox: unitBox,
            presentationTimeSeconds: 2
        )
        let switched = try await coordinator.submit(
            pixelBuffer: buffer,
            birdBoundingBox: unitBox,
            presentationTimeSeconds: 3
        )

        XCTAssertEqual(first?.first?.identifier, "sparrow")
        XCTAssertNil(throttled)
        XCTAssertEqual(pending?.first?.identifier, "sparrow")
        XCTAssertEqual(switched?.first?.identifier, "magpie")
        let callCount = await classifier.callCount
        XCTAssertEqual(callCount, 3)
    }

    func testSquareCropConvertsTopLeftCoordinatesToCoreImageCoordinates() {
        let crop = CoreMLBirdClassifier.squareCropRect(
            normalizedBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2),
            imageExtent: CGRect(x: 0, y: 0, width: 1000, height: 500),
            expansion: 1
        )

        XCTAssertEqual(crop.midX, 400, accuracy: 0.001)
        XCTAssertEqual(crop.midY, 300, accuracy: 0.001)
        XCTAssertEqual(crop.width, 400, accuracy: 0.001)
        XCTAssertEqual(crop.height, 400, accuracy: 0.001)
    }

    private var unitBox: CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func candidate(_ id: String, _ name: String, _ confidence: Float) -> BirdClassification {
        BirdClassification(identifier: id, displayName: name, confidence: confidence)
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            1,
            1,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func makeRegionPrior() throws -> BirdRegionPrior {
        let priorContents = """
        v1|GBIF|test
        C|CN|全国
        2
        0 ff
        1 80
        R|110000|测试省|2
        0 ff008000000000000000000000
        1 ff000000000000000000000000
        """
        let polygonContents = """
        v1
        P|110000|测试省
        0,0;10,0;10,10;0,10;0,0
        """
        return try BirdRegionPrior(
            priorContents: priorContents,
            polygonContents: polygonContents
        )
    }
}

private struct StubBirdPrior: BirdPriorWeighting {
    let weights: [Float]

    func weight(for index: Int) -> Float {
        weights[index]
    }
}

private actor StubBirdClassifier: BirdClassifying {
    private(set) var callCount = 0
    private let results: [[BirdClassification]]

    init(results: [[BirdClassification]]) {
        self.results = results
    }

    func classify(
        _ pixelBuffer: CVPixelBuffer,
        birdBoundingBox: CGRect
    ) async throws -> [BirdClassification] {
        defer { callCount += 1 }
        return results[min(callCount, results.count - 1)]
    }
}
