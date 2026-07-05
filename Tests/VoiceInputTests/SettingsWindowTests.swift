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

    func testValidatedTestConfigurationUsesTrimmedTransientValues() throws {
        let configuration = try SettingsWindow.validatedTestConfiguration(
            apiBaseURL: "  https://transient.example/v1  ",
            apiKey: "  transient-key  ",
            model: "  transient-model  "
        )

        XCTAssertEqual(configuration.apiBaseURL, "https://transient.example/v1")
        XCTAssertEqual(configuration.model, "transient-model")
        XCTAssertTrue(configuration.hasAPIKey)
    }

    func testValidatedTestConfigurationUsesDefaultsForBlankBaseURLAndModel() throws {
        let configuration = try SettingsWindow.validatedTestConfiguration(
            apiBaseURL: "   ",
            apiKey: " transient-key ",
            model: "   "
        )

        XCTAssertEqual(configuration.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertEqual(configuration.model, LLMRefiner.defaultModel)
        XCTAssertTrue(configuration.hasAPIKey)
    }

    func testValidatedTestConfigurationRejectsEmptyAPIKeyWithoutBuildingRequest() {
        XCTAssertThrowsError(
            try SettingsWindow.validatedTestConfiguration(
                apiBaseURL: "https://api.openai.com/v1",
                apiKey: "   ",
                model: "gpt-4o-mini"
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "API key is empty")
        }
    }

    func testValidatedTestConfigurationRejectsInvalidAPIBaseURL() {
        XCTAssertThrowsError(
            try SettingsWindow.validatedTestConfiguration(
                apiBaseURL: "http://api.example.com/v1",
                apiKey: "transient-key",
                model: "gpt-4o-mini"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid API base URL"))
        }
    }

    func testDraftChangePolicySuppressesStatusWhileLoadingSettings() {
        XCTAssertNil(LLMSettingsDraftChangePolicy.outcome(isLoadingSettings: true))
    }

    func testDraftChangePolicyCancelsActiveTestAndClearsStaleResultAfterUserEdit() throws {
        let outcome = try XCTUnwrap(LLMSettingsDraftChangePolicy.outcome(isLoadingSettings: false))

        XCTAssertTrue(outcome.shouldCancelActiveTest)
        XCTAssertEqual(outcome.testState, .notRun)
        XCTAssertEqual(
            outcome.message,
            "Unsaved changes. Test uses current fields once; Save persists them."
        )
        XCTAssertNil(outcome.success)
    }

    func testDraftChangePolicyMessageDoesNotExposeSecrets() throws {
        let outcome = try XCTUnwrap(LLMSettingsDraftChangePolicy.outcome(isLoadingSettings: false))

        XCTAssertFalse(outcome.message.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(outcome.message.localizedCaseInsensitiveContains("keychain"))
        XCTAssertFalse(outcome.message.localizedCaseInsensitiveContains("userdefaults"))
        XCTAssertFalse(outcome.message.localizedCaseInsensitiveContains("sk-"))
        XCTAssertTrue(outcome.message.localizedCaseInsensitiveContains("unsaved"))
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
