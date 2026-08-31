import AVFoundation
import Foundation

protocol BirdFocusControlling: Sendable {
    func focus(on normalizedPoint: CGPoint, device: AVCaptureDevice) async throws
    func resumeContinuousAutoFocus(on device: AVCaptureDevice) async throws
}

struct CameraDeviceBirdFocusController: BirdFocusControlling {
    func focus(on normalizedPoint: CGPoint, device: AVCaptureDevice) async throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let point = normalizedPoint.clampedToUnitSquare
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
        }
        if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        } else if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    func resumeContinuousAutoFocus(on device: AVCaptureDevice) async throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }
}

private extension CGPoint {
    var clampedToUnitSquare: CGPoint {
        CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}
