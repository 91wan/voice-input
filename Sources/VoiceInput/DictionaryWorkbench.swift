import Foundation

struct DictionaryWorkbenchEvaluation: Equatable {
    let canEvaluate: Bool
    let outputText: String
    let matchSummary: String
}

enum DictionaryWorkbench {
    static func evaluate(phrase: String, rulesText: String) -> DictionaryWorkbenchEvaluation {
        let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPhrase.isEmpty else {
            return DictionaryWorkbenchEvaluation(
                canEvaluate: true,
                outputText: "",
                matchSummary: "Enter a test phrase to preview dictionary matches."
            )
        }

        let parseResult = DictionaryFilter.parse(rulesText)
        guard parseResult.canSave else {
            return DictionaryWorkbenchEvaluation(
                canEvaluate: false,
                outputText: "",
                matchSummary: parseResult.summary()
            )
        }

        let filter = DictionaryFilter(
            userMap: parseResult.dictionary,
            notificationCenter: NotificationCenter()
        )
        let result = filter.applying(normalizedPhrase)
        return DictionaryWorkbenchEvaluation(
            canEvaluate: true,
            outputText: result.text,
            matchSummary: result.matches.isEmpty
                ? "No dictionary matches"
                : result.matches.map(\.displayText).joined(separator: ", ")
        )
    }
}
