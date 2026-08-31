import SwiftUI

struct CameraDiagnosticsView: View {
    let report: CameraCapabilityReport?
    let refresh: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    ScrollView {
                        Text(report.textDescription)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
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
}
