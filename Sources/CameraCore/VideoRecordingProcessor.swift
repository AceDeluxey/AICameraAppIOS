import AVFoundation
import Foundation

final class VideoRecordingProcessor: NSObject, AVCaptureFileOutputRecordingDelegate {
    typealias Completion = @Sendable (Result<URL, any Error>) -> Void

    private let didStart: @Sendable () -> Void
    private let completion: Completion

    init(
        didStart: @escaping @Sendable () -> Void,
        completion: @escaping Completion
    ) {
        self.didStart = didStart
        self.completion = completion
    }

    func fileOutput(
        _: AVCaptureFileOutput,
        didStartRecordingTo _: URL,
        from _: [AVCaptureConnection]
    ) {
        didStart()
    }

    func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: (any Error)?
    ) {
        if let error = error as NSError? {
            let finishedSuccessfully = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey]
                as? Bool == true
            if !finishedSuccessfully {
                completion(.failure(error))
                return
            }
        }
        completion(.success(outputFileURL))
    }
}
