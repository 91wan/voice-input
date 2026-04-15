import Foundation

enum TranscriptionResolution {
    struct Output {
        let text: String
        let wasLLMRefined: Bool
    }

    static func resolve(filteredText: String, refinedText: String?) -> Output {
        let normalizedRefinedText = refinedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalText = normalizedRefinedText.isEmpty ? filteredText : normalizedRefinedText
        return Output(text: finalText, wasLLMRefined: finalText != filteredText)
    }
}
