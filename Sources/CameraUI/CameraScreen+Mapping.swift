import SwiftUI

extension CameraScreen {
    func mappedBirdBox(_ box: CGRect, in size: CGSize) -> CGRect {
        let imageSize = camera.birdImageSize == .zero
            ? CGSize(width: 3, height: 4)
            : camera.birdImageSize
        let bounds = CGRect(origin: .zero, size: size)
        let topLeft = BirdFocusCoordinateMapper.layerPoint(
            fromNormalizedImagePoint: CGPoint(x: box.minX, y: box.minY),
            imageSize: imageSize,
            in: bounds
        )
        let bottomRight = BirdFocusCoordinateMapper.layerPoint(
            fromNormalizedImagePoint: CGPoint(x: box.maxX, y: box.maxY),
            imageSize: imageSize,
            in: bounds
        )
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).intersection(bounds)
    }
}
