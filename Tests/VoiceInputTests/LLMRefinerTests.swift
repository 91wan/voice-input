import Foundation
import Security
import XCTest
@testable import VoiceInput

final class LLMRefinerTests: XCTestCase {
    private final class MockNetworkTask: LLMNetworkTask {
        private(set) var resumeCount = 0
        private(set) var cancelCount = 0

        func resume() {
            resumeCount += 1
        }

        func cancel() {
            cancelCount += 1
        }
    }

    private struct CapturedRequest {
        let request: URLRequest
        let task: MockNetworkTask
        let completion: (Data?, URLResponse?, Error?) -> Void
    }

    private final class RequestRecorder {
        private(set) var capturedRequests: [CapturedRequest] = []

        func perform(
            request: URLRequest,
            completion: @escaping (Data?, URLResponse?, Error?) -> Void
        ) -> LLMNetworkTask {
            let task = MockNetworkTask()
            capturedRequests.append(CapturedRequest(request: request, task: task, completion: completion))
            return task
        }
    }

    func testApiKeyMigratesFromUserDefaultsToKeychain() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("legacy-test-key", forKey: "llmAPIKey")

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        XCTAssertEqual(refiner.apiKey, "legacy-test-key")
        XCTAssertNil(defaults.string(forKey: "llmAPIKey"))
        XCTAssertEqual(try store.read(), "legacy-test-key")
    }

    func testUpdateAPIKeyDeletesEmptyValueFromKeychain() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        try refiner.updateAPIKey("  test-key-value  ")
        XCTAssertEqual(try store.read(), "test-key-value")

        try refiner.updateAPIKey("   ")
        XCTAssertNil(try store.read())
    }

    func testApiKeyReadFailureIsLoggedInsteadOfSilentlyDisappearing() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let service = "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service, account: "llm-api-key")
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "llm-api-key",
            kSecValueData as String: Data([0xff, 0xfe]),
        ]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)

        var logs: [String] = []
        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { logs.append($0) }
        )

        XCTAssertEqual(refiner.apiKey, "")
        XCTAssertTrue(logs.contains { $0.contains("Failed to read LLM API key from Keychain") })
    }

    func testBlankBaseURLAndModelFallBackToDefaults() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        refiner.apiBaseURL = "   "
        refiner.model = "  "

        XCTAssertEqual(refiner.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertEqual(refiner.model, LLMRefiner.defaultModel)
        XCTAssertNil(defaults.object(forKey: "llmAPIBaseURL"))
        XCTAssertNil(defaults.object(forKey: "llmModel"))
    }

    func testLLMRequestConfigurationValidatedTrimsValues() throws {
        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "  https://transient.example/v1  ",
            apiKey: "  transient-key  ",
            model: "  transient-model  "
        )

        XCTAssertEqual(configuration.apiBaseURL, "https://transient.example/v1")
        XCTAssertEqual(configuration.apiKey, "transient-key")
        XCTAssertEqual(configuration.model, "transient-model")
    }

    func testLLMRequestConfigurationValidatedUsesDefaultsForBlankBaseURLAndModel() throws {
        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "   ",
            apiKey: " transient-key ",
            model: "   "
        )

        XCTAssertEqual(configuration.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertEqual(configuration.apiKey, "transient-key")
        XCTAssertEqual(configuration.model, LLMRefiner.defaultModel)
    }

    func testLLMRequestConfigurationValidatedRejectsEmptyAPIKey() {
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

    func testLLMRequestConfigurationValidatedRejectsInvalidAPIBaseURL() {
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

    func testRefinementModeDefaultsToPreciseAndClearsInvalidPersistedValue() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("unknown-mode", forKey: "llmMode")

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        XCTAssertEqual(refiner.mode, .precise)
        XCTAssertNil(defaults.object(forKey: "llmMode"))
    }

    func testPromptBuilderModeUsesPromptOrientedSystemPrompt() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        refiner.mode = .promptBuilder
        let body = refiner.chatRequestBody(for: "help me ask ChatGPT for SQL")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        let systemPrompt = try XCTUnwrap(messages.first?["content"])

        XCTAssertEqual(refiner.mode, .promptBuilder)
        XCTAssertEqual(defaults.string(forKey: "llmMode"), "promptBuilder")
        XCTAssertTrue(systemPrompt.contains("AI prompt"))
        XCTAssertTrue(systemPrompt.contains("Do NOT answer"))
    }

    func testPromptBuilderOverrideDoesNotPersistMode() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        refiner.mode = .precise
        let body = refiner.chatRequestBody(
            for: "make this into a concise coding prompt",
            mode: .promptBuilder
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        let systemPrompt = try XCTUnwrap(messages.first?["content"])

        XCTAssertTrue(systemPrompt.contains("AI prompt"))
        XCTAssertEqual(body["temperature"] as? Double, LLMRefinementMode.promptBuilder.temperature)
        XCTAssertEqual(refiner.mode, .precise)
        XCTAssertNil(defaults.string(forKey: "llmMode"))
    }

    func testRefineFallsBackToInputWithoutErrorWhenLLMIsUnavailable() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )
        refiner.isEnabled = true

        let expectation = expectation(description: "fallback delivered")
        refiner.refine("filtered text", mode: .promptBuilder) { result in
            XCTAssertEqual(try? result.get(), "filtered text")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testCancelDeliversCancellationInsteadOfDroppingCompletion() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = KeychainStore(service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)", account: "llm-api-key")
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        var capturedRequests: [CapturedRequest] = []
        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in },
            requestPerformer: { request, completion in
                let task = MockNetworkTask()
                capturedRequests.append(CapturedRequest(request: request, task: task, completion: completion))
                return task
            }
        )
        try refiner.updateAPIKey("test-key")

        let expectation = expectation(description: "cancel delivered")
        refiner.refine("filtered text", force: true) { result in
            guard case .failure(let error as LLMRefiner.RefinerError) = result else {
                return XCTFail("Expected cancellation error, got \(result)")
            }
            XCTAssertEqual(error, .cancelled)
            expectation.fulfill()
        }

        XCTAssertEqual(capturedRequests.count, 1)
        XCTAssertEqual(capturedRequests[0].task.resumeCount, 1)

        refiner.cancel()

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(capturedRequests[0].task.cancelCount, 1)
    }

    func testStartingSettingsTestDoesNotCancelActiveDictationRefinement() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = KeychainStore(service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)", account: "llm-api-key")
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        var capturedRequests: [CapturedRequest] = []
        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in },
            requestPerformer: { request, completion in
                let task = MockNetworkTask()
                capturedRequests.append(CapturedRequest(request: request, task: task, completion: completion))
                return task
            }
        )
        try refiner.updateAPIKey("test-key")

        let dictationExpectation = expectation(description: "dictation completes")
        let settingsExpectation = expectation(description: "settings completes")

        refiner.refine("dictation text", force: true) { result in
            XCTAssertEqual(try? result.get(), "dictation refined")
            dictationExpectation.fulfill()
        }
        refiner.refine("Hello, this is a test.", force: true) { result in
            XCTAssertEqual(try? result.get(), "settings refined")
            settingsExpectation.fulfill()
        }

        XCTAssertEqual(capturedRequests.count, 2)
        XCTAssertEqual(capturedRequests[0].task.cancelCount, 0)
        XCTAssertEqual(capturedRequests[1].task.cancelCount, 0)

        capturedRequests[0].completion(
            Self.successData("dictation refined"),
            HTTPURLResponse(url: capturedRequests[0].request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
            nil
        )
        capturedRequests[1].completion(
            Self.successData("settings refined"),
            HTTPURLResponse(url: capturedRequests[1].request.url!, statusCode: 200, httpVersion: nil, headerFields: nil),
            nil
        )

        wait(for: [dictationExpectation, settingsExpectation], timeout: 1)
    }

    func testHTTP401ErrorIncludesStatusAndMessageWithoutLeakingAuthorization() throws {
        let (refiner, recorder, store, defaults) = try makeCapturingRefiner()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        }
        try refiner.updateAPIKey("sk-test-secret")

        let expectation = expectation(description: "401 delivered")
        refiner.refine("filtered text", force: true) { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected HTTP failure, got \(result)")
            }
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("401 Unauthorized"))
            XCTAssertTrue(message.contains("Invalid API key"))
            XCTAssertTrue(message.contains("check API key"))
            XCTAssertFalse(message.contains("sk-test-secret"))
            XCTAssertFalse(message.contains("Bearer"))
            expectation.fulfill()
        }

        let captured = try XCTUnwrap(recorder.capturedRequests.first)
        captured.completion(
            Self.errorData(message: "Invalid API key"),
            Self.httpResponse(for: captured, statusCode: 401),
            nil
        )

        wait(for: [expectation], timeout: 1)
    }

    func testHTTP404ErrorSuggestsModelOrBaseURL() throws {
        let (refiner, recorder, store, defaults) = try makeCapturingRefiner()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        }

        let expectation = expectation(description: "404 delivered")
        refiner.refine("filtered text", force: true) { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected HTTP failure, got \(result)")
            }
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("404 Not Found"))
            XCTAssertTrue(message.contains("check model or API base URL"))
            expectation.fulfill()
        }

        let captured = try XCTUnwrap(recorder.capturedRequests.first)
        captured.completion(
            Self.errorData(message: "model not found"),
            Self.httpResponse(for: captured, statusCode: 404),
            nil
        )

        wait(for: [expectation], timeout: 1)
    }

    func testHTTP429ErrorSuggestsRetryLater() throws {
        let (refiner, recorder, store, defaults) = try makeCapturingRefiner()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        }

        let expectation = expectation(description: "429 delivered")
        refiner.refine("filtered text", force: true) { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected HTTP failure, got \(result)")
            }
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("429 Rate Limited"))
            XCTAssertTrue(message.contains("try later"))
            expectation.fulfill()
        }

        let captured = try XCTUnwrap(recorder.capturedRequests.first)
        captured.completion(
            Self.errorData(message: "too many requests"),
            Self.httpResponse(for: captured, statusCode: 429),
            nil
        )

        wait(for: [expectation], timeout: 1)
    }

    func testMalformedSuccessBodyReportsInvalidResponse() throws {
        let (refiner, recorder, store, defaults) = try makeCapturingRefiner()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        }

        let expectation = expectation(description: "invalid response delivered")
        refiner.refine("filtered text", force: true) { result in
            guard case .failure(let error as LLMRefiner.RefinerError) = result else {
                return XCTFail("Expected invalid response, got \(result)")
            }
            XCTAssertEqual(error, .invalidResponse)
            expectation.fulfill()
        }

        let captured = try XCTUnwrap(recorder.capturedRequests.first)
        captured.completion(
            Self.jsonData(["choices": []]),
            Self.httpResponse(for: captured, statusCode: 200),
            nil
        )

        wait(for: [expectation], timeout: 1)
    }

    func testSuccessResponseReturnsTrimmedContent() throws {
        let (refiner, recorder, store, defaults) = try makeCapturingRefiner()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        }

        let expectation = expectation(description: "success delivered")
        refiner.refine("filtered text", force: true) { result in
            XCTAssertEqual(try? result.get(), "refined text")
            expectation.fulfill()
        }

        let captured = try XCTUnwrap(recorder.capturedRequests.first)
        captured.completion(
            Self.successData("  refined text\n"),
            Self.httpResponse(for: captured, statusCode: 200),
            nil
        )

        wait(for: [expectation], timeout: 1)
    }

    func testInvalidPersistedBaseURLFallsBackToDefaultAndIsCleared() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("http://api.example.com/v1", forKey: "llmAPIBaseURL")

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        XCTAssertEqual(refiner.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertNil(defaults.object(forKey: "llmAPIBaseURL"))
    }

    func testSettingInvalidBaseURLClearsStoredValue() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in }
        )

        refiner.apiBaseURL = "http://api.example.com/v1"

        XCTAssertEqual(refiner.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertNil(defaults.object(forKey: "llmAPIBaseURL"))
    }

    func testTransientConfigurationRequestDoesNotPollutePersistedSettings() throws {
        let (refiner, recorder, store, defaults) = try makeCapturingRefiner()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: defaultsSuiteName(defaults))
        }

        try refiner.updateAPIKey("persisted-key")
        refiner.apiBaseURL = "https://persisted.example/v1"
        refiner.model = "persisted-model"

        let configuration = try LLMRequestConfiguration.validated(
            apiBaseURL: "https://transient.example/v1",
            apiKey: "transient-key",
            model: "transient-model"
        )

        refiner.refine("test connection", configuration: configuration, mode: .promptBuilder) { _ in }

        let captured = try XCTUnwrap(recorder.capturedRequests.first)
        XCTAssertEqual(captured.request.url?.absoluteString, "https://transient.example/v1/chat/completions")
        XCTAssertEqual(captured.request.value(forHTTPHeaderField: "Authorization"), "Bearer transient-key")

        let body = try Self.requestJSONBody(captured.request)
        XCTAssertEqual(body["model"] as? String, "transient-model")
        XCTAssertEqual(body["temperature"] as? Double, LLMRefinementMode.promptBuilder.temperature)

        XCTAssertEqual(refiner.apiBaseURL, "https://persisted.example/v1")
        XCTAssertEqual(refiner.apiKey, "persisted-key")
        XCTAssertEqual(refiner.model, "persisted-model")
        XCTAssertEqual(defaults.string(forKey: "llmAPIBaseURL"), "https://persisted.example/v1")
        XCTAssertEqual(defaults.string(forKey: "llmModel"), "persisted-model")
        XCTAssertEqual(try store.read(), "persisted-key")
    }

    func testInvalidTransientConfigurationDoesNotCreateRequestOrPollutePersistedSettings() throws {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        let recorder = RequestRecorder()
        defer {
            try? store.delete()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in },
            requestPerformer: recorder.perform
        )

        let expectation = expectation(description: "validation error delivered")
        let request = refiner.refine("test connection", force: true) { result in
            switch result {
            case .success(let text):
                XCTFail("Expected validation failure, got \(text)")
            case .failure(let error):
                XCTAssertEqual(error.localizedDescription, "API key is empty")
            }
            expectation.fulfill()
        }

        XCTAssertNil(request)
        XCTAssertTrue(recorder.capturedRequests.isEmpty)
        XCTAssertEqual(refiner.apiKey, "")
        XCTAssertEqual(refiner.apiBaseURL, LLMRefiner.defaultAPIBaseURL)
        XCTAssertEqual(refiner.model, LLMRefiner.defaultModel)
        XCTAssertNil(defaults.object(forKey: "llmAPIBaseURL"))
        XCTAssertNil(defaults.object(forKey: "llmModel"))
        XCTAssertNil(try store.read())
        wait(for: [expectation], timeout: 1)
    }

    func testChatCompletionsURLRequiresHTTPURLWithHost() {
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: " https://api.openai.com/v1/ ")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "http://localhost:1234/v1")?.absoluteString,
            "http://localhost:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "http://127.0.0.1:1234/v1//")?.absoluteString,
            "http://127.0.0.1:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "http://[::1]:1234/v1")?.absoluteString,
            "http://[::1]:1234/v1/chat/completions"
        )
        XCTAssertEqual(
            LLMRefiner.chatCompletionsURL(from: "https://api.openai.com/v1/chat/completions")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "http://api.example.com/v1"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "localhost:1234/v1"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "file:///tmp/api"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "not a url"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "https://api.openai.com/v1?debug=true"))
        XCTAssertNil(LLMRefiner.chatCompletionsURL(from: "https://user:pass@api.openai.com/v1"))
    }

    private static func requestJSONBody(
        _ request: URLRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody, "Expected request body", file: file, line: line)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Expected JSON object body",
            file: file,
            line: line
        )
    }

    private static func successData(_ content: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        let json: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "content": content,
                    ],
                ],
            ],
        ]
        do {
            return try JSONSerialization.data(withJSONObject: json)
        } catch {
            XCTFail("Failed to encode test response JSON: \(error)", file: file, line: line)
            return Data()
        }
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

    private static func httpResponse(for request: CapturedRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func makeCapturingRefiner() throws -> (
        refiner: LLMRefiner,
        recorder: RequestRecorder,
        store: KeychainStore,
        defaults: UserDefaults
    ) {
        let suiteName = "LLMRefinerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "testSuiteName")
        let store = KeychainStore(
            service: "app.voiceinput.VoiceInput.tests.\(UUID().uuidString)",
            account: "llm-api-key"
        )
        let recorder = RequestRecorder()
        let refiner = LLMRefiner(
            userDefaults: defaults,
            apiKeyStore: store,
            logHandler: { _ in },
            requestPerformer: recorder.perform
        )
        try refiner.updateAPIKey("test-key")
        return (refiner, recorder, store, defaults)
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "testSuiteName") ?? ""
    }
}
