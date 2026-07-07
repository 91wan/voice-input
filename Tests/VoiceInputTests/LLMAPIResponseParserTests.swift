import Foundation
import XCTest
@testable import VoiceInput

final class LLMAPIResponseParserTests: XCTestCase {
    func testSuccessResponseReturnsTrimmedContent() throws {
        let result = LLMAPIResponseParser.parse(
            data: Self.successData("  refined text\n"),
            response: Self.httpResponse(statusCode: 200),
            error: nil
        )

        XCTAssertEqual(try result.get(), "refined text")
    }

    func testMalformedSuccessJSONReturnsInvalidResponse() {
        let result = LLMAPIResponseParser.parse(
            data: Self.jsonData(["choices": []]),
            response: Self.httpResponse(statusCode: 200),
            error: nil
        )

        XCTAssertEqual(result.failure, .invalidResponse)
    }

    func testNilDataReturnsInvalidResponse() {
        let result = LLMAPIResponseParser.parse(
            data: nil,
            response: Self.httpResponse(statusCode: 200),
            error: nil
        )

        XCTAssertEqual(result.failure, .invalidResponse)
    }

    func testCancelledURLErrorReturnsCancelled() {
        let result = LLMAPIResponseParser.parse(
            data: nil,
            response: nil,
            error: URLError(.cancelled)
        )

        XCTAssertEqual(result.failure, .cancelled)
    }

    func testGenericTransportErrorReturnsTransportMessage() {
        let result = LLMAPIResponseParser.parse(
            data: nil,
            response: nil,
            error: NSError(domain: "VoiceInputTests", code: 42, userInfo: [
                NSLocalizedDescriptionKey: "connection dropped",
            ])
        )

        XCTAssertEqual(result.failure, .transport("connection dropped"))
    }

    func testTransportErrorRedactsBearerAndSKTokens() throws {
        let result = LLMAPIResponseParser.parse(
            data: nil,
            response: nil,
            error: NSError(domain: "VoiceInputTests", code: 43, userInfo: [
                NSLocalizedDescriptionKey: "Bearer secret-token failed for sk-live-secret",
            ])
        )

        let error = try XCTUnwrap(result.failure)
        let description = error.localizedDescription
        XCTAssertEqual(error, .transport("[redacted] failed for [redacted]"))
        XCTAssertFalse(description.contains("Bearer secret-token"))
        XCTAssertFalse(description.contains("sk-live-secret"))
        XCTAssertFalse(description.contains("sk-"))
    }

    func testHTTP401IncludesUnauthorizedAPIMessageAndRecoveryHint() throws {
        let result = LLMAPIResponseParser.parse(
            data: Self.errorData(message: "Invalid API key"),
            response: Self.httpResponse(statusCode: 401),
            error: nil
        )

        let error = try XCTUnwrap(result.failure)
        XCTAssertEqual(error, .httpStatus(401, "Invalid API key"))
        XCTAssertTrue(error.localizedDescription.contains("401 Unauthorized"))
        XCTAssertTrue(error.localizedDescription.contains("Invalid API key"))
        XCTAssertTrue(error.localizedDescription.contains("check API key"))
    }

    func testHTTP404SuggestsModelOrBaseURL() throws {
        let result = LLMAPIResponseParser.parse(
            data: Self.errorData(message: "model not found"),
            response: Self.httpResponse(statusCode: 404),
            error: nil
        )

        let error = try XCTUnwrap(result.failure)
        XCTAssertEqual(error, .httpStatus(404, "model not found"))
        XCTAssertTrue(error.localizedDescription.contains("404 Not Found"))
        XCTAssertTrue(error.localizedDescription.contains("check model or API base URL"))
    }

    func testHTTP429SuggestsTryLater() throws {
        let result = LLMAPIResponseParser.parse(
            data: Self.errorData(message: "too many requests"),
            response: Self.httpResponse(statusCode: 429),
            error: nil
        )

        let error = try XCTUnwrap(result.failure)
        XCTAssertEqual(error, .httpStatus(429, "too many requests"))
        XCTAssertTrue(error.localizedDescription.contains("429 Rate Limited"))
        XCTAssertTrue(error.localizedDescription.contains("try later"))
    }

    func testServerErrorSuggestsProviderStatus() throws {
        let result = LLMAPIResponseParser.parse(
            data: Self.errorData(message: "upstream unavailable"),
            response: Self.httpResponse(statusCode: 503),
            error: nil
        )

        let error = try XCTUnwrap(result.failure)
        XCTAssertEqual(error, .httpStatus(503, "upstream unavailable"))
        XCTAssertTrue(error.localizedDescription.contains("503 Service Unavailable"))
        XCTAssertTrue(error.localizedDescription.contains("check the API provider status"))
    }

    func testAPIErrorMessageRedactsBearerAndSKTokens() throws {
        let result = LLMAPIResponseParser.parse(
            data: Self.errorData(message: "Bearer secret-token failed for sk-live-secret"),
            response: Self.httpResponse(statusCode: 401),
            error: nil
        )

        let error = try XCTUnwrap(result.failure)
        let description = error.localizedDescription
        XCTAssertEqual(error, .httpStatus(401, "[redacted] failed for [redacted]"))
        XCTAssertFalse(description.contains("Bearer secret-token"))
        XCTAssertFalse(description.contains("sk-live-secret"))
        XCTAssertFalse(description.contains("sk-"))
    }

    private static func successData(_ content: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        jsonData(
            [
                "choices": [
                    [
                        "message": [
                            "content": content,
                        ],
                    ],
                ],
            ],
            file: file,
            line: line
        )
    }

    private static func errorData(message: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        jsonData(
            [
                "error": [
                    "message": message,
                    "type": "invalid_request_error",
                    "code": "test_error",
                ],
            ],
            file: file,
            line: line
        )
    }

    private static func jsonData(
        _ json: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: json)
        } catch {
            XCTFail("Failed to encode test JSON: \(error)", file: file, line: line)
            return Data()
        }
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.test/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private extension Result where Failure == LLMRefinementError {
    var failure: LLMRefinementError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
