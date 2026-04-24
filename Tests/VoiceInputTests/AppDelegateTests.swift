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

    func testScheduledOneShotTimerFiresOnce() {
        let expectation = expectation(description: "timer fired")
        var fireCount = 0

        let timer = AppDelegate.scheduleOneShotTimer(interval: 0.01) { _ in
            fireCount += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertFalse(timer.isValid)
        XCTAssertEqual(fireCount, 1)
    }
}
