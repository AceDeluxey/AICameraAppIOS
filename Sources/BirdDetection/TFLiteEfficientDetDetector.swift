import CoreImage
import CoreVideo
import Foundation

enum TFLiteTensorDataType: Equatable, Sendable {
    case float32
    case uint8
    case unsupported(String)
}

struct TFLiteTensorDescriptor: Equatable, Sendable {
    let shape: [Int]
    let dataType: TFLiteTensorDataType
}

protocol TFLiteEfficientDetRunning: AnyObject {
    var inputDescriptor: TFLiteTensorDescriptor { get }
    var outputDescriptors: [TFLiteTensorDescriptor] { get }

    func invoke(input: Data) throws -> [Data]
}

final class TFLiteEfficientDetDetector: BirdDetecting, @unchecked Sendable {
    static let inputWidth = 448
    static let inputHeight = 448
    static let inputByteCount = inputWidth * inputHeight * 3

    private static let expectedInput = TFLiteTensorDescriptor(
        shape: [1, inputHeight, inputWidth, 3],
        dataType: .uint8
    )
    private static let expectedOutputs = [
        TFLiteTensorDescriptor(shape: [1, 25, 4], dataType: .float32),
        TFLiteTensorDescriptor(shape: [1, 25], dataType: .float32),
        TFLiteTensorDescriptor(shape: [1, 25], dataType: .float32),
        TFLiteTensorDescriptor(shape: [1], dataType: .float32),
    ]

    private let runtime: any TFLiteEfficientDetRunning
    private let postprocessor: EfficientDetPostprocessor
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(
        runtime: any TFLiteEfficientDetRunning,
        postprocessor: EfficientDetPostprocessor = .init()
    ) throws {
        guard runtime.inputDescriptor == Self.expectedInput else {
            throw TFLiteEfficientDetError.invalidInputContract(runtime.inputDescriptor)
        }
        guard runtime.outputDescriptors == Self.expectedOutputs else {
            throw TFLiteEfficientDetError.invalidOutputContract(runtime.outputDescriptors)
        }
        self.runtime = runtime
        self.postprocessor = postprocessor
    }

    func detectBirds(in pixelBuffer: CVPixelBuffer) async throws -> [BirdObservation] {
        let input = try makeRGBInput(from: pixelBuffer)
        let outputs = try runtime.invoke(input: input)
        guard outputs.count == Self.expectedOutputs.count else {
            throw TFLiteEfficientDetError.invalidOutputCount(outputs.count)
        }

        let locations = try outputs[0].float32Values(expectedCount: 25 * 4)
        let classes = try outputs[1].float32Values(expectedCount: 25)
        let scores = try outputs[2].float32Values(expectedCount: 25)
        let count = try outputs[3].float32Values(expectedCount: 1)
        return postprocessor.observations(
            from: EfficientDetRawOutput(
                locations: locations,
                classes: classes,
                scores: scores,
                numberOfDetections: count[0]
            )
        )
    }

    private func makeRGBInput(from source: CVPixelBuffer) throws -> Data {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw TFLiteEfficientDetError.invalidSourceBuffer
        }

        let image = CIImage(cvPixelBuffer: source).transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(Self.inputWidth) / CGFloat(sourceWidth),
                y: CGFloat(Self.inputHeight) / CGFloat(sourceHeight)
            )
        )
        let bounds = CGRect(x: 0, y: 0, width: Self.inputWidth, height: Self.inputHeight)
        var rgba = [UInt8](repeating: 0, count: Self.inputWidth * Self.inputHeight * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            imageContext.render(
                image,
                toBitmap: address,
                rowBytes: Self.inputWidth * 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        var rgb = Data(count: Self.inputByteCount)
        rgb.withUnsafeMutableBytes { destination in
            guard let output = destination.bindMemory(to: UInt8.self).baseAddress else { return }
            for pixel in 0 ..< Self.inputWidth * Self.inputHeight {
                let sourceOffset = pixel * 4
                let destinationOffset = pixel * 3
                output[destinationOffset] = rgba[sourceOffset]
                output[destinationOffset + 1] = rgba[sourceOffset + 1]
                output[destinationOffset + 2] = rgba[sourceOffset + 2]
            }
        }
        return rgb
    }
}

enum TFLiteEfficientDetError: LocalizedError {
    case invalidInputContract(TFLiteTensorDescriptor)
    case invalidOutputContract([TFLiteTensorDescriptor])
    case invalidSourceBuffer
    case invalidOutputCount(Int)
    case invalidOutputByteCount(actual: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidInputContract(actual):
            "TFLite 输入接口错误：\(actual)"
        case let .invalidOutputContract(actual):
            "TFLite 输出接口错误：\(actual)"
        case .invalidSourceBuffer:
            "相机帧尺寸无效"
        case let .invalidOutputCount(actual):
            "TFLite 输出数量错误：\(actual)，预期 4"
        case let .invalidOutputByteCount(actual, expected):
            "TFLite 输出字节数错误：\(actual)，预期 \(expected)"
        }
    }
}

private extension Data {
    func float32Values(expectedCount: Int) throws -> [Float] {
        let expectedByteCount = expectedCount * MemoryLayout<Float>.size
        guard count == expectedByteCount else {
            throw TFLiteEfficientDetError.invalidOutputByteCount(
                actual: count,
                expected: expectedByteCount
            )
        }
        return withUnsafeBytes { bytes in
            (0 ..< expectedCount).map { index in
                bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<Float>.size,
                    as: Float.self
                )
            }
        }
    }
}

#if canImport(TensorFlowLite)
import TensorFlowLite

final class TensorFlowLiteEfficientDetRuntime: TFLiteEfficientDetRunning {
    let inputDescriptor: TFLiteTensorDescriptor
    let outputDescriptors: [TFLiteTensorDescriptor]

    private let interpreter: Interpreter

    init(modelPath: String, threadCount: Int = 2) throws {
        var options = Interpreter.Options()
        options.threadCount = max(threadCount, 1)
        let interpreter = try Interpreter(modelPath: modelPath, options: options)
        try interpreter.allocateTensors()
        self.interpreter = interpreter
        inputDescriptor = try Self.descriptor(for: interpreter.input(at: 0))
        outputDescriptors = try (0 ..< interpreter.outputTensorCount).map {
            try Self.descriptor(for: interpreter.output(at: $0))
        }
    }

    func invoke(input: Data) throws -> [Data] {
        try interpreter.copy(input, toInputAt: 0)
        try interpreter.invoke()
        return try (0 ..< interpreter.outputTensorCount).map {
            try interpreter.output(at: $0).data
        }
    }

    private static func descriptor(for tensor: Tensor) throws -> TFLiteTensorDescriptor {
        let dataType: TFLiteTensorDataType = switch tensor.dataType {
        case .float32:
            .float32
        case .uInt8:
            .uint8
        default:
            .unsupported(String(describing: tensor.dataType))
        }
        return TFLiteTensorDescriptor(
            shape: tensor.shape.dimensions,
            dataType: dataType
        )
    }
}
#endif
