import Foundation

struct LLMRequestConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    static let defaultAPIBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    let apiBaseURL: String
    let chatCompletionsURL: URL
    let model: String
    private let apiKey: String

    var hasAPIKey: Bool { !apiKey.isEmpty }

    var description: String { redactedDescription }

    var debugDescription: String { redactedDescription }

    private var redactedDescription: String {
        "LLMRequestConfiguration(apiBaseURL: \(apiBaseURL), model: \(model), apiKey: [redacted])"
    }

    private init(apiBaseURL: String, chatCompletionsURL: URL, apiKey: String, model: String) {
        self.apiBaseURL = apiBaseURL
        self.chatCompletionsURL = chatCompletionsURL
        self.apiKey = apiKey
        self.model = model
    }

    static func validated(
        apiBaseURL: String,
        apiKey: String,
        model: String
    ) throws -> LLMRequestConfiguration {
        try validationResult(apiBaseURL: apiBaseURL, apiKey: apiKey, model: model).get()
    }

    static func validationResult(
        apiBaseURL: String,
        apiKey: String,
        model: String
    ) -> Result<LLMRequestConfiguration, ValidationError> {
        let normalizedAPIBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedAPIKey.isEmpty else {
            return .failure(.emptyAPIKey)
        }

        let requestAPIBaseURL = normalizedAPIBaseURL.isEmpty ? defaultAPIBaseURL : normalizedAPIBaseURL
        guard let endpoint = chatCompletionsURL(from: requestAPIBaseURL) else {
            return .failure(.invalidAPIBaseURL)
        }

        return .success(LLMRequestConfiguration(
            apiBaseURL: requestAPIBaseURL,
            chatCompletionsURL: endpoint,
            apiKey: normalizedAPIKey,
            model: normalizedModel.isEmpty ? defaultModel : normalizedModel
        ))
    }

    func applyAuthorization(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
