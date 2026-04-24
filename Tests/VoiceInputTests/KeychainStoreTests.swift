import XCTest
import Security
@testable import VoiceInput

final class KeychainStoreTests: XCTestCase {
    func testKeychainStoreRoundTripsAndDeletesValue() throws {
        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )

        XCTAssertNil(try store.read())

        try store.write("test-key-value")
        XCTAssertEqual(try store.read(), "test-key-value")

        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testKeychainStoreThrowsOnInvalidUTF8Data() throws {
        let service = "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)"
        let account = "llm-api-key"
        let store = KeychainStore(service: service, account: account)
        defer { try? store.delete() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data([0xff, 0xfe]),
        ]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)

        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? KeychainStoreError, .unexpectedData)
        }
    }
}
