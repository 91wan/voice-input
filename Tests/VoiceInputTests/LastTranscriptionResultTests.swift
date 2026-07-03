import XCTest
@testable import VoiceInput

final class LastTranscriptionResultTests: XCTestCase {
    func testBuildsResultFromDictionaryAndResolvedOutput() {
        let dictionaryResult = DictionaryApplyResult(
            text: "TypeScript prompt",
            matches: [
                DictionaryMatch(source: "type script", replacement: "TypeScript", count: 1),
            ]
        )
        let resolved = TranscriptionResolution.Output(
            text: "TypeScript prompt.",
            wasLLMRefined: true
        )

        let result = LastTranscriptionResult.make(
            rawText: "type script prompt",
            dictionaryResult: dictionaryResult,
            resolvedOutput: resolved,
            refinedText: "TypeScript prompt.",
            dictationMode: .promptBuilder,
            refinementMode: .promptBuilder,
            injectionResult: nil
        )

        XCTAssertEqual(result.rawText, "type script prompt")
        XCTAssertEqual(result.filteredText, "TypeScript prompt")
        XCTAssertEqual(result.refinedText, "TypeScript prompt.")
        XCTAssertEqual(result.finalText, "TypeScript prompt.")
        XCTAssertTrue(result.wasLLMRefined)
        XCTAssertEqual(result.dictationModeSummary, "Mode: Prompt Builder")
        XCTAssertEqual(result.refinementSummary, "LLM: Prompt Builder")
        XCTAssertEqual(result.dictionarySummary, "type script → TypeScript")
        XCTAssertEqual(result.injectionSummary, "Insertion: pending")
    }

    func testTracksDictationModeEvenWhenLLMIsNotUsed() {
        let result = LastTranscriptionResult.make(
            rawText: "make a prompt",
            dictionaryResult: DictionaryApplyResult(text: "make a prompt", matches: []),
            resolvedOutput: TranscriptionResolution.Output(text: "make a prompt", wasLLMRefined: false),
            refinedText: nil,
            dictationMode: .promptBuilder,
            refinementMode: nil,
            injectionResult: nil
        )

        XCTAssertEqual(result.dictationMode, .promptBuilder)
        XCTAssertEqual(result.dictationModeSummary, "Mode: Prompt Builder")
        XCTAssertEqual(result.refinementSummary, "LLM: not used")
    }

    func testDefaultRuleDraftIsAvailableOnlyWhenRawAndFinalDiffer() {
        let changed = LastTranscriptionResult(
            rawText: "type script",
            filteredText: "TypeScript",
            refinedText: nil,
            finalText: "TypeScript",
            dictionaryMatches: [],
            wasLLMRefined: false,
            refinementMode: nil,
            injectionResult: .success
        )
        let unchanged = LastTranscriptionResult(
            rawText: "OpenClaw",
            filteredText: "OpenClaw",
            refinedText: nil,
            finalText: "OpenClaw",
            dictionaryMatches: [],
            wasLLMRefined: false,
            refinementMode: nil,
            injectionResult: .success
        )

        XCTAssertEqual(changed.defaultRuleDraft?.source, "type script")
        XCTAssertEqual(changed.defaultRuleDraft?.replacement, "TypeScript")
        XCTAssertNil(unchanged.defaultRuleDraft)
    }

    func testSuccessfulInjectionSummarySaysPasteCommandSent() {
        let result = LastTranscriptionResult(
            rawText: "hello",
            filteredText: "hello",
            refinedText: nil,
            finalText: "hello",
            dictionaryMatches: [],
            wasLLMRefined: false,
            refinementMode: nil,
            injectionResult: .success
        )

        XCTAssertEqual(result.injectionSummary, "Insertion: paste command sent")
        XCTAssertFalse(result.injectionSummary.localizedCaseInsensitiveContains("confirmed"))
        XCTAssertFalse(result.injectionSummary.localizedCaseInsensitiveContains("inserted"))
    }

    func testUpdatingInjectionResultPreservesTranscriptionFields() {
        let result = LastTranscriptionResult(
            rawText: "hello",
            filteredText: "hello",
            refinedText: nil,
            finalText: "hello",
            dictionaryMatches: [],
            wasLLMRefined: false,
            dictationMode: .precise,
            refinementMode: nil,
            injectionResult: nil
        )

        let updated = result.withInjectionResult(.failure(.pasteCommandFailed))

        XCTAssertEqual(updated.rawText, "hello")
        XCTAssertEqual(updated.finalText, "hello")
        XCTAssertEqual(updated.dictationMode, .precise)
        XCTAssertNil(updated.refinementMode)
        XCTAssertEqual(updated.injectionResult, .failure(.pasteCommandFailed))
        XCTAssertEqual(updated.injectionSummary, "Insertion: failed - Paste failed. Text was copied to the clipboard.")
    }
}
