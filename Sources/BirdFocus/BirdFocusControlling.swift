import AVFoundation
import Foundation

protocol BirdFocusControlling: Sendable {
    func focus(on normalizedPoint: CGPoint, device: AVCaptureDevice) async throws
}
