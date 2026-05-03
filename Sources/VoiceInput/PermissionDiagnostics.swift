import ApplicationServices
import AVFoundation
import Foundation
import IOKit.hidsystem
import Speech

enum PermissionDiagnosticState: Equatable {
    case ready
    case missing
    case notDetermined
    case unknown

    var displayText: String {
        switch self {
        case .ready:
            return "Ready"
        case .missing:
            return "Missing"
        case .notDetermined:
            return "Not Determined"
        case .unknown:
            return "Unknown"
        }
    }
}

enum InputMonitoringAccess: Equatable {
    case granted
    case denied
    case unknown

    var diagnosticState: PermissionDiagnosticState {
        switch self {
        case .granted:
            return .ready
        case .denied:
            return .missing
        case .unknown:
            return .unknown
        }
    }

    static func capture() -> InputMonitoringAccess {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .unknown
        }
    }
}

struct PermissionDiagnostic: Equatable {
    let name: String
    let state: PermissionDiagnosticState
    let settingsURL: URL?

    var isReady: Bool {
        state == .ready
    }

    var line: String {
        "\(name): \(state.displayText)"
    }
}

struct PermissionRecoveryGuidance: Equatable {
    let title: String
    let failurePoint: String
    let nextStep: String
    let reopenInstruction: String
    let detail: String
    let primarySettingsURL: URL?
    let requiresReopenOnly: Bool

    static func make(
        diagnostics: PermissionDiagnostics,
        eventMonitorStartFailed: Bool
    ) -> PermissionRecoveryGuidance {
        if !diagnostics.accessibility.isReady {
            return accessibilityGuidance(settingsURL: diagnostics.accessibility.settingsURL)
        }

        if !diagnostics.inputMonitoring.isReady {
            return inputMonitoringGuidance(settingsURL: diagnostics.inputMonitoring.settingsURL)
        }

        if !diagnostics.microphone.isReady {
            return microphoneGuidance(settingsURL: diagnostics.microphone.settingsURL)
        }

        if !diagnostics.speechRecognition.isReady {
            return speechRecognitionGuidance(settingsURL: diagnostics.speechRecognition.settingsURL)
        }

        if eventMonitorStartFailed {
            return make(
                title: "Reopen VoiceInput Required",
                failurePoint: "Input monitor is not active even though permissions appear enabled.",
                nextStep: "Quit and reopen VoiceInput. If it still fails, remove VoiceInput from Accessibility and Input Monitoring, then add /Applications/VoiceInput.app again.",
                reopenInstruction: "Required.",
                primarySettingsURL: nil,
                requiresReopenOnly: true
            )
        }

        return make(
            title: "Permissions Ready",
            failurePoint: "No permission failure detected.",
            nextStep: "No action required.",
            reopenInstruction: "Not required.",
            primarySettingsURL: nil,
            requiresReopenOnly: false
        )
    }

    static func make(issue: SpeechPermissionIssue) -> PermissionRecoveryGuidance {
        switch issue {
        case .microphoneDenied:
            return microphoneGuidance(settingsURL: issue.settingsURL)
        case .speechRecognitionDenied:
            return speechRecognitionGuidance(settingsURL: issue.settingsURL)
        case .speechRecognitionNotDetermined:
            return make(
                title: "Approve Speech Recognition Permission",
                failurePoint: "Speech Recognition permission has not been decided yet.",
                nextStep: "Start dictation again and approve the system permission prompt.",
                reopenInstruction: "Reopen VoiceInput if the status does not refresh.",
                primarySettingsURL: nil,
                requiresReopenOnly: false
            )
        case .unknownAuthorizationStatus:
            return make(
                title: "Check Speech Recognition Permission",
                failurePoint: "Speech Recognition permission is in an unknown state.",
                nextStep: "Open System Settings -> Privacy & Security -> Speech Recognition and verify VoiceInput.",
                reopenInstruction: "Reopen VoiceInput if the status does not refresh.",
                primarySettingsURL: SpeechPermissionIssue.speechRecognitionDenied.settingsURL,
                requiresReopenOnly: false
            )
        }
    }

    static func make(for diagnostic: PermissionDiagnostic) -> PermissionRecoveryGuidance? {
        guard !diagnostic.isReady else { return nil }

        switch diagnostic.name {
        case "Accessibility":
            return accessibilityGuidance(settingsURL: diagnostic.settingsURL)
        case "Input Monitoring":
            return inputMonitoringGuidance(settingsURL: diagnostic.settingsURL)
        case "Microphone":
            return microphoneGuidance(settingsURL: diagnostic.settingsURL)
        case "Speech Recognition":
            return speechRecognitionGuidance(settingsURL: diagnostic.settingsURL)
        default:
            return nil
        }
    }

    private static func accessibilityGuidance(settingsURL: URL?) -> PermissionRecoveryGuidance {
        make(
            title: "Fix Accessibility Permission",
            failurePoint: "Accessibility permission is missing or stale.",
            nextStep: "Open System Settings -> Privacy & Security -> Accessibility, enable VoiceInput. If already enabled, remove the old VoiceInput entry and add /Applications/VoiceInput.app again.",
            reopenInstruction: "Quit and reopen VoiceInput after changing this permission.",
            primarySettingsURL: settingsURL,
            requiresReopenOnly: false
        )
    }

