import SwiftUI

struct CameraScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraSessionController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack {
                statusView
                Spacer()
                controls
            }
            .padding()
        }
        .task {
            await camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                camera.stop()
            } else if phase == .active {
                Task { await camera.start() }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var statusView: some View {
        switch camera.state {
        case .unauthorized:
            Text("请在系统设置中允许相机权限")
                .padding(12)
                .background(.black.opacity(0.7), in: Capsule())
        case let .failed(message):
            Text(message)
                .padding(12)
                .background(.black.opacity(0.7), in: Capsule())
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack {
            controlButton(label: "相册", systemImage: "photo.on.rectangle")
            Spacer()
            Button(action: {}, label: {
                Circle()
                    .fill(Color(red: 1, green: 0.55, blue: 0.29))
                    .frame(width: 76, height: 76)
                    .overlay(Circle().stroke(.white, lineWidth: 4))
            })
            .accessibilityLabel("拍照")
            Spacer()
            controlButton(label: "鸟模式", systemImage: "bird")
        }
    }

    private func controlButton(label: String, systemImage: String) -> some View {
        Button(action: {}, label: {
            Image(systemName: systemImage)
                .frame(width: 52, height: 52)
                .background(Color(red: 0.29, green: 0.25, blue: 0.23), in: Circle())
        })
        .accessibilityLabel(label)
    }
}

#Preview {
    CameraScreen()
}
