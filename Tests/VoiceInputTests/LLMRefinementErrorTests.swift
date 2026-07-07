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
            (.invalidURL, "invalid_url"),
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

    func testSafeLogSummaryUsesStableBucketForHTTPProviderMessage() {
        let error = LLMRefinementError.httpStatus(
            401,
            "Provider echoed Bearer secret-token sk-live-secret"
        )

        let summary = LLMRefinementError.safeLogSummary(for: error)

        XCTAssertEqual(summary, "http_status=401 hint=check_api_key")
        XCTAssertFalse(summary.contains("Provider echoed"))
        XCTAssertFalse(summary.contains("Bearer"))
        XCTAssertFalse(summary.contains("sk-"))
    }

    func testSafeLogSummaryDoesNotExposeUnknownErrorLocalizedDescription() {
        let error = NSError(domain: "VoiceInputTests", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "secret detail sk-live-secret",
        ])

        let summary = LLMRefinementError.safeLogSummary(for: error)

        XCTAssertEqual(summary, "unknown_error")
        XCTAssertFalse(summary.contains("secret detail"))
        XCTAssertFalse(summary.contains("sk-"))
    }

    func testSafeLogSummaryBucketsConfigurationValidation() {
        XCTAssertEqual(
            LLMRefinementError.safeLogSummary(for: LLMRequestConfiguration.ValidationError.emptyAPIKey),
            "configuration_validation"
        )
    }
}
