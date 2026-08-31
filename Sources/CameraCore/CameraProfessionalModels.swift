import Foundation

enum CameraControlMode: String, CaseIterable, Codable, Sendable {
    case automatic
    case professional

    var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .professional: "Pro"
        }
    }
}

struct CameraProfessionalCapabilities: Equatable, Sendable {
    let exposureBiasRange: ClosedRange<Float>?
    let isoRange: ClosedRange<Float>?
    let exposureDurationRange: ClosedRange<Double>?
    let supportsManualFocus: Bool

    var supportsProfessionalMode: Bool {
        (isoRange != nil && exposureDurationRange != nil) || supportsManualFocus
    }
}

struct CameraProfessionalSettings: Equatable, Sendable {
    var exposureBias: Float
    var iso: Float
    var exposureDuration: Double
    var lensPosition: Float

    func constrained(to capabilities: CameraProfessionalCapabilities) -> Self {
        var result = self
        if let range = capabilities.exposureBiasRange {
            result.exposureBias = exposureBias.clamped(to: range)
        }
        if let range = capabilities.isoRange {
            result.iso = iso.clamped(to: range)
        }
        if let range = capabilities.exposureDurationRange {
            result.exposureDuration = exposureDuration.clamped(to: range)
        }
        result.lensPosition = lensPosition.clamped(to: 0 ... 1)
        return result
    }
}

enum CameraProfessionalControl: Equatable, Sendable {
    case exposureBias(Float)
    case iso(Float)
    case exposureDuration(Double)
    case lensPosition(Float)
}

enum CameraProfessionalStatus: Equatable, Sendable {
    case ready
    case applying
    case unavailable(String)
    case failed(String)
}

enum CameraProfessionalFormatter {
    static func exposureBias(_ value: Float) -> String {
        String(format: "%+.1f EV", value)
    }

    static func iso(_ value: Float) -> String {
        "ISO \(Int(value.rounded()))"
    }

    static func shutter(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--" }
        if seconds >= 1 {
            return String(format: "%.1f s", seconds)
        }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    static func focus(_ lensPosition: Float) -> String {
        lensPosition >= 0.98 ? "∞" : String(format: "%.2f", lensPosition)
    }
}

enum CameraProfessionalScale {
    static func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.lowerBound > 0, range.upperBound > range.lowerBound else { return 0 }
        let lower = log(range.lowerBound)
        let upper = log(range.upperBound)
        return ((log(value.clamped(to: range)) - lower) / (upper - lower)).clamped(to: 0 ... 1)
    }

    static func value(_ normalized: Double, in range: ClosedRange<Double>) -> Double {
        guard range.lowerBound > 0, range.upperBound > range.lowerBound else { return range.lowerBound }
        let lower = log(range.lowerBound)
        let upper = log(range.upperBound)
        return exp(lower + normalized.clamped(to: 0 ... 1) * (upper - lower))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
