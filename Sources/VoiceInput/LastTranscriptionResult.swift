import Foundation

struct DictionaryRuleDraft: Equatable {
    let source: String
    let replacement: String
}

struct LastTranscriptionResult: Equatable {
    let rawText: String
    let filteredText: String
    let refinedText: String?
    let finalText: String
    let dictionaryMatches: [DictionaryMatch]
    let wasLLMRefined: Bool
    let injectionResult: TextInjectionResult?
    let createdAt: Date

    init(
        rawText: String,
        filteredText: String,
        refinedText: String?,
        finalText: String,
        dictionaryMatches: [DictionaryMatch],
        wasLLMRefined: Bool,
        injectionResult: TextInjectionResult?,
        createdAt: Date = Date()
    ) {
        self.rawText = rawText
        self.filteredText = filteredText
        self.refinedText = refinedText
        self.finalText = finalText
        self.dictionaryMatches = dictionaryMatches
        self.wasLLMRefined = wasLLMRefined
        self.injectionResult = injectionResult
        self.createdAt = createdAt
    }

    static func make(
        rawText: String,
        dictionaryResult: DictionaryApplyResult,
        resolvedOutput: TranscriptionResolution.Output,
        refinedText: String?,
        injectionResult: TextInjectionResult?
    ) -> LastTranscriptionResult {
        LastTranscriptionResult(
            rawText: rawText,
            filteredText: dictionaryResult.text,
            refinedText: refinedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : refinedText,
            finalText: resolvedOutput.text,
            dictionaryMatches: dictionaryResult.matches,
            wasLLMRefined: resolvedOutput.wasLLMRefined,
            injectionResult: injectionResult
        )
    }

    var dictionarySummary: String {
        guard !dictionaryMatches.isEmpty else { return "No dictionary matches" }

        let visibleMatches = dictionaryMatches.prefix(3).map(\.displayText)
        var text = visibleMatches.joined(separator: ", ")
        if dictionaryMatches.count > 3 {
            text += ", +\(dictionaryMatches.count - 3) more"
        }
        return text
    }

    var injectionSummary: String {
        guard let injectionResult else { return "Insertion: pending" }

        switch injectionResult {
        case .success:
            return "Insertion: success"
        case .failure(let failure):
            return "Insertion: failed - \(failure.localizedDescription)"
        }
    }

    var defaultRuleDraft: DictionaryRuleDraft? {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !replacement.isEmpty else { return nil }
        guard source.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) !=
            replacement.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        else { return nil }

        return DictionaryRuleDraft(source: source, replacement: replacement)
    }

    func withInjectionResult(_ injectionResult: TextInjectionResult) -> LastTranscriptionResult {
        LastTranscriptionResult(
            rawText: rawText,
            filteredText: filteredText,
            refinedText: refinedText,
            finalText: finalText,
            dictionaryMatches: dictionaryMatches,
            wasLLMRefined: wasLLMRefined,
            injectionResult: injectionResult,
            createdAt: createdAt
        )
    }
}
