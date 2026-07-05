import Foundation
import os.log

private let logger = Logger(subsystem: "app.voiceinput.VoiceInput", category: "LLMRefiner")
private let llmAPIKeyDefaultsKey = "llmAPIKey"
private let llmAPIBaseURLDefaultsKey = "llmAPIBaseURL"
private let llmModelDefaultsKey = "llmModel"
private let llmModeDefaultsKey = "llmMode"

private func logToFile(_ message: String) {
    let msg = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    guard let data = msg.data(using: .utf8) else { return }
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VoiceInput.log")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logURL.path, contents: data)
    }
}

protocol CancellableRequest: AnyObject {
    func cancel()
}

protocol LLMNetworkTask: CancellableRequest {
    func resume()
}

extension URLSessionDataTask: LLMNetworkTask {}

enum LLMRefinementMode: String, CaseIterable, Equatable {
    case precise
    case promptBuilder

    var menuTitle: String {
        switch self {
        case .precise:
            return "Precise Dictation"
        case .promptBuilder:
            return "Prompt Builder"
        }
    }

    var temperature: Double {
        switch self {
        case .precise:
            return 0.3
        case .promptBuilder:
            return 0.2
        }
    }

    var systemPrompt: String {
        switch self {
        case .precise:
            return """
                You are a speech recognition post-processor for Chinese-English mixed technical speech. \
                Dictionary corrections (proper nouns, brand names) have already been applied upstream. \
                Your ONLY job:
                1. Fix Chinese homophones in clear technical context (的/地/得, 分支 vs 分汐, etc.)
                2. Fix broken English words split by the recognizer (e.g. "type script" → "TypeScript")
                3. Add missing sentence-ending punctuation (。or ，) when clearly absent
                Do NOT rephrase, rewrite, translate, add or remove content words, or improve any text.
                Return ONLY the corrected text. No explanations, no markdown.
                If nothing needs fixing, return the input exactly as-is.
                """
        case .promptBuilder:
            return """
                You turn rough speech transcripts into a clear AI prompt for ChatGPT, Claude, Cursor, or similar tools. \
                Treat the transcript as raw material only. \
                Do NOT answer the user's request. Do NOT execute tasks. Do NOT add facts the user did not say. \
                Rewrite only to remove filler words, clarify intent, preserve constraints, and structure the prompt. \
                Return ONLY the prompt text. No explanations, no markdown fence.
                """
        }
    }
}

final class LLMRefiner {
    typealias RequestPerformer = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> LLMNetworkTask
    typealias RefinerError = LLMRefinementError

    static let shared = LLMRefiner()
    static let defaultAPIBaseURL = LLMRequestConfiguration.defaultAPIBaseURL
    static let defaultModel = LLMRequestConfiguration.defaultModel

