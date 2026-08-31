import AVFoundation
import UIKit

final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    typealias Completion = @Sendable (Result<(Data, UIImage), Error>) -> Void

    private let aspectRatio: PhotoAspectRatio
    private let completion: Completion

    init(aspectRatio: PhotoAspectRatio, completion: @escaping Completion) {
        self.aspectRatio = aspectRatio
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(.failure(PhotoCaptureError.invalidPhotoData))
            return
        }

        do {
            let cropped = try Self.centerCrop(image, to: aspectRatio)
            guard let croppedData = cropped.jpegData(compressionQuality: 0.96) else {
                throw PhotoCaptureError.cannotEncodePhoto
            }
            completion(.success((croppedData, cropped)))
        } catch {
            completion(.failure(error))
        }
    }

    static func centerCrop(_ image: UIImage, to aspectRatio: PhotoAspectRatio) throws -> UIImage {
        let normalized = normalizeOrientation(image)
        let size = normalized.size
        guard size.width > 0, size.height > 0 else {
            throw PhotoCaptureError.invalidPhotoData
        }

        let landscape = size.width >= size.height
        let units: CGSize = switch (aspectRatio, landscape) {
        case (.fourByThree, true):
            CGSize(width: 4, height: 3)
        case (.fourByThree, false):
            CGSize(width: 3, height: 4)
        case (.sixteenByNine, true):
            CGSize(width: 16, height: 9)
        case (.sixteenByNine, false):
            CGSize(width: 9, height: 16)
        }
        let scale = floor(min(size.width / units.width, size.height / units.height))
        guard scale >= 1 else { throw PhotoCaptureError.cannotCropPhoto }
        let cropSize = CGSize(width: units.width * scale, height: units.height * scale)
        let cropRect = CGRect(
            x: floor((size.width - cropSize.width) / 2),
            y: floor((size.height - cropSize.height) / 2),
            width: cropSize.width,
            height: cropSize.height
        )

        guard let cgImage = normalized.cgImage?.cropping(to: cropRect) else {
            throw PhotoCaptureError.cannotCropPhoto
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

enum PhotoCaptureError: LocalizedError {
    case invalidPhotoData
    case cannotEncodePhoto
    case cannotCropPhoto

    var errorDescription: String? {
        switch self {
        case .invalidPhotoData:
            "相机返回了无效照片"
        case .cannotEncodePhoto:
            "无法编码照片"
        case .cannotCropPhoto:
            "无法裁切照片"
        }
    }
}
