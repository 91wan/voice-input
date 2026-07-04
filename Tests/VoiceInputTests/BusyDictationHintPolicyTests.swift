import XCTest
@testable import VoiceInput

final class BusyDictationHintPolicyTests: XCTestCase {
    func testResolvingWithVisibleOverlayDoesNotShowTransientHint() {
        XCTAssertFalse(
            BusyDictationHintPolicy.shouldShowTransient(
                phase: .resolving(sessionID: 1),
                isOverlayVisible: true
            )
        )
    }

    func testResolvingWithoutVisibleOverlayShowsTransientHint() {
        XCTAssertTrue(
            BusyDictationHintPolicy.shouldShowTransient(
                phase: .resolving(sessionID: 1),
                isOverlayVisible: false
            )
        )
    }

    func testIdleDoesNotShowTransientHint() {
        XCTAssertFalse(
            BusyDictationHintPolicy.shouldShowTransient(
                phase: .idle,
                isOverlayVisible: false
            )
        )
    }
}
