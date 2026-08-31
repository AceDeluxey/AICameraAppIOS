import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

struct CameraFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTimeSeconds: TimeInterval
}

final class CameraFrameOutput: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureOutput: AVCaptureVideoDataOutput

    var frameHandler: ((CameraFrame) -> Void)?

    private let outputQueue = DispatchQueue(label: "com.acedeluxey.aicamera.video-output")

    override init() {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        captureOutput = output

        super.init()
        output.setSampleBufferDelegate(self, queue: outputQueue)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let frameHandler,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameHandler(
            CameraFrame(
                pixelBuffer: pixelBuffer,
                presentationTimeSeconds: CMTimeGetSeconds(timestamp)
            )
        )
    }
}
