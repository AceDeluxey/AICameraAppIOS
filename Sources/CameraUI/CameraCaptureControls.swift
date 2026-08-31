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

struct CameraControlModePicker: View {
    let selectedMode: CameraControlMode
    let supportsProfessionalMode: Bool
    let isDisabled: Bool
    let selectMode: (CameraControlMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraControlMode.allCases, id: \.self) { mode in
                Button(mode.displayName) { selectMode(mode) }
                    .font(.subheadline.bold())
                    .foregroundStyle(selectedMode == mode ? .black : .white)
                    .frame(minWidth: 54, minHeight: 44)
                    .background(
                        selectedMode == mode ? CameraDesign.accent : Color.clear,
                        in: Capsule()
                    )
                    .disabled(mode == .professional && !supportsProfessionalMode)
                    .accessibilityIdentifier("\(mode.rawValue)ControlModeButton")
            }
        }
        .padding(3)
        .background(CameraDesign.overlayBackground, in: Capsule())
        .disabled(isDisabled)
        .accessibilityLabel("相机控制模式")
    }
}

struct CameraProfessionalControls: View {
    let mode: CameraControlMode
    let capabilities: CameraProfessionalCapabilities
    let settings: CameraProfessionalSettings
    let isDisabled: Bool
    let setControl: (CameraProfessionalControl) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if mode == .automatic, let range = capabilities.exposureBiasRange {
                controlRow(
                    title: "EV",
                    value: CameraProfessionalFormatter.exposureBias(settings.exposureBias),
                    valueBinding: Binding(
                        get: { Double(settings.exposureBias) },
                        set: { setControl(.exposureBias(Float($0))) }
                    ),
                    range: Double(range.lowerBound) ... Double(range.upperBound)
                )
            }
            if mode == .professional {
                professionalRows
            }
        }
        .padding(10)
        .background(CameraDesign.overlayBackground, in: RoundedRectangle(cornerRadius: 14))
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var professionalRows: some View {
        if let range = capabilities.isoRange {
            controlRow(
                title: "ISO",
                value: CameraProfessionalFormatter.iso(settings.iso),
                valueBinding: logarithmicBinding(
                    value: Double(settings.iso),
                    range: Double(range.lowerBound) ... Double(range.upperBound),
                    update: { setControl(.iso(Float($0))) }
                ),
                range: 0 ... 1
            )
        }
        if let range = capabilities.exposureDurationRange {
            controlRow(
                title: "快门",
                value: CameraProfessionalFormatter.shutter(settings.exposureDuration),
                valueBinding: logarithmicBinding(
                    value: settings.exposureDuration,
                    range: range,
                    update: { setControl(.exposureDuration($0)) }
                ),
                range: 0 ... 1
            )
        }
        if capabilities.supportsManualFocus {
            controlRow(
                title: "对焦",
                value: CameraProfessionalFormatter.focus(settings.lensPosition),
                valueBinding: Binding(
                    get: { Double(settings.lensPosition) },
                    set: { setControl(.lensPosition(Float($0))) }
                ),
                range: 0 ... 1
            )
        }
    }

    private func controlRow(
        title: String,
        value: String,
        valueBinding: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .frame(width: 38, alignment: .leading)
            Slider(value: valueBinding, in: range)
                .tint(CameraDesign.accent)
            Text(value)
                .font(.caption.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func logarithmicBinding(
        value: Double,
        range: ClosedRange<Double>,
        update: @escaping (Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { CameraProfessionalScale.normalized(value, in: range) },
            set: { update(CameraProfessionalScale.value($0, in: range)) }
        )
    }
}

struct VideoFormatPicker: View {
    let options: [VideoFormatOption]
    let selectedOption: VideoFormatOption?
    let isDisabled: Bool
    let selectOption: (VideoFormatOption) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.displayName) { selectOption(option) }
            }
        } label: {
            Text(selectedOption?.displayName ?? "选择视频档位")
                .font(.subheadline.bold().monospacedDigit())
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(CameraDesign.overlayBackground, in: Capsule())
        }
        .foregroundStyle(.white)
        .disabled(isDisabled)
        .accessibilityLabel("视频分辨率与帧率")
        .accessibilityValue(selectedOption?.displayName ?? "无可用档位")
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
