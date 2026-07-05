import XCTest
@testable import VoiceInput

final class SettingsTestLifecycleTests: XCTestCase {
    private final class StubRequest: CancellableRequest {
        private(set) var cancelCount = 0

        func cancel() {
            cancelCount += 1
        }
    }

    func testSecondTestCancelsFirstRequest() {
        let first = StubRequest()
        let second = StubRequest()
        let controller = LLMSettingsTestController()

        let firstGeneration = controller.beginTest(request: first)
        let secondGeneration = controller.beginTest(request: second)

        XCTAssertEqual(firstGeneration, 1)
        XCTAssertEqual(secondGeneration, 2)
        XCTAssertEqual(first.cancelCount, 1)
        XCTAssertEqual(second.cancelCount, 0)
    }

    func testLateCompletionFromOlderGenerationIsIgnored() {
        let first = StubRequest()
        let second = StubRequest()
        let controller = LLMSettingsTestController()

        let firstGeneration = controller.beginTest(request: first)
        let secondGeneration = controller.beginTest(request: second)

        XCTAssertFalse(controller.finishTest(generation: firstGeneration))
        XCTAssertTrue(controller.finishTest(generation: secondGeneration))
    }

    func testSaveOrCloseCancelsActiveRequest() {
        let request = StubRequest()
        let controller = LLMSettingsTestController()

        _ = controller.beginTest(request: request)
        controller.cancelActiveTest()

        XCTAssertEqual(request.cancelCount, 1)
        XCTAssertTrue(controller.isIdle)
    }

    func testSettingsTestCancellationDoesNotCancelDictationRequest() {
        let settingsRequest = StubRequest()
        let dictationRequest = StubRequest()
        let controller = LLMSettingsTestController()

        _ = controller.beginTest(request: settingsRequest)
        controller.cancelActiveTest()

        XCTAssertEqual(settingsRequest.cancelCount, 1)
        XCTAssertEqual(dictationRequest.cancelCount, 0)
    }

    func testNewAttemptBeforeValidationCancelsActiveRequest() {
        let oldRequest = StubRequest()
        let controller = LLMSettingsTestController()

        let oldGeneration = controller.beginTest(request: oldRequest)
        let newGeneration = controller.beginAttempt()

        XCTAssertEqual(oldRequest.cancelCount, 1)
        XCTAssertTrue(controller.isIdle)
        XCTAssertFalse(controller.finishTest(generation: oldGeneration))
        XCTAssertEqual(newGeneration, oldGeneration + 1)
    }

    func testNewAttemptBeforeEmptyAPIKeyBranchCancelsActiveRequest() {
        let oldRequest = StubRequest()
        let controller = LLMSettingsTestController()

        _ = controller.beginTest(request: oldRequest)
        _ = controller.beginAttempt()

        XCTAssertEqual(oldRequest.cancelCount, 1)
        XCTAssertTrue(controller.isIdle)
    }

    func testFieldEditCancellationInvalidatesInFlightCompletion() {
        let request = StubRequest()
        let controller = LLMSettingsTestController()

        let generation = controller.beginTest(request: request)
        controller.cancelActiveTest()

        XCTAssertEqual(request.cancelCount, 1)
        XCTAssertTrue(controller.isIdle)
        XCTAssertFalse(controller.finishTest(generation: generation))
    }
}
