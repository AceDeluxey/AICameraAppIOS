import SwiftUI

struct BirdClassificationCandidatesView: View {
    let status: BirdClassificationStatus
    let isEnabled: Bool

    var body: some View {
        if isEnabled, case let .candidates(candidates) = status, !candidates.isEmpty {
            VStack(spacing: 2) {
                ForEach(Array(candidates.prefix(3).enumerated()), id: \.element.identifier) { index, candidate in
                    Text(
                        "\(index + 1). \(candidate.displayName) "
                            + "\(Int((candidate.confidence * 100).rounded()))%"
                    )
                }
            }
            .font(.headline.bold())
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black, radius: 0, x: -1, y: 0)
            .shadow(color: .black, radius: 0, x: 1, y: 0)
            .shadow(color: .black, radius: 0, x: 0, y: -1)
            .shadow(color: .black, radius: 0, x: 0, y: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("鸟种候选")
        }
    }
}
