import XCTest
@testable import VoiceInput

final class RetryInsertPolicyTests: XCTestCase {
    func testIdleAllowsRetryInsert() {
        XCTAssertEqual(RetryInsertPolicy.availability(phase: .idle), .allowed)
    }

    func testActiveDictationPhasesBlockRetryInsert() {
        let busyPhases: [DictationPhase] = [
            .holding,
            .recording(sessionID: 1),
            .resolving(sessionID: 1),
            .injecting(sessionID: 1),
        ]

        for phase in busyPhases {
            XCTAssertEqual(
                RetryInsertPolicy.availability(phase: phase),
                .busy("Finish the current dictation before retrying insertion.")
            )
        }
    }

    func testAppDelegateRetryInsertAvailabilityUsesDictationPhase() {
        XCTAssertEqual(AppDelegate.retryInsertAvailability(phase: .idle), .allowed)
        XCTAssertEqual(
            AppDelegate.retryInsertAvailability(phase: .resolving(sessionID: 1)),
            .busy("Finish the current dictation before retrying insertion.")
        )
    }

    func testBusyRetryInsertDoesNotProceedToWindowHideOrAppActivation() {
        XCTAssertEqual(
            RetryInsertPresentationPolicy.plan(
                availability: .busy("Finish the current dictation before retrying insertion."),
                hasTargetApplication: true
            ),
            .showBusyStatus("Finish the current dictation before retrying insertion.")
        )
    }

    func testAllowedRetryInsertRequiresTargetApplicationBeforeProceeding() {
        XCTAssertEqual(
            RetryInsertPresentationPolicy.plan(availability: .allowed, hasTargetApplication: false),
            .missingTargetApplication
        )
        XCTAssertEqual(
            RetryInsertPresentationPolicy.plan(availability: .allowed, hasTargetApplication: true),
            .proceed
        )
    }

    func testDelayedRetryInsertRechecksAvailabilityBeforeProceeding() {
        XCTAssertEqual(
            RetryInsertPresentationPolicy.delayedPlan(
                availability: .busy("Finish the current dictation before retrying insertion.")
            ),
            .showBusyStatus("Finish the current dictation before retrying insertion.")
        )
        XCTAssertEqual(
            RetryInsertPresentationPolicy.delayedPlan(availability: .allowed),
            .proceed
        )
    }
}
