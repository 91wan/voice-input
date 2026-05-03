import XCTest
@testable import VoiceInput

final class DictationWorkflowStatusTests: XCTestCase {
    func testReadyStatusExplainsDefaultFnAndOneShotPromptBuilder() {
        let status = DictationWorkflowStatus.make(
            defaultMode: .precise,
            isLLMEnabled: true,
            isLLMConfigured: true
        )

        XCTAssertEqual(status.menuSummary, "Dictation: Fn uses Precise Dictation")
        XCTAssertEqual(status.defaultShortcutTitle, "Fn: Precise Dictation (default)")
        XCTAssertEqual(status.promptBuilderShortcutTitle, "Option + Fn: Prompt Builder (one shot)")
        XCTAssertEqual(status.readinessDetail, "Fn uses Precise Dictation. Option + Fn uses Prompt Builder once. LLM refinement is ready.")
        XCTAssertTrue(status.isLLMAvailable)
    }

    func testUnavailableLLMStatusKeepsOrdinaryFnQuietAndDeterministic() {
        let status = DictationWorkflowStatus.make(
            defaultMode: .promptBuilder,
            isLLMEnabled: false,
            isLLMConfigured: false
        )

        XCTAssertEqual(status.menuSummary, "Dictation: Fn uses Apple Speech + DictionaryFilter")
        XCTAssertEqual(status.defaultShortcutTitle, "Fn: Prompt Builder (default; LLM unavailable)")
        XCTAssertEqual(
            status.readinessDetail,
            "Fn uses Prompt Builder. Option + Fn uses Prompt Builder once. LLM unavailable: ordinary Fn still uses Apple Speech + DictionaryFilter without extra errors."
        )
        XCTAssertFalse(status.isLLMAvailable)
    }
}
