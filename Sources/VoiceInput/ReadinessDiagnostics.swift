import Foundation

enum ReadinessState: Equatable {
    case ready
    case attention
    case optional
}

enum ReadinessAction: Equatable {
    case openAccessibilitySettings
    case openInputMonitoringSettings
    case openMicrophoneSettings
    case openSpeechSettings
    case openLLMSettings
    case openDictionary
}

struct ReadinessItem: Equatable {
    let title: String
    let state: ReadinessState
    let detail: String
    let action: ReadinessAction?

    var needsAttention: Bool {
        state == .attention
    }
}

struct ReadinessDiagnostics: Equatable {
    let items: [ReadinessItem]

    var isReady: Bool {
        !items.contains(where: \.needsAttention)
    }

    var title: String {
        isReady ? "VoiceInput is ready" : "VoiceInput needs attention"
    }

    var menuTitle: String {
        isReady ? "Readiness: Ready" : "Readiness: Needs Attention"
    }

    var primaryAction: ReadinessAction? {
        items.first { $0.needsAttention && $0.action != nil }?.action
    }

    static func capture() -> ReadinessDiagnostics {
        make(
            permissionDiagnostics: PermissionDiagnostics.capture(),
            isLLMConfigured: LLMRefiner.shared.isConfigured,
            dictionaryLoadIssue: DictionaryFilter.shared.lastLoadIssue,
            userDictionaryEntryCount: DictionaryFilter.shared.userMap.count
        )
    }

    static func make(
        permissionDiagnostics: PermissionDiagnostics,
        isLLMConfigured: Bool,
        dictionaryLoadIssue: String?,
        userDictionaryEntryCount: Int
    ) -> ReadinessDiagnostics {
        var items: [ReadinessItem] = [
            item(
                from: permissionDiagnostics.accessibility,
                action: .openAccessibilitySettings
            ),
            item(
                from: permissionDiagnostics.inputMonitoring,
                action: .openInputMonitoringSettings
            ),
            item(
                from: permissionDiagnostics.microphone,
                action: .openMicrophoneSettings
            ),
            item(
                from: permissionDiagnostics.speechRecognition,
                action: .openSpeechSettings
            ),
        ]

        items.append(ReadinessItem(
            title: "LLM Refinement",
            state: isLLMConfigured ? .ready : .optional,
            detail: isLLMConfigured ? "Ready" : "Optional: add an API key for LLM refinement",
            action: isLLMConfigured ? nil : .openLLMSettings
        ))

        if let dictionaryLoadIssue, !dictionaryLoadIssue.isEmpty {
            items.append(ReadinessItem(
                title: "Dictionary",
                state: .attention,
                detail: dictionaryLoadIssue,
                action: .openDictionary
            ))
        } else {
            let detail = userDictionaryEntryCount > 0
                ? "Loaded \(userDictionaryEntryCount) user rules"
                : "Built-in dictionary ready"
            items.append(ReadinessItem(
                title: "Dictionary",
                state: .ready,
                detail: detail,
                action: .openDictionary
            ))
        }

        return ReadinessDiagnostics(items: items)
    }

    private static func item(from diagnostic: PermissionDiagnostic, action: ReadinessAction) -> ReadinessItem {
        let state: ReadinessState = diagnostic.isReady ? .ready : .attention
        return ReadinessItem(
            title: diagnostic.name,
            state: state,
            detail: diagnostic.state.displayText,
            action: diagnostic.isReady ? nil : action
        )
    }
}
