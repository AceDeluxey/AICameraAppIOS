import PhotosUI
import SwiftUI
import UIKit

struct CameraScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var camera = CameraSessionController()
    @AppStorage("birdModeEnabled") private var birdModeEnabled = true
    @AppStorage("stabilizationEnabled") private var stabilizationEnabled = true
    @State private var showsDiagnostics = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var compositionGrid = CompositionGrid.none
    @State private var manualFocusLocation: CGPoint?
    @State private var pinchStartZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                preview(in: geometry.size)
                chrome
            }
        }
        .task {
            await camera.start()
            camera.setBirdModeEnabled(birdModeEnabled)
            camera.setStabilizationMode(stabilizationEnabled ? .automatic : .off)
        }
        .onChange(of: birdModeEnabled) { _, enabled in
            camera.setBirdModeEnabled(enabled)
        }
        .onChange(of: stabilizationEnabled) { _, enabled in
            camera.setStabilizationMode(enabled ? .automatic : .off)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                camera.stop()
            } else if phase == .active {
                Task { await camera.start() }
            }
        }
        .onChange(of: camera.captureStatus) { _, status in
            guard status == .saved else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                camera.clearCaptureMessage()
            }
        }
        .onChange(of: camera.videoRecordingStatus) { _, status in
            guard status == .saved else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                camera.clearVideoMessage()
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showsDiagnostics) {
            CameraDiagnosticsView(
                report: camera.capabilityReport,
                stabilizationResult: camera.stabilizationResult,
                refresh: camera.refreshCapabilities,
                setStabilizationMode: camera.setStabilizationMode
            )
        }
    }
}

