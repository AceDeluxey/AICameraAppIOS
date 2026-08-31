@testable import AICameraApp
import CoreVideo
import XCTest

final class TFLiteEfficientDetDetectorTests: XCTestCase {
    func testRejectsInvalidModelContract() {
        let runtime = RuntimeStub(
            inputDescriptor: .init(shape: [1, 224, 224, 3], dataType: .uint8),
            outputDescriptors: Self.validOutputs,
            outputs: []
        )

        XCTAssertThrowsError(try TFLiteEfficientDetDetector(runtime: runtime)) { error in
            guard case TFLiteEfficientDetError.invalidInputContract = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRunsUint8RGBInputAndPostprocessesOutputs() async throws {
        let runtime = RuntimeStub(
            inputDescriptor: Self.validInput,
            outputDescriptors: Self.validOutputs,
            outputs: [
                floatData([0.2, 0.1, 0.8, 0.6] + [Float](repeating: 0, count: 96)),
                floatData([14] + [Float](repeating: 0, count: 24)),
                floatData([0.75] + [Float](repeating: 0, count: 24)),
                floatData([1]),
            ]
        )
        let detector = try TFLiteEfficientDetDetector(runtime: runtime)

        let observations = try await detector.detectBirds(in: makeRedPixelBuffer())
        let observation = try XCTUnwrap(observations.first)

        XCTAssertEqual(runtime.lastInput?.count, TFLiteEfficientDetDetector.inputByteCount)
        XCTAssertEqual(runtime.lastInput?.prefix(3), Data([255, 0, 0]))
        XCTAssertEqual(observation.boundingBox.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(observation.confidence, 0.75)
    }

    func testRejectsTruncatedRuntimeOutput() async throws {
        let runtime = RuntimeStub(
            inputDescriptor: Self.validInput,
            outputDescriptors: Self.validOutputs,
            outputs: [Data(), Data(), Data(), Data()]
        )
        let detector = try TFLiteEfficientDetDetector(runtime: runtime)

        do {
            _ = try await detector.detectBirds(in: makeRedPixelBuffer())
            XCTFail("Expected output byte count error")
        } catch TFLiteEfficientDetError.invalidOutputByteCount {
            // Expected.
        }
    }

    private static let validInput = TFLiteTensorDescriptor(
        shape: [1, 448, 448, 3],
        dataType: .uint8
    )
    private static let validOutputs = [
        TFLiteTensorDescriptor(shape: [1, 25, 4], dataType: .float32),
        TFLiteTensorDescriptor(shape: [1, 25], dataType: .float32),
        TFLiteTensorDescriptor(shape: [1, 25], dataType: .float32),
        TFLiteTensorDescriptor(shape: [1], dataType: .float32),
    ]

    private func makeRedPixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            1,
            1,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "TFLiteEfficientDetDetectorTests", code: Int(status))
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "TFLiteEfficientDetDetectorTests", code: -1)
        }
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        bytes[0] = 0
        bytes[1] = 0
        bytes[2] = 255
        bytes[3] = 255
        return pixelBuffer
    }

    private func floatData(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private final class RuntimeStub: TFLiteEfficientDetRunning {
    let inputDescriptor: TFLiteTensorDescriptor
    let outputDescriptors: [TFLiteTensorDescriptor]
    let outputs: [Data]
    private(set) var lastInput: Data?

    init(
        inputDescriptor: TFLiteTensorDescriptor,
        outputDescriptors: [TFLiteTensorDescriptor],
        outputs: [Data]
    ) {
        self.inputDescriptor = inputDescriptor
        self.outputDescriptors = outputDescriptors
        self.outputs = outputs
    }

    func invoke(input: Data) throws -> [Data] {
        lastInput = input
        return outputs
    }
}
