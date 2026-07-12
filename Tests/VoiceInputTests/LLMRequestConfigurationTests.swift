import XCTest
@testable import VoiceInput

final class LLMRequestConfigurationTests: XCTestCase {
    func testValidatedTrimsValues() throws {
        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "  https://transient.example/v1  ",
            apiKey: "  transient-key  ",
            model: "  transient-model  "
        )

        XCTAssertEqual(configuration.apiBaseURL, "https://transient.example/v1")
        XCTAssertEqual(configuration.chatCompletionsURL.absoluteString, "https://transient.example/v1/chat/completions")
        XCTAssertEqual(configuration.model, "transient-model")
        XCTAssertTrue(configuration.hasAPIKey)
    }

    func testValidatedUsesDefaultsForBlankBaseURLAndModel() throws {
        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "   ",
            apiKey: " transient-key ",
            model: "   "
        )

        XCTAssertEqual(configuration.apiBaseURL, LLMRequestConfiguration.defaultAPIBaseURL)
        XCTAssertEqual(
            configuration.chatCompletionsURL.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(configuration.model, LLMRequestConfiguration.defaultModel)
        XCTAssertTrue(configuration.hasAPIKey)
    }

    func testValidatedRejectsEmptyAPIKey() {
        XCTAssertThrowsError(
            try LLMRequestConfiguration.validated(
                apiBaseURL: "https://api.openai.com/v1",
                apiKey: "   ",
                model: "gpt-4o-mini"
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "API key is empty")
        }
    }

    func testValidationResultReturnsTypedEmptyAPIKeyFailure() {
        let result = LLMRequestConfiguration.validationResult(
            apiBaseURL: "https://api.openai.com/v1",
            apiKey: "   ",
            model: "gpt-4o-mini"
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected empty API key failure")
        }
        XCTAssertEqual(error, .emptyAPIKey)
    }

    func testValidatedRejectsInvalidAPIBaseURL() {
        XCTAssertThrowsError(
            try LLMRequestConfiguration.validated(
                apiBaseURL: "http://api.example.com/v1",
                apiKey: "transient-key",
                model: "gpt-4o-mini"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid API base URL"))
        }
    }

    func testValidationResultReturnsTypedInvalidBaseURLFailure() {
        let result = LLMRequestConfiguration.validationResult(
            apiBaseURL: "http://api.example.com/v1",
            apiKey: "transient-key",
            model: "gpt-4o-mini"
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected invalid base URL failure")
        }
        XCTAssertEqual(error, .invalidAPIBaseURL)
    }

    func testValidatedStoresCustomLoopbackEndpointWithoutDuplicatingPath() throws {
        let localhost = try LLMRequestConfiguration.validated(
            apiBaseURL: "http://localhost:1234/v1",
            apiKey: "transient-key",
            model: "local-model"
        )
        let completeEndpoint = try LLMRequestConfiguration.validated(
            apiBaseURL: "https://transient.example/v1/chat/completions",
            apiKey: "transient-key",
            model: "remote-model"
        )

        XCTAssertEqual(localhost.chatCompletionsURL.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(
            completeEndpoint.chatCompletionsURL.absoluteString,
            "https://transient.example/v1/chat/completions"
        )
    }

    func testAppliesAuthorizationWithoutExposingAPIKeyAsState() throws {
        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "https://transient.example/v1",
            apiKey: "transient-key",
            model: "transient-model"
        )
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://transient.example/v1/chat/completions")))

        configuration.applyAuthorization(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer transient-key")
        XCTAssertTrue(configuration.hasAPIKey)
    }

    func testDescriptionsRedactAPIKey() throws {
        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "https://transient.example/v1",
            apiKey: "sk-transient-secret",
            model: "transient-model"
        )

        let descriptions = [
            String(describing: configuration),
            String(reflecting: configuration),
            configuration.debugDescription,
        ]

        for description in descriptions {
            XCTAssertTrue(description.contains("https://transient.example/v1"))
            XCTAssertTrue(description.contains("transient-model"))
            XCTAssertTrue(description.contains("[redacted]"))
            XCTAssertFalse(description.contains("sk-transient-secret"))
            XCTAssertFalse(description.contains("Bearer"))
            XCTAssertFalse(description.contains("sk-"))
        }
    }

    func testChatCompletionsURLNormalizesValidBaseURLs() {
        XCTAssertEqual(
            LLMRequestConfiguration.chatCompletionsURL(from: " https://api.openai.com/v1/ ")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRequestConfiguration.chatCompletionsURL(from: "http://localhost:1234/v1")?.absoluteString,
            "http://localhost:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRequestConfiguration.chatCompletionsURL(from: "http://127.0.0.1:1234/v1//")?.absoluteString,
            "http://127.0.0.1:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRequestConfiguration.chatCompletionsURL(from: "http://[::1]:1234/v1")?.absoluteString,
            "http://[::1]:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRequestConfiguration.chatCompletionsURL(from: "https://api.openai.com/v1/chat/completions")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
    }

    func testChatCompletionsURLRejectsUnsafeBaseURLs() {
        XCTAssertNil(LLMRequestConfiguration.chatCompletionsURL(from: "http://api.example.com/v1"))
        XCTAssertNil(LLMRequestConfiguration.chatCompletionsURL(from: "localhost:1234/v1"))
        XCTAssertNil(LLMRequestConfiguration.chatCompletionsURL(from: "file:///tmp/api"))
        XCTAssertNil(LLMRequestConfiguration.chatCompletionsURL(from: "not a url"))
        XCTAssertNil(LLMRequestConfiguration.chatCompletionsURL(from: "https://api.openai.com/v1?debug=true"))
        XCTAssertNil(LLMRequestConfiguration.chatCompletionsURL(from: "https://user:pass@api.openai.com/v1"))
    }
}