    private let userDefaults: UserDefaults
    private let apiKeyStore: KeychainStore
    private let logHandler: (String) -> Void
    private let requestPerformer: RequestPerformer
    private let requestLock = NSLock()
    private var activeRequests: [LLMRefinementRequest] = []

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: "llmEnabled") }
        set { userDefaults.set(newValue, forKey: "llmEnabled") }
    }

    var apiBaseURL: String {
        get { normalizedAPIBaseURLSetting(userDefaults.string(forKey: llmAPIBaseURLDefaultsKey)) }
        set { persistAPIBaseURLSetting(newValue) }
    }

    var apiKey: String {
        migrateLegacyAPIKeyIfNeeded()
        do {
            return try apiKeyStore.read() ?? ""
        } catch {
            logHandler("Failed to read LLM API key from Keychain: \(error.localizedDescription)")
            return ""
        }
    }

    var model: String {
        get { normalizedSetting(userDefaults.string(forKey: llmModelDefaultsKey), fallback: Self.defaultModel) }
        set { persistSetting(newValue, key: llmModelDefaultsKey) }
    }

    var mode: LLMRefinementMode {
        get { normalizedMode(userDefaults.string(forKey: llmModeDefaultsKey)) }
        set { persistMode(newValue) }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    init(
        userDefaults: UserDefaults = .standard,
        apiKeyStore: KeychainStore = KeychainStore(
            service: "app.voiceinput.VoiceInput",
            account: "llm-api-key"
        ),
        logHandler: @escaping (String) -> Void = logToFile,
        requestPerformer: @escaping RequestPerformer = { request, completion in
            URLSession.shared.dataTask(with: request, completionHandler: completion)
        }
    ) {
        self.userDefaults = userDefaults
        self.apiKeyStore = apiKeyStore
        self.logHandler = logHandler
        self.requestPerformer = requestPerformer
    }

    @discardableResult
    func refine(
        _ text: String,
        mode modeOverride: LLMRefinementMode? = nil,
        force: Bool = false,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> CancellableRequest? {
        guard force || (isEnabled && isConfigured) else {
            completion(.success(text))
            return nil
        }

        let configuration: LLMRequestConfiguration
        do {
            configuration = try LLMRequestConfiguration.validated(
                apiBaseURL: apiBaseURL,
                apiKey: apiKey,
                model: model
            )
        } catch {
            completion(.failure(error))
            return nil
        }

        return refine(
            text,
            configuration: configuration,
            mode: modeOverride,
            completion: completion
        )
    }

    @discardableResult
    func refine(
        _ text: String,
        configuration: LLMRequestConfiguration,
        mode modeOverride: LLMRefinementMode? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> CancellableRequest? {
        guard let url = Self.chatCompletionsURL(from: configuration.apiBaseURL) else {
            completion(.failure(RefinerError.invalidURL))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        configuration.applyAuthorization(to: &request)
        request.timeoutInterval = 10

        let requestMode = modeOverride ?? mode
        let body = chatRequestBody(for: text, mode: requestMode, model: configuration.model)

        logHandler("Request: \(url.absoluteString) model=\(configuration.model) mode=\(requestMode.rawValue)")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let requestHandle = LLMRefinementRequest(completion: completion) { [weak self] request in
            self?.removeActiveRequest(request)
        }
        addActiveRequest(requestHandle)

        let task = requestPerformer(request) { data, response, error in
            switch LLMAPIResponseParser.parse(
                data: data,
                response: response,
                error: error,
                originalText: text
            ) {
            case .success(let refined):
                self.logHandler(
                    "Refined changed=\(refined != text) input_chars=\(text.count) output_chars=\(refined.count)"
                )
                requestHandle.complete(.success(refined))
            case .failure(let error):
                self.logHandler("LLM response failed: \(error.localizedDescription)")
                requestHandle.complete(.failure(error))
            }
        }
        if requestHandle.setTask(task) {
            task.resume()
        }
        return requestHandle
    }

    func chatRequestBody(for text: String, mode modeOverride: LLMRefinementMode? = nil) -> [String: Any] {
        let currentMode = modeOverride ?? mode
        return chatRequestBody(for: text, mode: currentMode, model: model)
    }

    private func chatRequestBody(for text: String, mode currentMode: LLMRefinementMode, model: String) -> [String: Any] {
        return [
            "model": model,
            "messages": [
                ["role": "system", "content": currentMode.systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": currentMode.temperature,
        ]
    }

    func cancel() {
        let requests: [LLMRefinementRequest]
        requestLock.lock()
        requests = activeRequests
        requestLock.unlock()

        for request in requests {
            request.cancel()
        }
    }

    func updateAPIKey(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.removeObject(forKey: llmAPIKeyDefaultsKey)
        if normalized.isEmpty {
            try apiKeyStore.delete()
        } else {
            try apiKeyStore.write(normalized)
        }
    }

    private func migrateLegacyAPIKeyIfNeeded() {
        let existing = try? apiKeyStore.read()
        if let existing, !existing.isEmpty {
            userDefaults.removeObject(forKey: llmAPIKeyDefaultsKey)
            return
        }

        guard let legacy = userDefaults.string(forKey: llmAPIKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        else {
            userDefaults.removeObject(forKey: llmAPIKeyDefaultsKey)
            return
        }

        do {
            try apiKeyStore.write(legacy)
            userDefaults.removeObject(forKey: llmAPIKeyDefaultsKey)
            logHandler("Migrated LLM API key from UserDefaults to Keychain")
        } catch {
            logger.error("Failed to migrate LLM API key to Keychain: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func normalizedSetting(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private func persistSetting(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(trimmed, forKey: key)
        }
    }

    private func normalizedMode(_ value: String?) -> LLMRefinementMode {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            userDefaults.removeObject(forKey: llmModeDefaultsKey)
            return .precise
        }

        guard let mode = LLMRefinementMode(rawValue: rawValue) else {
            userDefaults.removeObject(forKey: llmModeDefaultsKey)
            return .precise
        }

        return mode
    }

    private func persistMode(_ mode: LLMRefinementMode) {
        if mode == .precise {
            userDefaults.removeObject(forKey: llmModeDefaultsKey)
        } else {
            userDefaults.set(mode.rawValue, forKey: llmModeDefaultsKey)
        }
    }

    private func normalizedAPIBaseURLSetting(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            userDefaults.removeObject(forKey: llmAPIBaseURLDefaultsKey)
            return Self.defaultAPIBaseURL
        }

        guard Self.chatCompletionsURL(from: trimmed) != nil else {
            userDefaults.removeObject(forKey: llmAPIBaseURLDefaultsKey)
            return Self.defaultAPIBaseURL
        }

        return trimmed
    }

    private func persistAPIBaseURLSetting(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.chatCompletionsURL(from: trimmed) != nil else {
            userDefaults.removeObject(forKey: llmAPIBaseURLDefaultsKey)
            return
        }

        userDefaults.set(trimmed, forKey: llmAPIBaseURLDefaultsKey)
    }

    static func chatCompletionsURL(from baseURLString: String) -> URL? {
        LLMRequestConfiguration.chatCompletionsURL(from: baseURLString)
    }

    private func addActiveRequest(_ request: LLMRefinementRequest) {
        requestLock.lock()
        activeRequests.append(request)
        requestLock.unlock()
    }

    private func removeActiveRequest(_ request: LLMRefinementRequest) {
        requestLock.lock()
        activeRequests.removeAll { $0 === request }
        requestLock.unlock()
    }

}

private final class LLMRefinementRequest: CancellableRequest {
    private let lock = NSLock()
    private var completion: ((Result<String, Error>) -> Void)?
    private var task: LLMNetworkTask?
    private let cleanup: (LLMRefinementRequest) -> Void

    init(
        completion: @escaping (Result<String, Error>) -> Void,
        cleanup: @escaping (LLMRefinementRequest) -> Void
    ) {
        self.completion = completion
        self.cleanup = cleanup
    }

    func setTask(_ task: LLMNetworkTask) -> Bool {
        lock.lock()
        guard completion != nil else {
            lock.unlock()
            task.cancel()
            return false
        }
        self.task = task
        lock.unlock()
        return true
    }

    func cancel() {
        lock.lock()
        let taskToCancel = task
        lock.unlock()

        taskToCancel?.cancel()
        complete(.failure(LLMRefiner.RefinerError.cancelled))
    }

    func complete(_ result: Result<String, Error>) {
        lock.lock()
        guard let completion else {
            lock.unlock()
            return
        }
        self.completion = nil
        task = nil
        lock.unlock()

        cleanup(self)
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
