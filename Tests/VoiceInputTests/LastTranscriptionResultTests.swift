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
            injectionResult: nil
        )

        XCTAssertEqual(result.rawText, "type script prompt")
        XCTAssertEqual(result.filteredText, "TypeScript prompt")
        XCTAssertEqual(result.refinedText, "TypeScript prompt.")
        XCTAssertEqual(result.finalText, "TypeScript prompt.")
        XCTAssertTrue(result.wasLLMRefined)
        XCTAssertEqual(result.dictionarySummary, "type script → TypeScript")
        XCTAssertEqual(result.injectionSummary, "Insertion: pending")
    }

    func testDefaultRuleDraftIsAvailableOnlyWhenRawAndFinalDiffer() {
        let changed = LastTranscriptionResult(
            rawText: "type script",
            filteredText: "TypeScript",
            refinedText: nil,
            finalText: "TypeScript",
            dictionaryMatches: [],
            wasLLMRefined: false,
            injectionResult: .success
        )
        let unchanged = LastTranscriptionResult(
            rawText: "OpenClaw",
            filteredText: "OpenClaw",
            refinedText: nil,
            finalText: "OpenClaw",
            dictionaryMatches: [],
            wasLLMRefined: false,
            injectionResult: .success
        )

        XCTAssertEqual(changed.defaultRuleDraft?.source, "type script")
        XCTAssertEqual(changed.defaultRuleDraft?.replacement, "TypeScript")
        XCTAssertNil(unchanged.defaultRuleDraft)
    }

    func testUpdatingInjectionResultPreservesTranscriptionFields() {
        let result = LastTranscriptionResult(
            rawText: "hello",
            filteredText: "hello",
            refinedText: nil,
            finalText: "hello",
            dictionaryMatches: [],
            wasLLMRefined: false,
            injectionResult: nil
        )

        let updated = result.withInjectionResult(.failure(.pasteCommandFailed))

        XCTAssertEqual(updated.rawText, "hello")
        XCTAssertEqual(updated.finalText, "hello")
        XCTAssertEqual(updated.injectionResult, .failure(.pasteCommandFailed))
        XCTAssertEqual(updated.injectionSummary, "Insertion: failed - Paste failed. Text was copied to the clipboard.")
    }
}