    private static func inputMonitoringGuidance(settingsURL: URL?) -> PermissionRecoveryGuidance {
        make(
            title: "Fix Input Monitoring Permission",
            failurePoint: "Input Monitoring permission is missing or stale.",
            nextStep: "Open System Settings -> Privacy & Security -> Input Monitoring, enable VoiceInput. If already enabled, remove the old VoiceInput entry and add /Applications/VoiceInput.app again.",
            reopenInstruction: "Quit and reopen VoiceInput after changing this permission.",
            primarySettingsURL: settingsURL,
            requiresReopenOnly: false
        )
    }

    private static func microphoneGuidance(settingsURL: URL?) -> PermissionRecoveryGuidance {
        make(
            title: "Fix Microphone Permission",
            failurePoint: "Microphone permission is missing.",
            nextStep: "Open System Settings -> Privacy & Security -> Microphone and enable VoiceInput.",
            reopenInstruction: "Reopen VoiceInput if the status does not refresh.",
            primarySettingsURL: settingsURL,
            requiresReopenOnly: false
        )
    }

    private static func speechRecognitionGuidance(settingsURL: URL?) -> PermissionRecoveryGuidance {
        make(
            title: "Fix Speech Recognition Permission",
            failurePoint: "Speech Recognition permission is missing.",
            nextStep: "Open System Settings -> Privacy & Security -> Speech Recognition and enable VoiceInput.",
            reopenInstruction: "Reopen VoiceInput if the status does not refresh.",
            primarySettingsURL: settingsURL,
            requiresReopenOnly: false
        )
    }

    private static func make(
        title: String,
        failurePoint: String,
        nextStep: String,
        reopenInstruction: String,
        primarySettingsURL: URL?,
        requiresReopenOnly: Bool
    ) -> PermissionRecoveryGuidance {
        PermissionRecoveryGuidance(
            title: title,
            failurePoint: failurePoint,
            nextStep: nextStep,
            reopenInstruction: reopenInstruction,
            detail: """
            Failed: \(failurePoint)
            Next: \(nextStep)
            Reopen: \(reopenInstruction)
            """,
            primarySettingsURL: primarySettingsURL,
            requiresReopenOnly: requiresReopenOnly
        )
    }
}

struct PermissionDiagnostics: Equatable {
    let accessibility: PermissionDiagnostic
    let inputMonitoring: PermissionDiagnostic
    let microphone: PermissionDiagnostic
    let speechRecognition: PermissionDiagnostic

    var isReady: Bool {
        allDiagnostics.allSatisfy(\.isReady)
    }

    var menuTitle: String {
        isReady ? "Permissions: Ready" : "Permissions: Needs Attention"
    }

    var detailText: String {
        let lines = allDiagnostics.map(\.line)
        return (lines + [
            "",
            "VoiceInput will not request permissions from this diagnostics view.",
            "Open System Settings only when you want to change a missing permission.",
        ]).joined(separator: "\n")
    }

    var primarySettingsURL: URL? {
        allDiagnostics.first { !$0.isReady && $0.settingsURL != nil }?.settingsURL
    }

    private var allDiagnostics: [PermissionDiagnostic] {
        [accessibility, inputMonitoring, microphone, speechRecognition]
    }

    static func capture() -> PermissionDiagnostics {
        make(
            accessibilityTrusted: AXIsProcessTrusted(),
            inputMonitoringAccess: .capture(),
            microphoneAuthorization: AVCaptureDevice.authorizationStatus(for: .audio),
            speechAuthorization: SFSpeechRecognizer.authorizationStatus()
        )
    }

    static func make(
        accessibilityTrusted: Bool,
        inputMonitoringAccess: InputMonitoringAccess,
        microphoneAuthorization: AVAuthorizationStatus,
        speechAuthorization: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionDiagnostics {
        PermissionDiagnostics(
            accessibility: PermissionDiagnostic(
                name: "Accessibility",
                state: accessibilityTrusted ? .ready : .missing,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            ),
            inputMonitoring: PermissionDiagnostic(
                name: "Input Monitoring",
                state: inputMonitoringAccess.diagnosticState,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
            ),
            microphone: PermissionDiagnostic(
                name: "Microphone",
                state: state(for: microphoneAuthorization),
                settingsURL: SpeechPermissionIssue.microphoneDenied.settingsURL
            ),
            speechRecognition: PermissionDiagnostic(
                name: "Speech Recognition",
                state: state(for: speechAuthorization),
                settingsURL: SpeechPermissionIssue.speechRecognitionDenied.settingsURL
            )
        )
    }

    private static func state(for authorizationStatus: AVAuthorizationStatus) -> PermissionDiagnosticState {
        switch authorizationStatus {
        case .authorized:
            return .ready
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .missing
        @unknown default:
            return .unknown
        }
    }

    private static func state(
        for authorizationStatus: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionDiagnosticState {
        switch authorizationStatus {
        case .authorized:
            return .ready
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .missing
        @unknown default:
            return .unknown
        }
    }
}
