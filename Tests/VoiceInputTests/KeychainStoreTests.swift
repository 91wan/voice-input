import XCTest
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
}
