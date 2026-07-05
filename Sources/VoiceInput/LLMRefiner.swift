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

struct LLMRequestConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    let apiBaseURL: String
    let model: String
    private let apiKey: String

    var hasAPIKey: Bool { !apiKey.isEmpty }

    var description: String { redactedDescription }

    var debugDescription: String { redactedDescription }

    private var redactedDescription: String {
        "LLMRequestConfiguration(apiBaseURL: \(apiBaseURL), model: \(model), apiKey: [redacted])"
    }

    private init(apiBaseURL: String, apiKey: String, model: String) {
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.model = model
    }

    static func validated(
        apiBaseURL: String,
        apiKey: String,
        model: String
    ) throws -> LLMRequestConfiguration {
        let normalizedAPIBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedAPIKey.isEmpty else {
            throw ValidationError.emptyAPIKey
        }

        let requestAPIBaseURL: String
        if normalizedAPIBaseURL.isEmpty {
            requestAPIBaseURL = LLMRefiner.defaultAPIBaseURL
        } else if LLMRefiner.chatCompletionsURL(from: normalizedAPIBaseURL) != nil {
            requestAPIBaseURL = normalizedAPIBaseURL
        } else {
            throw ValidationError.invalidAPIBaseURL
        }

        return LLMRequestConfiguration(
            apiBaseURL: requestAPIBaseURL,
            apiKey: normalizedAPIKey,
            model: normalizedModel.isEmpty ? LLMRefiner.defaultModel : normalizedModel
        )
    }

    func applyAuthorization(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    enum ValidationError: LocalizedError, Equatable {
        case invalidAPIBaseURL
        case emptyAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidAPIBaseURL:
                return "Invalid API base URL. Use a full http(s) base URL, for example https://api.openai.com/v1."
            case .emptyAPIKey:
                return "API key is empty"
            }
        }
    }
}

final class LLMRefiner {
    typealias RequestPerformer = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> LLMNetworkTask

    static let shared = LLMRefiner()
    static let defaultAPIBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

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
            if let error {
                self.logHandler("Network error: \(error.localizedDescription)")
                if (error as? URLError)?.code == .cancelled {
                    requestHandle.complete(.failure(RefinerError.cancelled))
                } else {
                    requestHandle.complete(.failure(RefinerError.transport(error.localizedDescription)))
                }
                return
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let message = data.flatMap(Self.apiErrorMessage(from:))
                self.logHandler("HTTP error: \(httpResponse.statusCode) \(message ?? "no error message")")
                requestHandle.complete(.failure(RefinerError.httpStatus(httpResponse.statusCode, message)))
                return
            }
            guard let data else {
                self.logHandler("No data in response")
                requestHandle.complete(.failure(RefinerError.invalidResponse))
                return
            }
            self.logHandler("Response bytes: \(data.count)")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String
            else {
                self.logHandler("Failed to parse response")
                requestHandle.complete(.failure(RefinerError.invalidResponse))
                return
            }
            let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
            self.logHandler(
                "Refined changed=\(refined != text) input_chars=\(text.count) output_chars=\(refined.count)"
            )
            requestHandle.complete(.success(refined))
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
        var normalized = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        guard
            var components = URLComponents(string: normalized),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty,
            scheme == "https" || isLoopbackHost(host),
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            return nil
        }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        let endpointPath = "/chat/completions"
        if path.lowercased().hasSuffix(endpointPath) {
            components.percentEncodedPath = path
        } else {
            components.percentEncodedPath = "\(path)\(endpointPath)"
        }
        return components.url
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalizedHost == "localhost" || normalizedHost == "127.0.0.1" || normalizedHost == "::1"
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }

        let redacted = redactSensitiveTokens(in: message)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return redacted.isEmpty ? nil : redacted
    }

    private static func redactSensitiveTokens(in message: String) -> String {
        let patterns = [
            #"Bearer\s+[A-Za-z0-9._\-]+"#,
            #"sk-[A-Za-z0-9._\-]+"#,
        ]
        return patterns.reduce(message) { current, pattern in
            current.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
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

    enum RefinerError: LocalizedError, Equatable {
        case invalidURL
        case transport(String)
        case httpStatus(Int, String?)
        case invalidResponse
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API base URL"
            case .transport(let message): return "Network error: \(message)"
            case .httpStatus(let statusCode, let message):
                return Self.httpStatusDescription(statusCode: statusCode, message: message)
            case .invalidResponse: return "Invalid response from LLM API"
            case .cancelled: return "LLM request was cancelled"
            }
        }

        private static func httpStatusDescription(statusCode: Int, message: String?) -> String {
            var parts = ["\(statusCode) \(statusTitle(statusCode))"]
            if let message, !message.isEmpty {
                parts.append(message)
            }
            if let hint = recoveryHint(statusCode) {
                parts.append(hint)
            }
            return parts.joined(separator: " - ")
        }

        private static func statusTitle(_ statusCode: Int) -> String {
            switch statusCode {
            case 400: return "Bad Request"
            case 401: return "Unauthorized"
            case 403: return "Forbidden"
            case 404: return "Not Found"
            case 408: return "Request Timeout"
            case 409: return "Conflict"
            case 422: return "Unprocessable Content"
            case 429: return "Rate Limited"
            case 500: return "Server Error"
            case 502: return "Bad Gateway"
            case 503: return "Service Unavailable"
            case 504: return "Gateway Timeout"
            default: return "HTTP Error"
            }
        }

        private static func recoveryHint(_ statusCode: Int) -> String? {
            switch statusCode {
            case 401, 403:
                return "check API key"
            case 404:
                return "check model or API base URL"
            case 429:
                return "try later"
            case 500...599:
                return "try later or check the API provider status"
            default:
                return nil
            }
        }
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
