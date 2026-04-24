import Foundation
import Security
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

    func testApiKeyReadFailureIsLoggedInsteadOfSilentlyDisappearing() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let service = "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service, account: "llm-api-key")
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "llm-api-key",
            kSecValueData as String: Data([0xff, 0xfe]),
        ]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)

        var logs: [String] = []
        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { logs.append($0) }
        )

        XCTAssertEqual(refiner.apiKey, "")
        XCTAssertTrue(logs.contains { $0.contains("Failed to read LLM API key from Keychain") })
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
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "http://127.0.0.1:1234/v1//")?.absoluteString,
            "http://127.0.0.1:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "https://api.openai.com/v1/chat/completions")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "localhost:1234/v1"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "file:///tmp/api"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "not a url"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "https://api.openai.com/v1?debug=true"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "https://user:pass@api.openai.com/v1"))
    }
}
