import AVFoundation
import Foundation

enum BirdFocusCoordinateMapper {
    static func layerPoint(
        fromNormalizedImagePoint point: CGPoint,
        imageSize: CGSize,
        in bounds: CGRect,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        let normalizedPoint = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        let scale = scale(
            imageSize: imageSize,
            boundsSize: bounds.size,
            videoGravity: videoGravity
        )
        let renderedSize = CGSize(
            width: imageSize.width * scale.width,
            height: imageSize.height * scale.height
        )
        let origin = CGPoint(
            x: bounds.midX - renderedSize.width / 2,
            y: bounds.midY - renderedSize.height / 2
        )

        return CGPoint(
            x: origin.x + normalizedPoint.x * renderedSize.width,
            y: origin.y + normalizedPoint.y * renderedSize.height
        )
    }

    @MainActor
    static func devicePoint(
        fromNormalizedImagePoint point: CGPoint,
        imageSize: CGSize,
        previewLayer: AVCaptureVideoPreviewLayer
    ) -> CGPoint {
        let pointInLayer = layerPoint(
            fromNormalizedImagePoint: point,
            imageSize: imageSize,
            in: previewLayer.bounds,
            videoGravity: previewLayer.videoGravity
        )
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: pointInLayer)
        return CGPoint(
            x: min(max(devicePoint.x, 0), 1),
            y: min(max(devicePoint.y, 0), 1)
        )
    }

    private static func scale(
        imageSize: CGSize,
        boundsSize: CGSize,
        videoGravity: AVLayerVideoGravity
    ) -> CGSize {
        let horizontalScale = boundsSize.width / imageSize.width
        let verticalScale = boundsSize.height / imageSize.height

        switch videoGravity {
        case .resizeAspect:
            let uniformScale = min(horizontalScale, verticalScale)
            return CGSize(width: uniformScale, height: uniformScale)
        case .resizeAspectFill:
            let uniformScale = max(horizontalScale, verticalScale)
            return CGSize(width: uniformScale, height: uniformScale)
        default:
            return CGSize(width: horizontalScale, height: verticalScale)
        }
    }
}
