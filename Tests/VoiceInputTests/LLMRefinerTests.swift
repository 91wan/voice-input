import Foundation
import XCTest
@testable import VoiceInput

final class LLMRefinerTests: XCTestCase {
    func testApiKeyMigratesFromUserDefaultsToKeychain() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("legacy-test-key", forKey: "llmAPIKey")

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        XCTAssertEqual(refiner.apiKey, "legacy-test-key")
        XCTAssertNil(defaults.string(forKey: "llmAPIKey"))
        XCTAssertEqual(try store.read(), "legacy-test-key")
    }

    func testUpdateAPIKeyDeletesEmptyValueFromKeychain() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        try refiner.updateAPIKey("  test-key-value  ")
        XCTAssertEqual(try store.read(), "test-key-value")

        try refiner.updateAPIKey("   ")
        XCTAssertNil(try store.read())
    }

    func testBlankBaseURLAndModelFallBackToDefaults() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        refiner.apiBaseURL = "   "
        refiner.model = "  "

        XCTAssertEqual(refiner.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertEqual(refiner.model, LLMRefiner.defaultModel)
        XCTAssertNil(defaults.object(forKey: "llmAPIBaseURL"))
        XCTAssertNil(defaults.object(forKey: "llmModel"))
    }

    func testChatCompletionsURLRequiresHTTPURLWithHost() {
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: " https://api.openai.com/v1/ ")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "http://localhost:1234/v1")?.absoluteString,
            "http://localhost:1234/v1/chat/completions"
        )
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "localhost:1234/v1"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "file:///tmp/api"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "not a url"))
    }
}
