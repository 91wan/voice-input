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
}
