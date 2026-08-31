@testable import AICameraApp
import CoreVideo
import XCTest

final class BirdDetectionSchedulerTests: XCTestCase {
    func testDropsFrameWhileInferenceIsRunning() async throws {
        let detector = StubBirdDetector(delayNanoseconds: 80_000_000)
        let scheduler = BirdDetectionScheduler(detector: detector, minimumInterval: 0)
        let pixelBuffer = try makePixelBuffer()

        async let first = scheduler.submit(pixelBuffer: pixelBuffer, presentationTimeSeconds: 0)
        try await Task.sleep(nanoseconds: 10_000_000)
        let second = try await scheduler.submit(pixelBuffer: pixelBuffer, presentationTimeSeconds: 0.01)
        let firstResult = try await first
        let callCount = await detector.callCount

        XCTAssertNotNil(firstResult)
        XCTAssertNil(second)
        XCTAssertEqual(callCount, 1)
    }

    func testThrottlesFramesInsideMinimumInterval() async throws {
        let detector = StubBirdDetector(delayNanoseconds: 0)
        let scheduler = BirdDetectionScheduler(detector: detector, minimumInterval: 0.1)
        let pixelBuffer = try makePixelBuffer()

        let first = try await scheduler.submit(pixelBuffer: pixelBuffer, presentationTimeSeconds: 1)
        let throttled = try await scheduler.submit(pixelBuffer: pixelBuffer, presentationTimeSeconds: 1.05)
        let next = try await scheduler.submit(pixelBuffer: pixelBuffer, presentationTimeSeconds: 1.1)
        let callCount = await detector.callCount

        XCTAssertNotNil(first)
        XCTAssertNil(throttled)
        XCTAssertNotNil(next)
        XCTAssertEqual(callCount, 2)
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            1,
            1,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )

        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }
}

private actor StubBirdDetector: BirdDetecting {
    private(set) var callCount = 0
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func detectBirds(in pixelBuffer: CVPixelBuffer) async throws -> [BirdObservation] {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return [BirdObservation(boundingBox: .zero, confidence: 0.9)]
    }
}
