import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((CGPoint, CGPoint) -> Void)?
    var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPinch: onPinch)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didTap(_:))
        )
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didPinch(_:))
        )
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pinch)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        context.coordinator.onTap = onTap
        context.coordinator.onPinch = onPinch
    }

    final class Coordinator: NSObject {
        weak var view: PreviewView?
        var onTap: ((CGPoint, CGPoint) -> Void)?
        var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?

        init(
            onTap: ((CGPoint, CGPoint) -> Void)?,
            onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?
        ) {
            self.onTap = onTap
            self.onPinch = onPinch
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            let normalizedLayerPoint = CGPoint(
                x: layerPoint.x / max(view.bounds.width, 1),
                y: layerPoint.y / max(view.bounds.height, 1)
            )
            onTap?(devicePoint, normalizedLayerPoint)
        }

        @objc func didPinch(_ recognizer: UIPinchGestureRecognizer) {
            onPinch?(recognizer.scale, recognizer.state)
        }
    }
}

final class PreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("PreviewView must use AVCaptureVideoPreviewLayer")
        }
        return previewLayer
    }
}
