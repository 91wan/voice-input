import XCTest
@testable import VoiceInput

final class KeyMonitorTests: XCTestCase {
    func testFnTransitionsOnlyEmitOnEdges() {
        var state = KeyMonitorState()

        XCTAssertEqual(state.transition(fnDown: true), .fnDown)
        XCTAssertNil(state.transition(fnDown: true))
        XCTAssertEqual(state.transition(fnDown: false), .fnUp)
        XCTAssertNil(state.transition(fnDown: false))
    }

    func testTapDisableResetsPressedFnState() {
        var state = KeyMonitorState()

        XCTAssertEqual(state.transition(fnDown: true), .fnDown)
        XCTAssertEqual(state.resetForTapDisable(), .fnUp)
        XCTAssertNil(state.transition(fnDown: false))
    }
}
