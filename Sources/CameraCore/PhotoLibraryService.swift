import CoreLocation
import Photos

struct PhotoLibraryService: Sendable {
    func save(_ data: Data, location: CLLocation? = nil) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.unauthorized
        }

        let _: Void = try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = Date()
                request.location = location
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if saved {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryError.cannotSave)
                }
            }
        }
    }

    private func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum PhotoLibraryError: LocalizedError {
    case unauthorized
    case cannotSave

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "未获得照片保存权限"
        case .cannotSave:
            "照片保存失败"
        }
    }
}
