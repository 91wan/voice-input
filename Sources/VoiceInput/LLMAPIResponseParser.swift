import Foundation

struct LLMAPIResponseParser {
    static func parse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<String, LLMRefinementError> {
        if let error {
            if (error as? URLError)?.code == .cancelled {
                return .failure(.cancelled)
            }
            return .failure(.transport(redactSensitiveTokens(in: error.localizedDescription)))
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            return .failure(.httpStatus(httpResponse.statusCode, data.flatMap(apiErrorMessage(from:))))
        }

        guard let data else {
            return .failure(.invalidResponse)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return .failure(.invalidResponse)
        }

        return .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
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
}
