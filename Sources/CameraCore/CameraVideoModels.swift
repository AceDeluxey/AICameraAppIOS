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
