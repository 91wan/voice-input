import XCTest
@testable import VoiceInput

final class SettingsWindowTests: XCTestCase {
    func testSettingsValidationRejectsInvalidNonBlankAPIBaseURL() {
        XCTAssertThrowsError(
            try SettingsWindow.validatedSettings(
                apiBaseURL: "localhost:1234/v1",
                model: "gpt-4o-mini"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid API base URL"))
        }
    }

    func testSettingsValidationAllowsBlankAPIBaseURLForDefaultFallback() throws {
        let settings = try SettingsWindow.validatedSettings(
            apiBaseURL: "   ",
            model: "   "
        )

        XCTAssertEqual(settings.apiBaseURL, "")
        XCTAssertEqual(settings.model, "")
    }

    func testLLMSettingsStatusShowsNotConfiguredWithoutAPIKey() {
        let status = LLMSettingsStatus.make(
            isConfigured: false,
            apiBaseURL: LLMRefiner.defaultAPIBaseURL,
            model: LLMRefiner.defaultModel,
            mode: .precise,
            testState: .notRun
        )

        XCTAssertEqual(status.displayText, "Not configured: add an API key to enable LLM refinement.")
        XCTAssertFalse(status.isReady)
    }

    func testLLMSettingsStatusShowsReadyConfigurationWithoutSecret() {
        let status = LLMSettingsStatus.make(
            isConfigured: true,
            apiBaseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            mode: .promptBuilder,
            testState: .notRun
        )

        XCTAssertEqual(status.displayText, "Ready: https://api.openai.com/v1 · gpt-4o-mini · Prompt Builder")
        XCTAssertTrue(status.isReady)
        XCTAssertFalse(status.displayText.contains("sk-"))
    }

    func testLLMSettingsStatusShowsFailedTestWithEndpointModelAndMode() {
        let status = LLMSettingsStatus.make(
            isConfigured: true,
            apiBaseURL: "https://api.example.com/v1",
            model: "custom-model",
            mode: .precise,
            testState: .failed("401 Unauthorized")
        )

        XCTAssertEqual(
            status.displayText,
            "Test failed: 401 Unauthorized · https://api.example.com/v1 · custom-model · Precise Dictation"
        )
        XCTAssertFalse(status.isReady)
    }
}
