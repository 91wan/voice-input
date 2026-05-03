import Foundation

enum LLMSettingsTestState: Equatable {
    case notRun
    case testing
    case succeeded(String)
    case failed(String)
}

struct LLMSettingsStatus: Equatable {
    let displayText: String
    let isReady: Bool

    static func make(
        isConfigured: Bool,
        apiBaseURL: String,
        model: String,
        mode: LLMRefinementMode,
        testState: LLMSettingsTestState
    ) -> LLMSettingsStatus {
        guard isConfigured else {
            return LLMSettingsStatus(
                displayText: "Not configured: add an API key to enable LLM refinement.",
                isReady: false
            )
        }

        let context = "\(apiBaseURL) · \(model) · \(mode.menuTitle)"
        switch testState {
        case .notRun:
            return LLMSettingsStatus(displayText: "Ready: \(context)", isReady: true)
        case .testing:
            return LLMSettingsStatus(displayText: "Testing: \(context)", isReady: false)
        case .succeeded(let sample):
            return LLMSettingsStatus(displayText: "Test OK: \(sample)", isReady: true)
        case .failed(let message):
            return LLMSettingsStatus(displayText: "Test failed: \(message) · \(context)", isReady: false)
        }
    }
}