private extension CameraScreen {
    private func preview(in size: CGSize) -> some View {
        let width = size.width
        let height = min(size.height, width / camera.aspectRatio.portraitValue)
        return CameraPreview(
            session: camera.session,
            onTap: { devicePoint, layerPoint in
                camera.focus(at: devicePoint)
                manualFocusLocation = layerPoint
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    manualFocusLocation = nil
                }
            },
            onPinch: { scale, state in
                if state == .began {
                    pinchStartZoom = camera.zoomFactor
                }
                camera.setZoomFactor(pinchStartZoom * scale)
            }
        )
        .frame(width: width, height: height)
        .clipped()
        .overlay(CompositionGridOverlay(grid: compositionGrid))
        .overlay { birdTargetOverlay }
        .overlay { focusOverlay }
        .position(x: size.width / 2, y: size.height / 2)
        .accessibilityLabel("相机取景器")
    }

    private var birdTargetOverlay: some View {
        GeometryReader { geometry in
            if birdModeEnabled, let box = camera.birdBoundingBox {
                let mapped = mappedBirdBox(box, in: geometry.size)
                RoundedRectangle(cornerRadius: 5)
                    .stroke(CameraDesign.accent, lineWidth: 2)
                    .frame(width: mapped.width, height: mapped.height)
                    .position(x: mapped.midX, y: mapped.midY)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .accessibilityLabel("已检测到鸟")
            }
        }
        .allowsHitTesting(false)
    }

    private var focusOverlay: some View {
        GeometryReader { geometry in
            if let point = manualFocusLocation {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(CameraDesign.accent, lineWidth: 2)
                    .frame(width: 64, height: 64)
                    .position(
                        x: point.x * geometry.size.width,
                        y: point.y * geometry.size.height
                    )
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var chrome: some View {
        VStack(spacing: 12) {
            topBar
            BirdClassificationCandidatesView(
                status: camera.birdClassificationStatus,
                isEnabled: birdModeEnabled
            )
            statusView
            Spacer()
            captureModePicker
            professionalControls
            lensControls
            zoomControl
            bottomControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var topBar: some View {
        HStack {
            Button(camera.aspectRatio.rawValue, action: camera.toggleAspectRatio)
                .font(.headline.monospacedDigit())
                .frame(minWidth: 52, minHeight: 44)
                .background(CameraDesign.overlayBackground, in: Capsule())
                .accessibilityLabel("照片比例 \(camera.aspectRatio.rawValue)")
                .accessibilityIdentifier("aspectRatioButton")
                .disabled(camera.videoRecordingStatus.isBusy)

            Spacer()

            Button(action: { compositionGrid = compositionGrid.next }, label: {
                Image(systemName: "grid")
                    .frame(width: 44, height: 44)
                    .background(CameraDesign.overlayBackground, in: Circle())
            })
            .accessibilityLabel("构图线 \(compositionGrid.label)")

            Menu {
                Toggle("照片记录位置", isOn: $camera.includesLocationMetadata)
                Toggle("稳定：自动", isOn: $stabilizationEnabled)
            } label: {
                Image(systemName: camera.includesLocationMetadata ? "location.fill" : "ellipsis")
                    .frame(width: 44, height: 44)
                    .background(CameraDesign.overlayBackground, in: Circle())
            }
            .accessibilityLabel("拍摄设置")

            #if DEBUG
                Button(action: { showsDiagnostics = true }, label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                        .background(CameraDesign.overlayBackground, in: Circle())
                })
                .accessibilityLabel("相机诊断")
            #endif
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let message = camera.interruptionMessage {
            statusPill(message)
        } else if camera.thermalState == .critical {
            statusPill("设备温度过高，已降低 AI 频率")
        } else if camera.videoRecordingStatus != .idle {
            VideoRecordingStatusView(
                status: camera.videoRecordingStatus,
                includesAudio: camera.isRecordingAudioEnabled,
                hudSnapshot: camera.currentVideoHUDSnapshot
            )
        } else if birdModeEnabled, let birdMessage {
            statusPill(birdMessage)
        } else if case let .failed(message) = camera.professionalStatus {
            statusPill(message)
        } else if case let .unavailable(message) = camera.professionalStatus, camera.controlMode == .professional {
            statusPill(message)
        } else {
            switch camera.state {
            case .unauthorized:
                Button("请在系统设置中允许相机权限", action: openSettings)
                    .padding(12)
                    .background(CameraDesign.overlayBackground, in: Capsule())
            case let .failed(message):
                statusPill(message)
            default:
                switch camera.captureStatus {
                case .saved:
                    statusPill("已保存到照片")
                case let .failed(message):
                    Button(message, action: openSettings)
                        .padding(12)
                        .background(CameraDesign.overlayBackground, in: Capsule())
                default:
                    EmptyView()
                }
            }
        }
    }

    private var birdMessage: String? {
        switch camera.birdModeStatus {
        case let .unavailable(message), let .failed(message):
            message
        case .pausedForRecording:
            nil
        default:
            nil
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

private extension CameraScreen {
    @ViewBuilder
    private var lensControls: some View {
        if !camera.availableLenses.isEmpty {
            HStack(spacing: 8) {
                ForEach(camera.availableLenses) { lens in
                    Button(lens.zoomLabel) { camera.selectLens(id: lens.id) }
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(camera.activeLensID == lens.id ? .black : .white)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            camera.activeLensID == lens.id
                                ? CameraDesign.accent : CameraDesign.overlayBackground,
                            in: Capsule()
                        )
                        .accessibilityLabel("切换到 \(lens.displayName)")
                        .disabled(camera.videoRecordingStatus.isBusy)
                }
            }
        }
    }

    private var zoomControl: some View {
        HStack(spacing: 10) {
            Text(String(format: "%.1f×", camera.zoomFactor))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { camera.zoomFactor },
                    set: camera.setZoomFactor
                ),
                in: camera.zoomRange
            )
            .tint(CameraDesign.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(CameraDesign.overlayBackground, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("变焦")
        .accessibilityValue(String(format: "%.1f 倍", camera.zoomFactor))
    }

    private var bottomControls: some View {
        HStack {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Group {
                    if let image = camera.latestThumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                .frame(width: 52, height: 52)
                .background(CameraDesign.controlBackground, in: Circle())
                .clipShape(Circle())
            }
            .accessibilityLabel("打开照片")

            Spacer()

            CaptureShutterButton(
                mode: camera.captureMode,
                recordingStatus: camera.videoRecordingStatus,
                isBusy: isShutterBusy,
                isDisabled: camera.state != .running || isShutterBusy,
                action: captureAction
            )

            Spacer()

            Button(action: { birdModeEnabled.toggle() }, label: {
                Image(systemName: "bird")
                    .frame(width: 52, height: 52)
                    .foregroundStyle(birdModeEnabled ? .black : .white)
                    .background(
                        birdModeEnabled ? CameraDesign.accent : CameraDesign.controlBackground,
                        in: Circle()
                    )
            })
            .accessibilityLabel("鸟模式")
            .accessibilityValue(birdModeEnabled ? "开启" : "关闭")
            .accessibilityIdentifier("birdModeButton")
            .disabled(camera.videoRecordingStatus.isBusy)
        }
    }

    private var isShutterBusy: Bool {
        if camera.captureMode == .photo {
            return camera.captureStatus == .capturing
        }
        return switch camera.videoRecordingStatus {
        case .preparing, .saving:
            true
        case .idle, .recording, .saved, .failed:
            false
        }
    }

    private func captureAction() {
        if camera.captureMode == .photo {
            camera.capturePhoto()
        } else {
            camera.toggleVideoRecording()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func mappedBirdBox(_ box: CGRect, in size: CGSize) -> CGRect {
        let imageSize = camera.birdImageSize == .zero
            ? CGSize(width: 3, height: 4)
            : camera.birdImageSize
        let bounds = CGRect(origin: .zero, size: size)
        let topLeft = BirdFocusCoordinateMapper.layerPoint(
            fromNormalizedImagePoint: CGPoint(x: box.minX, y: box.minY),
            imageSize: imageSize,
            in: bounds
        )
        let bottomRight = BirdFocusCoordinateMapper.layerPoint(
            fromNormalizedImagePoint: CGPoint(x: box.maxX, y: box.maxY),
            imageSize: imageSize,
            in: bounds
        )
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).intersection(bounds)
    }
}

#Preview {
    CameraScreen()
}
