import SwiftUI

struct CameraDiagnosticsView: View {
    let report: CameraCapabilityReport?
    let stabilizationResult: StabilizationApplicationResult?
    let refresh: () -> Void
    let setStabilizationMode: (StabilizationModeSelection) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            stabilizationControls
                            Divider()
                            Text(report.textDescription)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                } else {
                    ProgressView("正在读取相机能力")
                }
            }
            .navigationTitle("相机能力")
            .toolbar {
                Button("刷新", action: refresh)
            }
        }
    }

    private var stabilizationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("防抖诊断")
                .font(.headline)

            if let stabilizationResult {
                Text(stabilizationResult.textDescription)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("当前连接没有可读取的防抖状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(StabilizationModeSelection.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    setStabilizationMode(mode)
                }
                .buttonStyle(.bordered)
                .disabled(stabilizationResult?.requestedMode == mode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
