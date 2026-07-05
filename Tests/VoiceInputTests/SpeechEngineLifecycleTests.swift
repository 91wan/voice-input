import XCTest
@testable import VoiceInput

final class SpeechEngineLifecycleTests: XCTestCase {
    func testFinishAfterResultConsumedIsIdempotentAndSilent() {
        let engine = SpeechEngine()
        engine.onError = { message in
            XCTFail("finishAfterResultConsumed should not deliver UI errors, got: \(message)")
        }

        engine.finishAfterResultConsumed()
        engine.finishAfterResultConsumed()
    }

}
