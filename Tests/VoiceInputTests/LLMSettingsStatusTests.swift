import XCTest
@testable import VoiceInput

final class LLMSettingsStatusTests: XCTestCase {
    func testTransientTestingStatusShowsUnsavedConfiguration() {
        let status = LLMSettingsStatus.make(
            isConfigured: true,
            apiBaseURL: "https://api.example.com/v1",
            model: "custom-model",
            mode: .promptBuilder,
            testState: .testing,
            isTransientConfiguration: true
        )

        XCTAssertEqual(
            status.displayText,
            "Testing unsaved settings: https://api.example.com/v1 · custom-model · Prompt Builder"
        )
        XCTAssertFalse(status.isReady)
    }

    func testTransientSuccessStatusShowsNotSaved() {
        let status = LLMSettingsStatus.make(
            isConfigured: true,
            apiBaseURL: "https://api.example.com/v1",
            model: "custom-model",
            mode: .precise,
            testState: .succeeded("Hello"),
            isTransientConfiguration: true
        )

        XCTAssertEqual(status.displayText, "Test OK (not saved): Hello")
        XCTAssertTrue(status.isReady)
    }

    func testTransientFailureStatusShowsNotSaved() {
        let status = LLMSettingsStatus.make(
            isConfigured: true,
            apiBaseURL: "https://api.example.com/v1",
            model: "custom-model",
            mode: .precise,
            testState: .failed("401 Unauthorized"),
            isTransientConfiguration: true
        )

        XCTAssertEqual(
            status.displayText,
            "Test failed (not saved): 401 Unauthorized · https://api.example.com/v1 · custom-model · Precise Dictation"
        )
        XCTAssertFalse(status.isReady)
    }

    func testPersistentReadyStatusDoesNotSayUnsaved() {
        let status = LLMSettingsStatus.make(
            isConfigured: true,
            apiBaseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            mode: .promptBuilder,
            testState: .notRun
        )

        XCTAssertEqual(status.displayText, "Ready: https://api.openai.com/v1 · gpt-4o-mini · Prompt Builder")
        XCTAssertFalse(status.displayText.localizedCaseInsensitiveContains("unsaved"))
        XCTAssertFalse(status.displayText.localizedCaseInsensitiveContains("not saved"))
        XCTAssertTrue(status.isReady)
    }

}
