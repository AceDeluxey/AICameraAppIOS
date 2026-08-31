import Foundation

enum BirdDetectionRuntimeFactory {
    static func loadBundledDetector(bundle: Bundle = .main) throws -> any BirdDetecting {
        if bundle.url(forResource: "EfficientDetLite2", withExtension: "mlmodelc") != nil {
            return try CoreMLEfficientDetDetector.loadBundled(bundle: bundle)
        }

        #if canImport(TensorFlowLite)
            if let modelPath = bundle.path(forResource: "efficientdet-lite2", ofType: "tflite") {
                let runtime = try TensorFlowLiteEfficientDetRuntime(modelPath: modelPath)
                return try TFLiteEfficientDetDetector(runtime: runtime)
            }
        #endif

        throw BirdDetectionRuntimeError.modelUnavailable
    }
}

enum BirdDetectionRuntimeError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "鸟体检测模型尚未安装"
        }
    }
}
