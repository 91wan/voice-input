import XCTest
@testable import VoiceInput

final class SessionCounterTests: XCTestCase {
    func testBeginMakesNewestSessionCurrent() {
        var counter = SessionCounter()

        let first = counter.begin()
        let second = counter.begin()

        XCTAssertFalse(counter.isCurrent(first))
        XCTAssertTrue(counter.isCurrent(second))
    }

    func testInvalidateExpiresPreviousSession() {
        var counter = SessionCounter()

        let current = counter.begin()
        counter.invalidate()

        XCTAssertFalse(counter.isCurrent(current))
        XCTAssertEqual(counter.currentID, current + 1)
    }

    func testClaimCurrentSessionOnlySucceedsOnce() {
        var counter = SessionCounter()

        let current = counter.begin()

        XCTAssertTrue(counter.claimCurrent(current))
        XCTAssertFalse(counter.claimCurrent(current))
    }

    func testClaimCurrentSessionRejectsExpiredSession() {
        var counter = SessionCounter()

        let expired = counter.begin()
        _ = counter.begin()

        XCTAssertFalse(counter.claimCurrent(expired))
    }

    func testBeginResetsClaimForNewSession() {
        var counter = SessionCounter()

        let first = counter.begin()
        XCTAssertTrue(counter.claimCurrent(first))

        let second = counter.begin()
        XCTAssertTrue(counter.claimCurrent(second))
    }
}
