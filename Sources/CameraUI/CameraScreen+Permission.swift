import SwiftUI
import UIKit

extension CameraScreen {
    @ViewBuilder
    var permissionRecoveryOverlay: some View {
        if camera.state == .unauthorized {
            VStack(spacing: 14) {
                Text("需要相机权限")
                    .font(.headline)
                Text("允许相机权限后才能取景和拍摄。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("打开系统设置", action: openSettings)
                    .accessibilityIdentifier("cameraPermissionSettingsButton")
                    .buttonStyle(.borderedProminent)
                    .tint(CameraDesign.accent)
            }
            .padding(24)
            .background(CameraDesign.controlBackground, in: RoundedRectangle(cornerRadius: 18))
            .padding(24)
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
