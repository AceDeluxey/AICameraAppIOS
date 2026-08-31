@testable import AICameraApp
import UIKit
import XCTest

final class CameraPhotoModelsTests: XCTestCase {
    func testAspectRatioValues() {
        XCTAssertEqual(PhotoAspectRatio.fourByThree.landscapeValue, 4 / 3, accuracy: 0.0001)
        XCTAssertEqual(PhotoAspectRatio.fourByThree.portraitValue, 3 / 4, accuracy: 0.0001)
        XCTAssertEqual(PhotoAspectRatio.sixteenByNine.landscapeValue, 16 / 9, accuracy: 0.0001)
        XCTAssertEqual(PhotoAspectRatio.sixteenByNine.portraitValue, 9 / 16, accuracy: 0.0001)
    }

    func testCenterCropProducesRequestedLandscapeRatio() throws {
        let image = makeImage(size: CGSize(width: 100, height: 100))
        let cropped = try PhotoCaptureProcessor.centerCrop(image, to: .sixteenByNine)

        XCTAssertEqual(cropped.size.width / cropped.size.height, 16 / 9, accuracy: 0.02)
    }

    func testCenterCropProducesRequestedPortraitRatio() throws {
        let image = makeImage(size: CGSize(width: 100, height: 200))
        let cropped = try PhotoCaptureProcessor.centerCrop(image, to: .fourByThree)

        XCTAssertEqual(cropped.size.width / cropped.size.height, 3 / 4, accuracy: 0.02)
    }

    func testCompositionGridCyclesBackToNone() {
        var grid = CompositionGrid.none
        for _ in 0 ..< CompositionGrid.allCases.count {
            grid = grid.next
        }
        XCTAssertEqual(grid, .none)
    }

    func testThermalPolicyProgressivelyReducesDetectionRate() {
        XCTAssertLessThan(
            CameraLoadPolicy.detectionInterval(for: .nominal),
            CameraLoadPolicy.detectionInterval(for: .fair)
        )
        XCTAssertLessThan(
            CameraLoadPolicy.detectionInterval(for: .fair),
            CameraLoadPolicy.detectionInterval(for: .serious)
        )
        XCTAssertLessThan(
            CameraLoadPolicy.detectionInterval(for: .serious),
            CameraLoadPolicy.detectionInterval(for: .critical)
        )
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
