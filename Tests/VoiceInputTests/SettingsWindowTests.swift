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

        XCTAssertEqual(
            configuration,
            try LLMRequestConfiguration.validated(
                apiBaseURL: "https://transient.example/v1",
                apiKey: "transient-key",
                model: "transient-model"
            )
        )
    }

    func testValidatedTestConfigurationUsesDefaultsForBlankBaseURLAndModel() throws {
        let configuration = try SettingsWindow.validatedTestConfiguration(
            apiBaseURL: "   ",
            apiKey: " transient-key ",
            model: "   "
        )

        XCTAssertEqual(configuration.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertEqual(configuration.apiKey, "transient-key")
        XCTAssertEqual(configuration.model, LLMRefiner.defaultModel)
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

    func testSettingsWindowValidatedTestConfigurationDelegatesToCoreValueObject() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/SettingsWindow.swift", encoding: .utf8)
        let method = try Self.methodBody(named: "static func validatedTestConfiguration(", in: source)

        XCTAssertTrue(method.contains("LLMRequestConfiguration.validated("))
        XCTAssertFalse(method.contains("trimmingCharacters"))
        XCTAssertFalse(method.contains("LLMRequestConfiguration("))
        XCTAssertFalse(method.contains("LLMRefiner.defaultAPIBaseURL"))
        XCTAssertFalse(method.contains("LLMRefiner.defaultModel"))
    }

    func testSettingsTestMethodDoesNotSaveOrNotifySettingsSaved() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/SettingsWindow.swift", encoding: .utf8)
        let methodStart = try XCTUnwrap(source.range(of: "@objc private func test()")?.lowerBound)
        let methodEnd = try XCTUnwrap(source.range(of: "@objc private func save()", range: methodStart..<source.endIndex)?.lowerBound)
        let methodSource = String(source[methodStart..<methodEnd])

        XCTAssertFalse(methodSource.contains("applyFields()"))
        XCTAssertFalse(methodSource.contains("onSettingsSaved?()"))
        XCTAssertTrue(methodSource.contains("validatedTestConfiguration"))
        XCTAssertTrue(methodSource.contains("configuration: configuration"))
    }

    func testSettingsWindowInvalidatesTestStateWhenFieldsChange() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/SettingsWindow.swift", encoding: .utf8)
        let changeHandler = try Self.methodBody(named: "func controlTextDidChange(_ obj: Notification)", in: source)
        let draftChanged = try Self.methodBody(named: "private func markSettingsDraftChanged()", in: source)

        XCTAssertTrue(source.contains("final class SettingsWindow: NSPanel, NSTextFieldDelegate"))
        XCTAssertTrue(source.contains("apiBaseURLField.delegate = self"))
        XCTAssertTrue(source.contains("apiKeyField.delegate = self"))
        XCTAssertTrue(source.contains("modelField.delegate = self"))
        XCTAssertTrue(changeHandler.contains("markSettingsDraftChanged()"))
        XCTAssertTrue(draftChanged.contains("statusGeneration += 1"))
        XCTAssertTrue(draftChanged.contains("testController.cancelActiveTest()"))
        XCTAssertTrue(draftChanged.contains("testState = .notRun"))
        XCTAssertTrue(draftChanged.contains("Unsaved changes"))
        XCTAssertTrue(draftChanged.contains("Test uses current fields once"))
        XCTAssertTrue(draftChanged.contains("Save persists them"))
        XCTAssertFalse(draftChanged.contains("applyFields()"))
        XCTAssertFalse(draftChanged.contains("onSettingsSaved?()"))
    }

    func testLoadSettingsSuppressesDraftChangeStatus() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/SettingsWindow.swift", encoding: .utf8)
        let loadSettings = try Self.methodBody(named: "private func loadSettings()", in: source)
        let changeHandler = try Self.methodBody(named: "func controlTextDidChange(_ obj: Notification)", in: source)

        XCTAssertTrue(source.contains("private var isLoadingSettings = false"))
        XCTAssertTrue(loadSettings.contains("isLoadingSettings = true"))
        XCTAssertTrue(loadSettings.contains("defer { isLoadingSettings = false }"))
        XCTAssertTrue(loadSettings.contains("refreshConfigurationStatus()"))
        XCTAssertFalse(loadSettings.contains("markSettingsDraftChanged()"))
        XCTAssertTrue(changeHandler.contains("guard !isLoadingSettings else { return }"))
    }

    func testSettingsDraftChangeStatusDoesNotExposeSecretOrPersist() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/SettingsWindow.swift", encoding: .utf8)
        let draftChanged = try Self.methodBody(named: "private func markSettingsDraftChanged()", in: source)

        XCTAssertFalse(draftChanged.contains("apiKeyField.stringValue"))
        XCTAssertFalse(draftChanged.contains("Keychain"))
        XCTAssertFalse(draftChanged.contains("UserDefaults"))
        XCTAssertFalse(draftChanged.contains("applyFields()"))
        XCTAssertFalse(draftChanged.contains("onSettingsSaved?()"))
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

    private static func methodBody(named signature: String, in source: String) throws -> String {
        let methodStart = try XCTUnwrap(source.range(of: signature)?.lowerBound)
        let remainingSource = source[methodStart...]
        var depth = 0
        var hasEnteredBody = false

        for index in remainingSource.indices {
            let character = remainingSource[index]
            if character == "{" {
                depth += 1
                hasEnteredBody = true
            } else if character == "}" {
                depth -= 1
                if hasEnteredBody, depth == 0 {
                    return String(source[methodStart...index])
                }
            }
        }

        return String(remainingSource)
    }
}
