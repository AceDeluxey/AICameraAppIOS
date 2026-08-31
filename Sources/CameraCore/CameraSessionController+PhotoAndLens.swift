import AVFoundation
import UIKit

extension CameraSessionController {
    func finishCapture(
        id: Int64,
        result: Result<(Data, UIImage), any Error>
    ) {
        sessionQueue.async { [weak self] in
            self?.photoProcessors[id] = nil
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch result {
            case let .success((data, image)):
                do {
                    let location = includesLocationMetadata
                        ? await photoLocationProvider.currentLocation()
                        : nil
                    try await photoLibrary.save(data, location: location)
                    latestThumbnail = image
                    captureStatus = .saved
                } catch {
                    captureStatus = .failed(error.localizedDescription)
                }
            case let .failure(error):
                captureStatus = .failed(error.localizedDescription)
            }
        }
    }

    func switchLens(to id: String) {
        let devices = physicalBackCameras()
        guard let device = devices.first(where: { $0.uniqueID == id }),
              let currentInput = activeInput
        else { return }

        do {
            let replacement = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.removeInput(currentInput)
            if session.canAddInput(replacement) {
                session.addInput(replacement)
                activeInput = replacement
                activeDevice = device
                activeDeviceID = device.uniqueID
                updateLensState(for: device)
            } else {
                session.addInput(currentInput)
            }
            session.commitConfiguration()
            applyStabilization()
            generateCapabilityReport()
        } catch {
            Task { @MainActor in self.state = .failed(error.localizedDescription) }
        }
    }

    func applyZoomFactor(_ requestedFactor: CGFloat) {
        guard let activeDevice else { return }
        let factor = min(
            max(requestedFactor, activeDevice.minAvailableVideoZoomFactor),
            activeDevice.maxAvailableVideoZoomFactor
        )
        do {
            try activeDevice.lockForConfiguration()
            activeDevice.videoZoomFactor = factor
            activeDevice.unlockForConfiguration()
            Task { @MainActor in self.zoomFactor = factor }
        } catch {
            Task { @MainActor in self.captureStatus = .failed(error.localizedDescription) }
        }
    }

    func updateLensState(for device: AVCaptureDevice) {
        let devices = physicalBackCameras()
        let wideFieldOfView = devices.first(where: { $0.deviceType == .builtInWideAngleCamera })?
            .activeFormat.videoFieldOfView ?? device.activeFormat.videoFieldOfView
        let options = devices.map { camera -> CameraLensOption in
            let factor = max(0.1, CGFloat(wideFieldOfView / camera.activeFormat.videoFieldOfView))
            return CameraLensOption(
                id: camera.uniqueID,
                displayName: camera.localizedName,
                zoomLabel: Self.zoomLabel(for: factor),
                nominalZoomFactor: factor
            )
        }.sorted { $0.nominalZoomFactor < $1.nominalZoomFactor }
        let range = device.minAvailableVideoZoomFactor ... device.maxAvailableVideoZoomFactor
        Task { @MainActor in
            self.availableLenses = options
            self.activeLensID = device.uniqueID
            self.zoomRange = range
            self.zoomFactor = device.videoZoomFactor
        }
    }

    func physicalBackCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        ).devices
    }

    static func zoomLabel(for factor: CGFloat) -> String {
        if abs(factor.rounded() - factor) < 0.08 {
            return "\(Int(factor.rounded()))×"
        }
        return String(format: "%.1f×", factor)
    }
}
