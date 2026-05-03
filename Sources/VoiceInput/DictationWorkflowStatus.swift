import Foundation

struct DictationWorkflowStatus: Equatable {
    let menuSummary: String
    let defaultShortcutTitle: String
    let promptBuilderShortcutTitle: String
    let readinessDetail: String
    let isLLMAvailable: Bool

    static func make(
        defaultMode: LLMRefinementMode,
        isLLMEnabled: Bool,
        isLLMConfigured: Bool
    ) -> DictationWorkflowStatus {
        let isLLMAvailable = isLLMEnabled && isLLMConfigured
        let readinessDetail: String
        if isLLMAvailable {
            readinessDetail = "Fn uses \(defaultMode.menuTitle). Option + Fn uses Prompt Builder once. LLM refinement is ready."
        } else {
            readinessDetail = "Fn uses \(defaultMode.menuTitle). Option + Fn uses Prompt Builder once. LLM unavailable: ordinary Fn still uses Apple Speech + DictionaryFilter without extra errors."
        }

        return DictationWorkflowStatus(
            menuSummary: isLLMAvailable
                ? "Dictation: Fn uses \(defaultMode.menuTitle)"
                : "Dictation: Fn uses Apple Speech + DictionaryFilter",
            defaultShortcutTitle: isLLMAvailable
                ? "Fn: \(defaultMode.menuTitle) (default)"
                : "Fn: \(defaultMode.menuTitle) (default; LLM unavailable)",
            promptBuilderShortcutTitle: "Option + Fn: Prompt Builder (one shot)",
            readinessDetail: readinessDetail,
            isLLMAvailable: isLLMAvailable
        )
    }
}
