import CoreImage
import CoreML
import CoreVideo
import Foundation

struct CoreMLBirdClassifierFeatureNames: Equatable, Sendable {
    let input: String
    let logits: String

    init(input: String = "input", logits: String = "output") {
        self.input = input
        self.logits = logits
    }
}

final class CoreMLBirdClassifier: BirdClassifying, @unchecked Sendable {
    static let inputSize = 224
    static let expectedClassCount = 10964
    static let imageNetMean: [Float] = [0.485, 0.456, 0.406]
    static let imageNetStandardDeviation: [Float] = [0.229, 0.224, 0.225]

    private let model: MLModel
    private let labels: [BirdClassificationLabel]
    private let featureNames: CoreMLBirdClassifierFeatureNames
    private let postprocessor: BirdClassificationPostprocessor
    private let prior: (any BirdPriorWeighting)?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(
        model: MLModel,
        labels: [BirdClassificationLabel],
        featureNames: CoreMLBirdClassifierFeatureNames = .init(),
        postprocessor: BirdClassificationPostprocessor = .init(),
        prior: (any BirdPriorWeighting)? = nil
    ) throws {
        self.model = model
        self.labels = labels
        self.featureNames = featureNames
        self.postprocessor = postprocessor
        self.prior = prior
        try Self.validateModelContract(
            model.modelDescription,
            labels: labels,
            featureNames: featureNames
        )
    }

    func classify(
        _ pixelBuffer: CVPixelBuffer,
        birdBoundingBox: CGRect
    ) async throws -> [BirdClassification] {
        let inputArray = try makeModelInput(
            from: pixelBuffer,
            birdBoundingBox: birdBoundingBox
        )
        let input = try MLDictionaryFeatureProvider(dictionary: [
            featureNames.input: MLFeatureValue(multiArray: inputArray),
        ])
        let prediction = try await model.prediction(from: input)
        guard let logits = prediction.featureValue(for: featureNames.logits)?.multiArrayValue else {
            throw CoreMLBirdClassifierError.missingOutput(featureNames.logits)
        }
        return postprocessor.classifications(logits: logits.floatValues, labels: labels, prior: prior)
    }

