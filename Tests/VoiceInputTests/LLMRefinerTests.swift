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
}
