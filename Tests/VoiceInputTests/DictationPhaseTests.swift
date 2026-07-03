import XCTest
@testable import VoiceInput

final class DictationPhaseTests: XCTestCase {
    func testIdleFnDownStartsHold() {
        var phase = DictationPhase.idle

        XCTAssertEqual(phase.fnDown(), .startHold)
        XCTAssertEqual(phase, .holding)
    }

    func testHoldingThresholdStartsRecording() {
        var phase = DictationPhase.holding

        XCTAssertEqual(phase.holdThresholdReached(sessionID: 7), .startRecording(sessionID: 7))
        XCTAssertEqual(phase, .recording(sessionID: 7))
    }

    func testRecordingFnUpStartsResolving() {
        var phase = DictationPhase.recording(sessionID: 7)

        XCTAssertEqual(phase.fnUp(), .stopRecording(sessionID: 7))
        XCTAssertEqual(phase, .resolving(sessionID: 7))
    }

    func testResolvingFnDownRejectsAsBusy() {
        var phase = DictationPhase.resolving(sessionID: 7)

        XCTAssertEqual(phase.fnDown(), .rejectBecauseBusy)
        XCTAssertEqual(phase, .resolving(sessionID: 7))
    }

    func testInjectingFnDownRejectsAsBusy() {
        var phase = DictationPhase.injecting(sessionID: 7)

        XCTAssertEqual(phase.fnDown(), .rejectBecauseBusy)
        XCTAssertEqual(phase, .injecting(sessionID: 7))
    }

    func testResolvingCompletesThroughInjectingToIdle() {
        var phase = DictationPhase.resolving(sessionID: 7)

        XCTAssertEqual(phase.beginInjection(sessionID: 7), .beginInjecting(sessionID: 7))
        XCTAssertEqual(phase, .injecting(sessionID: 7))
        XCTAssertEqual(phase.finishInjection(sessionID: 7), .finish)
        XCTAssertEqual(phase, .idle)
    }

    func testResetReturnsAnyPhaseToIdle() {
        for originalPhase in [
            DictationPhase.holding,
            .recording(sessionID: 1),
            .resolving(sessionID: 1),
            .injecting(sessionID: 1),
        ] {
            var phase = originalPhase

            XCTAssertEqual(phase.reset(), .reset)
            XCTAssertEqual(phase, .idle)
        }
    }
}
