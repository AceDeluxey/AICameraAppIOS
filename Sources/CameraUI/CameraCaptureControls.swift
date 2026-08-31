import SwiftUI

struct CaptureModePicker: View {
    let selectedMode: CameraCaptureMode
    let isDisabled: Bool
    let selectMode: (CameraCaptureMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraCaptureMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    selectMode(mode)
                }
                .font(.subheadline.bold())
                .foregroundStyle(selectedMode == mode ? .black : .white)
                .frame(minWidth: 64, minHeight: 44)
                .background(
                    selectedMode == mode ? CameraDesign.accent : Color.clear,
                    in: Capsule()
                )
                .accessibilityIdentifier("\(mode.rawValue)ModeButton")
            }
        }
        .padding(3)
        .background(CameraDesign.overlayBackground, in: Capsule())
        .disabled(isDisabled)
    }
}

struct CaptureShutterButton: View {
    let mode: CameraCaptureMode
    let recordingStatus: VideoRecordingStatus
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            ZStack {
                Circle()
                    .fill(mode == .video ? .red : CameraDesign.accent)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                if recordingStatus.isRecording {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white)
                        .frame(width: 26, height: 26)
                }
            }
            .opacity(isBusy ? 0.55 : 1)
        })
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("shutterButton")
    }

    private var accessibilityLabel: String {
        if mode == .photo {
            return "拍照"
        }
        return recordingStatus.isRecording ? "停止录像" : "开始录像"
    }
}

struct VideoRecordingStatusView: View {
    let status: VideoRecordingStatus
    let includesAudio: Bool
    let hudSnapshot: () -> VideoRecordingHUDSnapshot

    var body: some View {
        switch status {
        case .preparing:
            statusPill("正在准备录像")
        case let .recording(startedAt):
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let snapshot = hudSnapshot()
                VStack(spacing: 5) {
                    statusPill(
                        "● \(VideoRecordingDurationFormatter.text(from: startedAt, to: context.date))"
                            + (includesAudio ? "" : " · 静音")
                    )
                    .foregroundStyle(.red)
                    Text(
                        "\(VideoRecordingHUDFormatter.batteryText(level: snapshot.batteryLevel))"
                            + " · \(VideoRecordingHUDFormatter.storageText(bytes: snapshot.availableCapacity))"
                    )
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CameraDesign.overlayBackground, in: Capsule())
                }
            }
        case .saving:
            statusPill("正在保存视频")
        case .saved:
            statusPill("视频已保存到照片")
        case let .failed(message):
            statusPill(message)
        case .idle:
            EmptyView()
        }
    }

    private func statusPill(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(CameraDesign.overlayBackground, in: Capsule())
    }
}
