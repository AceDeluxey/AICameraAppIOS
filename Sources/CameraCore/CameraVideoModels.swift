import Foundation

enum CameraCaptureMode: String, CaseIterable, Codable, Sendable {
    case photo
    case video

    var displayName: String {
        switch self {
        case .photo:
            "拍照"
        case .video:
            "视频"
        }
    }
}

enum VideoRecordingStatus: Equatable, Sendable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case saving
    case saved
    case failed(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .preparing, .recording, .saving:
            true
        case .idle, .saved, .failed:
            false
        }
    }
}

enum VideoRecordingDurationFormatter {
    static func text(from startDate: Date, to endDate: Date) -> String {
        let duration = max(0, Int(endDate.timeIntervalSince(startDate)))
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct VideoFormatDescriptor: Equatable, Sendable {
    let width: Int32
    let height: Int32
    let frameRateRanges: [ClosedRange<Double>]
}

enum VideoResolution: String, CaseIterable, Hashable, Sendable {
    case fullPixel
    case fourK
    case fullHighDefinition
    case highDefinition

    var displayName: String {
        switch self {
        case .fullPixel: "全像素"
        case .fourK: "4K"
        case .fullHighDefinition: "1080p"
        case .highDefinition: "720p"
        }
    }
}

struct VideoFormatOption: Identifiable, Hashable, Sendable {
    let resolution: VideoResolution
    let width: Int32
    let height: Int32
    let framesPerSecond: Int

    var id: String {
        "\(resolution.rawValue)-\(width)x\(height)-\(framesPerSecond)"
    }

    var displayName: String {
        "\(resolution.displayName) · \(framesPerSecond)fps"
    }
}

enum VideoFormatOptionBuilder {
    private static let supportedFrameRates = [30, 60, 120]

    static func options(from descriptors: [VideoFormatDescriptor]) -> [VideoFormatOption] {
        guard !descriptors.isEmpty else { return [] }
        let fullPixelSize = descriptors
            .filter { descriptor in
                let longEdge = Double(max(descriptor.width, descriptor.height))
                let shortEdge = Double(min(descriptor.width, descriptor.height))
                return shortEdge > 0 && abs(longEdge / shortEdge - 4.0 / 3.0) < 0.04
            }
            .max { pixelCount($0) < pixelCount($1) }
            .map { ($0.width, $0.height) }

        var options = Set<VideoFormatOption>()
        for descriptor in descriptors {
            guard let resolution = resolution(
                width: descriptor.width,
                height: descriptor.height,
                fullPixelSize: fullPixelSize
            ) else { continue }

            for frameRate in supportedFrameRates where descriptor.frameRateRanges.contains(where: {
                $0.lowerBound <= Double(frameRate) && $0.upperBound >= Double(frameRate)
            }) {
                options.insert(VideoFormatOption(
                    resolution: resolution,
                    width: descriptor.width,
                    height: descriptor.height,
                    framesPerSecond: frameRate
                ))
            }
        }

        return options.sorted {
            let lhsRank = VideoResolution.allCases.firstIndex(of: $0.resolution) ?? .max
            let rhsRank = VideoResolution.allCases.firstIndex(of: $1.resolution) ?? .max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return $0.framesPerSecond < $1.framesPerSecond
        }
    }

    private static func resolution(
        width: Int32,
        height: Int32,
        fullPixelSize: (Int32, Int32)?
    ) -> VideoResolution? {
        let dimensions = (max(width, height), min(width, height))
        if let fullPixelSize,
           dimensions == (max(fullPixelSize.0, fullPixelSize.1), min(fullPixelSize.0, fullPixelSize.1))
        {
            return .fullPixel
        }
        return switch dimensions {
        case (3840, 2160): .fourK
        case (1920, 1080): .fullHighDefinition
        case (1280, 720): .highDefinition
        default: nil
        }
    }

    private static func pixelCount(_ descriptor: VideoFormatDescriptor) -> Int64 {
        Int64(descriptor.width) * Int64(descriptor.height)
    }
}

struct VideoRecordingHUDSnapshot: Equatable, Sendable {
    let batteryLevel: Double?
    let availableCapacity: Int64?
}

enum VideoRecordingHUDFormatter {
    static func batteryText(level: Double?) -> String {
        guard let level, level >= 0 else { return "电量 --" }
        return "电量 \(Int((min(level, 1) * 100).rounded()))%"
    }

    static func storageText(bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "可用 --" }
        return "可用 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}
