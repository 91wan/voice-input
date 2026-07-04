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

    func testFinishAfterResultConsumedClearsRecognitionSessionResources() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/SpeechEngine.swift", encoding: .utf8)
        let methodStart = try XCTUnwrap(source.range(of: "func finishAfterResultConsumed()")?.lowerBound)
        let methodEnd = try XCTUnwrap(source.range(of: "func cancel()", range: methodStart..<source.endIndex)?.lowerBound)
        let methodSource = String(source[methodStart..<methodEnd])

        XCTAssertTrue(methodSource.contains("recognitionSessions.invalidate()"))
        XCTAssertTrue(methodSource.contains("finalResultSessionID = nil"))
        XCTAssertTrue(methodSource.contains("cleanup()"))

        let invalidate = try XCTUnwrap(methodSource.range(of: "recognitionSessions.invalidate()")?.lowerBound)
        let clearFinal = try XCTUnwrap(methodSource.range(of: "finalResultSessionID = nil")?.lowerBound)
        let cleanup = try XCTUnwrap(methodSource.range(of: "cleanup()")?.lowerBound)
        XCTAssertLessThan(invalidate, cleanup)
        XCTAssertLessThan(clearFinal, cleanup)
    }
}
