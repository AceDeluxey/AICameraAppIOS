import AVFoundation
import Foundation

struct StabilizationCapability: Equatable, Sendable {
    let supportedModes: Set<AVCaptureVideoStabilizationMode>

    func supports(_ mode: AVCaptureVideoStabilizationMode) -> Bool {
        supportedModes.contains(mode)
    }
}
