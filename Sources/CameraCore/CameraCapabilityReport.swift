import Foundation

struct CameraCapabilityReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let operatingSystem: String
    let activeDeviceID: String?
    let devices: [CameraDeviceCapability]

    var textDescription: String {
        var lines = [
            "AICameraApp Camera Capability Report",
            "Generated: \(generatedAt.ISO8601Format())",
            "OS: \(operatingSystem)",
            "Active device: \(activeDeviceID ?? "none")",
            "Devices: \(devices.count)",
        ]

        for device in devices {
            lines.append("")
            lines.append("[\(device.position)] \(device.name)")
            lines.append("  ID: \(device.id)")
            lines.append("  Type: \(device.type) | Virtual: \(device.isVirtual)")
            lines.append("  Constituents: \(device.constituentDeviceIDs.joined(separator: ", "))")
            lines.append("  Focus: \(device.focusModes.joined(separator: ", ")) | POI: \(device.supportsFocusPoint)")
            let exposureModes = device.exposureModes.joined(separator: ", ")
            lines.append("  Exposure: \(exposureModes) | POI: \(device.supportsExposurePoint)")
            lines.append("  Zoom: \(device.minimumZoomFactor)-\(device.maximumZoomFactor)")
            lines.append("  Formats: \(device.formats.count)")

            for format in device.formats {
                let ranges = format.frameRateRanges
                    .map { "\($0.minimum)-\($0.maximum)fps" }
                    .joined(separator: ", ")
                lines.append(
                    "    \(format.width)x\(format.height) \(format.mediaSubtype) "
                        + "[\(ranges)] stabilization=\(format.stabilizationModes.joined(separator: ","))"
                )
            }
        }

        return lines.joined(separator: "\n")
    }
}

struct CameraDeviceCapability: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let position: String
    let isVirtual: Bool
    let constituentDeviceIDs: [String]
    let focusModes: [String]
    let exposureModes: [String]
    let supportsFocusPoint: Bool
    let supportsExposurePoint: Bool
    let minimumZoomFactor: Double
    let maximumZoomFactor: Double
    let formats: [CameraFormatCapability]
}

struct CameraFormatCapability: Codable, Equatable, Sendable {
    let width: Int32
    let height: Int32
    let mediaSubtype: String
    let fieldOfView: Float
    let isVideoBinned: Bool
    let supportsHDR: Bool
    let autofocusSystem: String
    let minimumISO: Float
    let maximumISO: Float
    let minimumExposureSeconds: Double
    let maximumExposureSeconds: Double
    let maximumZoomFactor: Double
    let frameRateRanges: [CameraFrameRateRange]
    let stabilizationModes: [String]
}

struct CameraFrameRateRange: Codable, Equatable, Sendable {
    let minimum: Double
    let maximum: Double
}
