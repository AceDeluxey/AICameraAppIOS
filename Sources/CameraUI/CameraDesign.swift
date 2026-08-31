import SwiftUI

enum CameraDesign {
    static let accent = Color(red: 1, green: 140 / 255, blue: 75 / 255)
    static let controlBackground = Color(red: 74 / 255, green: 64 / 255, blue: 58 / 255)
    static let overlayBackground = Color.black.opacity(0.62)
}

enum CompositionGrid: String, CaseIterable, Identifiable {
    case none
    case thirds
    case goldenRatio
    case crosshair
    case diagonal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .none: "无"
        case .thirds: "三分"
        case .goldenRatio: "黄金"
        case .crosshair: "十字"
        case .diagonal: "对角线"
        }
    }

    var next: CompositionGrid {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
}

struct CompositionGridOverlay: View {
    let grid: CompositionGrid

    var body: some View {
        Canvas { context, size in
            var path = Path()
            switch grid {
            case .none:
                break
            case .thirds:
                addVerticalLines([1 / 3, 2 / 3], size: size, path: &path)
                addHorizontalLines([1 / 3, 2 / 3], size: size, path: &path)
            case .goldenRatio:
                addVerticalLines([0.382, 0.618], size: size, path: &path)
                addHorizontalLines([0.382, 0.618], size: size, path: &path)
            case .crosshair:
                addVerticalLines([0.5], size: size, path: &path)
                addHorizontalLines([0.5], size: size, path: &path)
            case .diagonal:
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.move(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size.height))
            }
            context.stroke(path, with: .color(.white.opacity(0.72)), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func addVerticalLines(_ positions: [CGFloat], size: CGSize, path: inout Path) {
        for position in positions {
            path.move(to: CGPoint(x: size.width * position, y: 0))
            path.addLine(to: CGPoint(x: size.width * position, y: size.height))
        }
    }

    private func addHorizontalLines(_ positions: [CGFloat], size: CGSize, path: inout Path) {
        for position in positions {
            path.move(to: CGPoint(x: 0, y: size.height * position))
            path.addLine(to: CGPoint(x: size.width, y: size.height * position))
        }
    }
}
