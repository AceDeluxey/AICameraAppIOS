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

        let desiredRatio = size.width >= size.height
            ? aspectRatio.landscapeValue
            : aspectRatio.portraitValue
        let currentRatio = size.width / size.height
        let cropRect: CGRect
        if currentRatio > desiredRatio {
            let width = size.height * desiredRatio
            cropRect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        } else {
            let height = size.width / desiredRatio
            cropRect = CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }

        guard let cgImage = normalized.cgImage?.cropping(to: cropRect.integral) else {
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
