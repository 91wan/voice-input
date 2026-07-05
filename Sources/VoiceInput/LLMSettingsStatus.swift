import Foundation

enum LLMSettingsTestState: Equatable {
    case notRun
    case testing
    case succeeded(String)
    case failed(String)
}

struct LLMSettingsDraftChangeOutcome: Equatable {
    let shouldCancelActiveTest: Bool
    let testState: LLMSettingsTestState
    let message: String
    let success: Bool?
}

enum LLMSettingsDraftChangePolicy {
    static func outcome(isLoadingSettings: Bool) -> LLMSettingsDraftChangeOutcome? {
        guard !isLoadingSettings else { return nil }

        return LLMSettingsDraftChangeOutcome(
            shouldCancelActiveTest: true,
            testState: .notRun,
            message: "Unsaved changes. Test uses current fields once; Save persists them.",
            success: nil
        )
    }
}

struct LLMSettingsStatus: Equatable {
    let displayText: String
    let isReady: Bool

    static func make(
        isConfigured: Bool,
        apiBaseURL: String,
        model: String,
        mode: LLMRefinementMode,
        testState: LLMSettingsTestState,
        isTransientConfiguration: Bool = false
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
            if isTransientConfiguration {
                return LLMSettingsStatus(displayText: "Testing unsaved settings: \(context)", isReady: false)
            }
            return LLMSettingsStatus(displayText: "Testing: \(context)", isReady: false)
        case .succeeded(let sample):
            if isTransientConfiguration {
                return LLMSettingsStatus(displayText: "Test OK (not saved): \(sample)", isReady: true)
            }
            return LLMSettingsStatus(displayText: "Test OK: \(sample)", isReady: true)
        case .failed(let message):
            if isTransientConfiguration {
                return LLMSettingsStatus(displayText: "Test failed (not saved): \(message) · \(context)", isReady: false)
            }
            return LLMSettingsStatus(displayText: "Test failed: \(message) · \(context)", isReady: false)
        }
    }
}
