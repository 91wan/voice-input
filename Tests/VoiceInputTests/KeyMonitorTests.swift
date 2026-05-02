import XCTest
@testable import VoiceInput

final class KeyMonitorTests: XCTestCase {
    func testFnTransitionsOnlyEmitOnEdges() {
        var state = KeyMonitorState()

        XCTAssertEqual(state.transition(fnDown: true), .fnDown(mode: .defaultMode))
        XCTAssertNil(state.transition(fnDown: true))
        XCTAssertEqual(state.transition(fnDown: false), .fnUp)
        XCTAssertNil(state.transition(fnDown: false))
    }

    func testOptionFnStartsPromptBuilderShortcutMode() {
        var state = KeyMonitorState()

        XCTAssertEqual(state.transition(fnDown: true, optionDown: true), .fnDown(mode: .promptBuilder))
        XCTAssertNil(state.transition(fnDown: true, optionDown: false))
        XCTAssertEqual(state.transition(fnDown: false), .fnUp)
    }

    func testTapDisableResetsPressedFnState() {
        var state = KeyMonitorState()

        XCTAssertEqual(state.transition(fnDown: true), .fnDown(mode: .defaultMode))
        XCTAssertEqual(state.resetForTapDisable(), .fnUp)
        XCTAssertNil(state.transition(fnDown: false))
    }
}
