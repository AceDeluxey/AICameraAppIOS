@testable import AICameraApp
import XCTest

final class EfficientDetPostprocessorTests: XCTestCase {
    func testMapsYXYXOutputToNormalizedObservation() throws {
        let output = rawOutput(
            locations: [0.2, 0.1, 0.8, 0.6],
            classes: [14],
            scores: [0.75]
        )

        let observation = try XCTUnwrap(EfficientDetPostprocessor().observations(from: output).first)

        XCTAssertEqual(observation.boundingBox.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(observation.boundingBox.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(observation.boundingBox.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(observation.boundingBox.height, 0.6, accuracy: 0.0001)
        XCTAssertEqual(observation.confidence, 0.75)
    }

    func testUsesHigherThresholdForCatCompatibility() {
        let output = rawOutput(
            locations: repeatedBoxes(count: 4),
            classes: [14, 14, 15, 15],
            scores: [0.09, 0.10, 0.29, 0.30]
        )
        let configuration = EfficientDetPostprocessingConfiguration(maximumResults: 4)

        let observations = EfficientDetPostprocessor(configuration: configuration)
            .observations(from: output)

        XCTAssertEqual(observations.map(\.confidence), [0.30, 0.10])
    }

    func testRejectsOtherClassesAndInvalidBoxes() {
        let output = rawOutput(
            locations: [
                0.1, 0.1, 0.4, 0.4,
                0.8, 0.8, 0.2, 0.2,
            ],
            classes: [0, 14],
            scores: [0.9, 0.9]
        )

        XCTAssertTrue(EfficientDetPostprocessor().observations(from: output).isEmpty)
    }

    func testClampsCoordinatesAndHandlesTruncatedOutput() throws {
        let output = EfficientDetRawOutput(
            locations: [-0.2, -0.1, 1.3, 1.2],
            classes: [14],
            scores: [0.8],
            numberOfDetections: 25
        )

        let observation = try XCTUnwrap(EfficientDetPostprocessor().observations(from: output).first)

        XCTAssertEqual(observation.boundingBox, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testNonMaximumSuppressionKeepsHighestOverlappingResult() {
        let output = rawOutput(
            locations: [
                0.1, 0.1, 0.6, 0.6,
                0.12, 0.12, 0.62, 0.62,
                0.7, 0.7, 0.9, 0.9,
            ],
            classes: [14, 14, 14],
            scores: [0.8, 0.9, 0.7]
        )
        let configuration = EfficientDetPostprocessingConfiguration(maximumResults: 3)

        let observations = EfficientDetPostprocessor(configuration: configuration)
            .observations(from: output)

        XCTAssertEqual(observations.map(\.confidence), [0.9, 0.7])
    }

    func testMapsUprightBoxBackToOriginalFrameForRightAngleRotations() {
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

        assertRect(
            BirdDetectionCoordinateMapper.originalFrameBox(
                fromUprightBox: box,
                clockwiseRotationDegrees: 90
            ),
            equals: CGRect(x: 0.2, y: 0.6, width: 0.4, height: 0.3)
        )
        assertRect(
            BirdDetectionCoordinateMapper.originalFrameBox(
                fromUprightBox: box,
                clockwiseRotationDegrees: 180
            ),
            equals: CGRect(x: 0.6, y: 0.4, width: 0.3, height: 0.4)
        )
        assertRect(
            BirdDetectionCoordinateMapper.originalFrameBox(
                fromUprightBox: box,
                clockwiseRotationDegrees: 270
            ),
            equals: CGRect(x: 0.4, y: 0.1, width: 0.4, height: 0.3)
        )
        assertRect(
            BirdDetectionCoordinateMapper.originalFrameBox(
                fromUprightBox: box,
                clockwiseRotationDegrees: 360
            ),
            equals: box
        )
    }

    private func rawOutput(
        locations: [Float],
        classes: [Float],
        scores: [Float]
    ) -> EfficientDetRawOutput {
        EfficientDetRawOutput(
            locations: locations,
            classes: classes,
            scores: scores,
            numberOfDetections: Float(scores.count)
        )
    }

    private func repeatedBoxes(count: Int) -> [Float] {
        (0 ..< count).flatMap { index in
            let offset = Float(index) * 0.2
            return [offset, offset, offset + 0.1, offset + 0.1]
        }
    }

    private func assertRect(
        _ actual: CGRect,
        equals expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }
}
