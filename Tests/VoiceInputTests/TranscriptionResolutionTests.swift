import XCTest
@testable import VoiceInput

final class TranscriptionResolutionTests: XCTestCase {
    func testUsesRefinedTextWhenLLMReturnsNonEmptyText() {
        let output = TranscriptionResolution.resolve(
            filteredText: "OpenClaw 已部署",
            refinedText: "OpenClaw 已经部署。"
        )

        XCTAssertEqual(output.text, "OpenClaw 已经部署。")
        XCTAssertTrue(output.wasLLMRefined)
    }

    func testFallsBackToFilteredTextWhenLLMReturnsEmptyText() {
        let output = TranscriptionResolution.resolve(
            filteredText: "OpenClaw 已部署",
            refinedText: "   "
        )

        XCTAssertEqual(output.text, "OpenClaw 已部署")
        XCTAssertFalse(output.wasLLMRefined)
    }

    func testFallsBackToFilteredTextWhenLLMFails() {
        let output = TranscriptionResolution.resolve(
            filteredText: "OpenClaw 已部署",
            refinedText: nil
        )

        XCTAssertEqual(output.text, "OpenClaw 已部署")
        XCTAssertFalse(output.wasLLMRefined)
    }
}