    static func loadBundled(
        modelResourceName: String = "BirdClassifier",
        labelResourceName: String = "bird_labels_dongniao",
        bundle: Bundle = .main,
        configuration: MLModelConfiguration = MLModelConfiguration(),
        prior: (any BirdPriorWeighting)? = nil
    ) throws -> CoreMLBirdClassifier {
        guard let modelURL = bundle.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
            throw CoreMLBirdClassifierError.modelResourceMissing(modelResourceName)
        }
        guard let labelURL = bundle.url(forResource: labelResourceName, withExtension: "txt") else {
            throw CoreMLBirdClassifierError.labelResourceMissing(labelResourceName)
        }
        let contents = try String(contentsOf: labelURL, encoding: .utf8)
        let labels = BirdClassificationLabelParser.parse(contents)
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        return try CoreMLBirdClassifier(model: model, labels: labels, prior: prior)
    }

    private static func validateModelContract(
        _ description: MLModelDescription,
        labels: [BirdClassificationLabel],
        featureNames: CoreMLBirdClassifierFeatureNames
    ) throws {
        guard labels.count == expectedClassCount else {
            throw CoreMLBirdClassifierError.invalidLabelCount(labels.count)
        }
        guard let input = description.inputDescriptionsByName[featureNames.input],
              input.type == .multiArray,
              input.multiArrayConstraint?.shape.map(\.intValue) == [1, 3, inputSize, inputSize]
        else {
            throw CoreMLBirdClassifierError.invalidInputContract
        }
        guard let output = description.outputDescriptionsByName[featureNames.logits],
              output.type == .multiArray,
              output.multiArrayConstraint?.shape.map(\.intValue).last == expectedClassCount
        else {
            throw CoreMLBirdClassifierError.invalidOutputContract
        }
    }

    private func makeModelInput(
        from source: CVPixelBuffer,
        birdBoundingBox: CGRect
    ) throws -> MLMultiArray {
        let image = CIImage(cvPixelBuffer: source)
        guard image.extent.width > 0, image.extent.height > 0 else {
            throw CoreMLBirdClassifierError.invalidSourceBuffer
        }
        let crop = Self.squareCropRect(
            normalizedBox: birdBoundingBox,
            imageExtent: image.extent,
            expansion: 1.25
        )
        guard crop.width > 0, crop.height > 0 else {
            throw CoreMLBirdClassifierError.invalidBirdBoundingBox
        }

        let destination = try makeBGRAInputBuffer()
        let croppedImage = image.cropped(to: crop)
        let scale = CGAffineTransform(
            scaleX: CGFloat(Self.inputSize) / crop.width,
            y: CGFloat(Self.inputSize) / crop.height
        )
        let translated = croppedImage
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: scale)
        imageContext.render(
            translated,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: Self.inputSize, height: Self.inputSize),
            colorSpace: colorSpace
        )
        return try normalizedCHWArray(fromBGRA: destination)
    }

    static func squareCropRect(
        normalizedBox: CGRect,
        imageExtent: CGRect,
        expansion: CGFloat
    ) -> CGRect {
        let clipped = normalizedBox.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return .null }

        let center = CGPoint(
            x: imageExtent.minX + clipped.midX * imageExtent.width,
            y: imageExtent.minY + (1 - clipped.midY) * imageExtent.height
        )
        let side = max(
            clipped.width * imageExtent.width,
            clipped.height * imageExtent.height
        ) * max(expansion, 1)
        return CGRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        ).intersection(imageExtent)
    }

    private func makeBGRAInputBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputSize,
            Self.inputSize,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw CoreMLBirdClassifierError.cannotCreateInputBuffer(status)
        }
        return buffer
    }

    private func normalizedCHWArray(fromBGRA buffer: CVPixelBuffer) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [1, 3, Self.inputSize, Self.inputSize] as [NSNumber],
            dataType: .float32
        )
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw CoreMLBirdClassifierError.invalidSourceBuffer
        }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let channelSize = Self.inputSize * Self.inputSize
        let output = array.dataPointer.assumingMemoryBound(to: Float.self)
        for row in 0 ..< Self.inputSize {
            for column in 0 ..< Self.inputSize {
                let sourceOffset = row * rowBytes + column * 4
                let pixelOffset = row * Self.inputSize + column
                let red = Float(bytes[sourceOffset + 2]) / 255
                let green = Float(bytes[sourceOffset + 1]) / 255
                let blue = Float(bytes[sourceOffset]) / 255
                output[pixelOffset] = (red - Self.imageNetMean[0])
                    / Self.imageNetStandardDeviation[0]
                output[channelSize + pixelOffset] = (green - Self.imageNetMean[1])
                    / Self.imageNetStandardDeviation[1]
                output[channelSize * 2 + pixelOffset] = (blue - Self.imageNetMean[2])
                    / Self.imageNetStandardDeviation[2]
            }
        }
        return array
    }
}

enum CoreMLBirdClassifierError: LocalizedError {
    case modelResourceMissing(String)
    case labelResourceMissing(String)
    case invalidLabelCount(Int)
    case invalidInputContract
    case invalidOutputContract
    case invalidSourceBuffer
    case invalidBirdBoundingBox
    case cannotCreateInputBuffer(CVReturn)
    case missingOutput(String)

    var errorDescription: String? {
        switch self {
        case let .modelResourceMissing(name): "鸟种分类模型资源不存在：\(name).mlmodelc"
        case let .labelResourceMissing(name): "鸟种标签资源不存在：\(name).txt"
        case let .invalidLabelCount(count): "鸟种标签数量应为 10964，实际为 \(count)"
        case .invalidInputContract: "鸟种模型输入必须为 float32 [1,3,224,224]"
        case .invalidOutputContract: "鸟种模型输出必须包含 10964 个 logits"
        case .invalidSourceBuffer: "鸟种分类输入帧无效"
        case .invalidBirdBoundingBox: "鸟种分类目标区域无效"
        case let .cannotCreateInputBuffer(status): "无法创建鸟种分类输入缓冲区：\(status)"
        case let .missingOutput(name): "鸟种模型缺少输出：\(name)"
        }
    }
}

private extension MLMultiArray {
    var floatValues: [Float] {
        (0 ..< count).map { self[$0].floatValue }
    }
}
