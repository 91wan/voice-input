import Foundation

enum LLMRefinementError: LocalizedError, Equatable {
    case invalidURL
    case transport(String)
    case httpStatus(Int, String?)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API base URL"
        case .transport(let message):
            return "Network error: \(message)"
        case .httpStatus(let statusCode, let message):
            return Self.httpStatusDescription(statusCode: statusCode, message: message)
        case .invalidResponse:
            return "Invalid response from LLM API"
        case .cancelled:
            return "LLM request was cancelled"
        }
    }

    var logSummary: String {
        switch self {
        case .invalidURL:
            return "invalid_url"
        case .transport:
            return "transport"
        case .httpStatus(let statusCode, _):
            return Self.httpStatusLogSummary(statusCode)
        case .invalidResponse:
            return "invalid_response"
        case .cancelled:
            return "cancelled"
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

    private static func httpStatusLogSummary(_ statusCode: Int) -> String {
        switch statusCode {
        case 401, 403:
            return "http_status=\(statusCode) hint=check_api_key"
        case 404:
            return "http_status=404 hint=check_model_or_api_base_url"
        case 429:
            return "http_status=429 hint=try_later"
        case 500...599:
            return "http_status=\(statusCode) hint=provider_status"
        default:
            return "http_status=\(statusCode)"
        }
    }
}
