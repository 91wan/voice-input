import XCTest
@testable import VoiceInput

final class RecentTranscriptionStoreTests: XCTestCase {
    func testStoreKeepsMostRecentResultsFirstWithinCapacity() {
        let store = RecentTranscriptionStore(capacity: 3)

        store.record(makeResult("one"))
        store.record(makeResult("two"))
        store.record(makeResult("three"))
        store.record(makeResult("four"))

        XCTAssertEqual(store.results.map(\.finalText), ["four", "three", "two"])
    }

    func testUpdatingMostRecentInjectionResultPreservesExistingResultFields() {
        let store = RecentTranscriptionStore(capacity: 10)
        store.record(makeResult("first"))
        store.record(makeResult("latest"))

        store.updateMostRecentInjectionResult(.failure(.pasteCommandFailed))

        XCTAssertEqual(store.results.map(\.finalText), ["latest", "first"])
        XCTAssertEqual(store.results.first?.injectionResult, .failure(.pasteCommandFailed))
        XCTAssertNil(store.results.last?.injectionResult)
    }

    func testUpdatingSelectedOlderResultDoesNotMutateNewestResult() {
        let store = RecentTranscriptionStore(capacity: 10)
        let older = makeResult("older")
        let latest = makeResult("latest")
        store.record(older)
        store.record(latest)

        store.updateInjectionResult(.success, for: older)

        XCTAssertEqual(store.results.map(\.finalText), ["latest", "older"])
        XCTAssertNil(store.results.first?.injectionResult)
        XCTAssertEqual(store.results.last?.injectionResult, .success)
    }

    func testClearRemovesAllSessionResults() {
        let store = RecentTranscriptionStore(capacity: 10)
        store.record(makeResult("one"))

        store.clear()

        XCTAssertTrue(store.results.isEmpty)
    }

    private func makeResult(_ text: String) -> LastTranscriptionResult {
        LastTranscriptionResult(
            rawText: text,
            filteredText: text,
            refinedText: nil,
            finalText: text,
            dictionaryMatches: [],
            wasLLMRefined: false,
            refinementMode: nil,
            injectionResult: nil
        )
    }
}
