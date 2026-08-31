import Foundation

struct BirdClassificationLabel: Equatable, Sendable {
    let identifier: String
    let displayName: String
}

struct BirdClassificationPostprocessor: Sendable {
    let maximumResults: Int

    init(maximumResults: Int = 3) {
        precondition(maximumResults > 0)
        self.maximumResults = maximumResults
    }

    func classifications(
        logits: [Float],
        labels: [BirdClassificationLabel]
    ) -> [BirdClassification] {
        guard logits.count == labels.count,
              let maximumLogit = logits.filter(\.isFinite).max()
        else { return [] }

        let exponentials = logits.map { value -> Double in
            guard value.isFinite else { return 0 }
            return exp(Double(value - maximumLogit))
        }
        let total = exponentials.reduce(0, +)
        guard total.isFinite, total > 0 else { return [] }

        return exponentials.indices
            .sorted { exponentials[$0] > exponentials[$1] }
            .prefix(maximumResults)
            .map { index in
                BirdClassification(
                    identifier: labels[index].identifier,
                    displayName: labels[index].displayName,
                    confidence: Float(exponentials[index] / total)
                )
            }
    }
}

enum BirdClassificationLabelParser {
    static func parse(_ contents: String) -> [BirdClassificationLabel] {
        contents.split(whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            let displayName = fields.first.map(String.init)?.trimmingCharacters(in: .whitespaces)
            guard let displayName, !displayName.isEmpty else { return nil }
            let identifier = fields.count >= 3
                ? String(fields[2]).trimmingCharacters(in: .whitespaces)
                : String(index)
            return BirdClassificationLabel(
                identifier: identifier.isEmpty ? String(index) : identifier,
                displayName: displayName
            )
        }
    }
}
