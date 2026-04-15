import Foundation
import os.log

private let logger = Logger(subsystem: "app.voiceinput.VoiceInput", category: "LLMRefiner")
private let llmAPIKeyDefaultsKey = "llmAPIKey"
private let llmAPIBaseURLDefaultsKey = "llmAPIBaseURL"
private let llmModelDefaultsKey = "llmModel"

private func logToFile(_ message: String) {
    let msg = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/VoiceInput.log")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(msg.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logURL.path, contents: msg.data(using: .utf8))
    }
}

final class LLMRefiner {
    static let shared = LLMRefiner()
    static let defaultAPIBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    private let userDefaults: UserDefaults
    private let apiKeyStore: KeychainStore
    private let logHandler: (String) -> Void

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: "llmEnabled") }
        set { userDefaults.set(newValue, forKey: "llmEnabled") }
    }

    var apiBaseURL: String {
        get { normalizedSetting(userDefaults.string(forKey: llmAPIBaseURLDefaultsKey), fallback: Self.defaultAPIBaseURL) }
        set { persistSetting(newValue, key: llmAPIBaseURLDefaultsKey) }
    }

    var apiKey: String {
        migrateLegacyAPIKeyIfNeeded()
        return (try? apiKeyStore.read()) ?? ""
    }

    var model: String {
        get { normalizedSetting(userDefaults.string(forKey: llmModelDefaultsKey), fallback: Self.defaultModel) }
        set { persistSetting(newValue, key: llmModelDefaultsKey) }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    private var currentTask: URLSessionDataTask?

    private let systemPrompt = """
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

    init(
        userDefaults: UserDefaults = .standard,
        apiKeyStore: KeychainStore = KeychainStore(
            service: "app.voiceinput.VoiceInput",
            account: "llm-api-key"
        ),
        logHandler: @escaping (String) -> Void = logToFile
    ) {
        self.userDefaults = userDefaults
        self.apiKeyStore = apiKeyStore
        self.logHandler = logHandler
    }

    func refine(_ text: String, force: Bool = false, completion: @escaping (Result<String, Error>) -> Void) {
        guard force || (isEnabled && isConfigured) else {
            completion(.success(text))
            return
        }

        let baseURL = apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            completion(.failure(RefinerError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
        ]

        logHandler("Request: \(url.absoluteString) model=\(model)")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        currentTask = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                self.logHandler("Network error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                self.logHandler("No data in response")
                DispatchQueue.main.async { completion(.failure(RefinerError.invalidResponse)) }
                return
            }
            self.logHandler("Response bytes: \(data.count)")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String
            else {
                self.logHandler("Failed to parse response")
                DispatchQueue.main.async { completion(.failure(RefinerError.invalidResponse)) }
                return
            }
            let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
            self.logHandler(
                "Refined changed=\(refined != text) input_chars=\(text.count) output_chars=\(refined.count)"
            )
            DispatchQueue.main.async { completion(.success(refined)) }
        }
        currentTask?.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
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

    enum RefinerError: LocalizedError {
        case invalidURL
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API base URL"
            case .invalidResponse: return "Invalid response from LLM API"
            }
        }
    }
}
