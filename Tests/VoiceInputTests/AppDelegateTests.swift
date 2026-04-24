import XCTest
@testable import VoiceInput

final class AppDelegateTests: XCTestCase {
    func testEmptyLocaleCodeResolvesToSystemCurrentLocale() {
        XCTAssertEqual(
            AppDelegate.locale(forSelectedLocaleCode: "").identifier,
            Locale.current.identifier
        )
    }

    func testExplicitLocaleCodeResolvesToRequestedLocale() {
        XCTAssertEqual(
            AppDelegate.locale(forSelectedLocaleCode: "en-US").identifier,
            Locale(identifier: "en-US").identifier
        )
    }
}
