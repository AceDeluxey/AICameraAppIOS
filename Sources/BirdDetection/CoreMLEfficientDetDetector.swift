import CoreImage
import CoreML
import CoreVideo
import Foundation

struct CoreMLEfficientDetFeatureNames: Equatable, Sendable {
    let input: String
    let locations: String
    let classes: String
    let scores: String
    let numberOfDetections: String

    init(
        input: String = "image",
        locations: String = "locations",
        classes: String = "classes",
        scores: String = "scores",
        numberOfDetections: String = "num_detections"
    ) {
        self.input = input
        self.locations = locations
        self.classes = classes
        self.scores = scores
        self.numberOfDetections = numberOfDetections
    }
}

final class CoreMLEfficientDetDetector: BirdDetecting, @unchecked Sendable {
    static let inputWidth = 448
    static let inputHeight = 448

    private let model: MLModel
    private let featureNames: CoreMLEfficientDetFeatureNames
    private let postprocessor: EfficientDetPostprocessor
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(
        model: MLModel,
        featureNames: CoreMLEfficientDetFeatureNames = .init(),
        postprocessor: EfficientDetPostprocessor = .init()
    ) throws {
        self.model = model
        self.featureNames = featureNames
        self.postprocessor = postprocessor
        try Self.validateModelContract(model.modelDescription, featureNames: featureNames)
    }

    func detectBirds(in pixelBuffer: CVPixelBuffer) async throws -> [BirdObservation] {
        let resizedBuffer = try makeModelInput(from: pixelBuffer)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            featureNames.input: MLFeatureValue(pixelBuffer: resizedBuffer),
        ])
        let prediction = try model.prediction(from: input)
        let rawOutput = try rawOutput(from: prediction)
        return postprocessor.observations(from: rawOutput)
    }

    static func loadBundled(
        resourceName: String = "EfficientDetLite2",
        bundle: Bundle = .main,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws -> CoreMLEfficientDetDetector {
        guard let modelURL = bundle.url(forResource: resourceName, withExtension: "mlmodelc") else {
            throw CoreMLEfficientDetError.modelResourceMissing(resourceName)
        }
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        return try CoreMLEfficientDetDetector(model: model)
    }

    private static func validateModelContract(
        _ description: MLModelDescription,
        featureNames: CoreMLEfficientDetFeatureNames
    ) throws {
        guard
            let inputDescription = description.inputDescriptionsByName[featureNames.input],
            inputDescription.type == .image,
            let imageConstraint = inputDescription.imageConstraint,
            imageConstraint.pixelsWide == inputWidth,
            imageConstraint.pixelsHigh == inputHeight
        else {
            throw CoreMLEfficientDetError.invalidInputContract
        }

        let expectedOutputs = [
            featureNames.locations,
            featureNames.classes,
            featureNames.scores,
            featureNames.numberOfDetections,
        ]
        let missingOutputs = expectedOutputs.filter {
            description.outputDescriptionsByName[$0]?.type != .multiArray
        }
        if !missingOutputs.isEmpty {
            throw CoreMLEfficientDetError.invalidOutputContract(missingOutputs)
        }
    }

    private func makeModelInput(from source: CVPixelBuffer) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputWidth,
            Self.inputHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else {
            throw CoreMLEfficientDetError.cannotCreateInputBuffer(status)
        }

        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw CoreMLEfficientDetError.invalidSourceBuffer
        }

        let sourceImage = CIImage(cvPixelBuffer: source)
        let scale = CGAffineTransform(
            scaleX: CGFloat(Self.inputWidth) / CGFloat(sourceWidth),
            y: CGFloat(Self.inputHeight) / CGFloat(sourceHeight)
        )
        let bounds = CGRect(x: 0, y: 0, width: Self.inputWidth, height: Self.inputHeight)
        imageContext.render(
            sourceImage.transformed(by: scale),
            to: destination,
            bounds: bounds,
            colorSpace: colorSpace
        )
        return destination
    }

    private func rawOutput(from prediction: any MLFeatureProvider) throws -> EfficientDetRawOutput {
        let locations = try multiArray(named: featureNames.locations, in: prediction)
        let classes = try multiArray(named: featureNames.classes, in: prediction)
        let scores = try multiArray(named: featureNames.scores, in: prediction)
        let numberOfDetections = try multiArray(
            named: featureNames.numberOfDetections,
            in: prediction
        )
        guard numberOfDetections.count > 0 else {
            throw CoreMLEfficientDetError.emptyOutput(featureNames.numberOfDetections)
        }

        return EfficientDetRawOutput(
            locations: locations.floatValues,
            classes: classes.floatValues,
            scores: scores.floatValues,
            numberOfDetections: numberOfDetections[0].floatValue
        )
    }

    private func multiArray(
        named name: String,
        in prediction: any MLFeatureProvider
    ) throws -> MLMultiArray {
        guard let array = prediction.featureValue(for: name)?.multiArrayValue else {
            throw CoreMLEfficientDetError.missingOutput(name)
        }
        return array
    }
}

enum CoreMLEfficientDetError: LocalizedError {
    case modelResourceMissing(String)
    case invalidInputContract
    case invalidOutputContract([String])
    case invalidSourceBuffer
    case cannotCreateInputBuffer(CVReturn)
    case missingOutput(String)
    case emptyOutput(String)

    var errorDescription: String? {
        switch self {
        case let .modelResourceMissing(name):
            "Core ML 模型资源不存在：\(name).mlmodelc"
        case .invalidInputContract:
            "Core ML 模型必须提供名为 image 的 448×448 图像输入"
        case let .invalidOutputContract(names):
            "Core ML 模型缺少多数组输出：\(names.joined(separator: ", "))"
        case .invalidSourceBuffer:
            "相机帧尺寸无效"
        case let .cannotCreateInputBuffer(status):
            "无法创建 Core ML 输入缓冲区：\(status)"
        case let .missingOutput(name):
            "Core ML 推理缺少输出：\(name)"
        case let .emptyOutput(name):
            "Core ML 推理输出为空：\(name)"
        }
    }
}

private extension MLMultiArray {
    var floatValues: [Float] {
        (0 ..< count).map { self[$0].floatValue }
    }
}
