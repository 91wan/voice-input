import XCTest
@testable import VoiceInput

final class LLMRefinementErrorTests: XCTestCase {
    func testHTTPStatusLocalizedDescriptionRemainsUserFacing() {
        let error = LLMRefinementError.httpStatus(401, "Invalid API key")

        XCTAssertTrue(error.localizedDescription.contains("401 Unauthorized"))
        XCTAssertTrue(error.localizedDescription.contains("Invalid API key"))
        XCTAssertTrue(error.localizedDescription.contains("check API key"))
    }

    func testLogSummaryExcludesProviderMessageAndSecretLikeContent() {
        let error = LLMRefinementError.httpStatus(
            401,
            "Provider echoed quota detail Bearer secret-token sk-live-secret"
        )

        XCTAssertEqual(error.logSummary, "http_status=401 hint=check_api_key")
        XCTAssertFalse(error.logSummary.contains("Provider echoed quota detail"))
        XCTAssertFalse(error.logSummary.contains("Bearer"))
        XCTAssertFalse(error.logSummary.contains("sk-live-secret"))
        XCTAssertFalse(error.logSummary.contains("sk-"))
    }

    func testLogSummaryUsesStableSafeBuckets() {
        let cases: [(LLMRefinementError, String)] = [
            (.configuration(.emptyAPIKey), "configuration_empty_api_key"),
            (.configuration(.invalidAPIBaseURL), "configuration_invalid_api_base_url"),
            (.cancelled, "cancelled"),
            (.invalidResponse, "invalid_response"),
            (.transport("connection dropped"), "transport"),
            (.httpStatus(404, "model not found"), "http_status=404 hint=check_model_or_api_base_url"),
            (.httpStatus(429, "too many requests"), "http_status=429 hint=try_later"),
            (.httpStatus(503, "upstream unavailable"), "http_status=503 hint=provider_status"),
            (.httpStatus(418, "teapot"), "http_status=418"),
        ]

        for (error, expectedSummary) in cases {
            XCTAssertEqual(error.logSummary, expectedSummary)
        }
    }

    func testConfigurationErrorsDelegateUserFacingDescriptions() {
        XCTAssertEqual(
            LLMRefinementError.configuration(.emptyAPIKey).localizedDescription,
            LLMRequestConfiguration.ValidationError.emptyAPIKey.localizedDescription
        )
        XCTAssertEqual(
            LLMRefinementError.configuration(.invalidAPIBaseURL).localizedDescription,
            LLMRequestConfiguration.ValidationError.invalidAPIBaseURL.localizedDescription
        )
    }

    func testTransportLogSummaryDoesNotExposeSystemMessage() {
        let error = LLMRefinementError.transport("connection failed sk-live-secret")

        XCTAssertEqual(error.logSummary, "transport")
        XCTAssertFalse(error.logSummary.contains("connection failed"))
        XCTAssertFalse(error.logSummary.contains("sk-"))
    }
}
