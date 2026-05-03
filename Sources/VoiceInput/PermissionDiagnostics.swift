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
    let detail: String
    let primarySettingsURL: URL?
    let requiresReopenOnly: Bool

    static func make(
        diagnostics: PermissionDiagnostics,
        eventMonitorStartFailed: Bool
    ) -> PermissionRecoveryGuidance {
        if !diagnostics.accessibility.isReady {
            return PermissionRecoveryGuidance(
                title: "Fix Accessibility Permission",
                detail: """
                Open System Settings -> Privacy & Security -> Accessibility, enable VoiceInput, then quit and reopen VoiceInput.

                If the entry is already enabled but still fails, remove the old VoiceInput entry and add /Applications/VoiceInput.app again.
                """,
                primarySettingsURL: diagnostics.accessibility.settingsURL,
                requiresReopenOnly: false
            )
        }

        if !diagnostics.inputMonitoring.isReady {
            return PermissionRecoveryGuidance(
                title: "Fix Input Monitoring Permission",
                detail: """
                Open System Settings -> Privacy & Security -> Input Monitoring, enable VoiceInput, then quit and reopen VoiceInput.

                If the entry is already enabled but still fails, remove the old VoiceInput entry and add /Applications/VoiceInput.app again.
                """,
                primarySettingsURL: diagnostics.inputMonitoring.settingsURL,
                requiresReopenOnly: false
            )
        }

        if !diagnostics.microphone.isReady {
            return PermissionRecoveryGuidance(
                title: "Fix Microphone Permission",
                detail: "Open System Settings -> Privacy & Security -> Microphone and enable VoiceInput.",
                primarySettingsURL: diagnostics.microphone.settingsURL,
                requiresReopenOnly: false
            )
        }

        if !diagnostics.speechRecognition.isReady {
            return PermissionRecoveryGuidance(
                title: "Fix Speech Recognition Permission",
                detail: "Open System Settings -> Privacy & Security -> Speech Recognition and enable VoiceInput.",
                primarySettingsURL: diagnostics.speechRecognition.settingsURL,
                requiresReopenOnly: false
            )
        }

        if eventMonitorStartFailed {
            return PermissionRecoveryGuidance(
                title: "Reopen VoiceInput Required",
                detail: """
                System permissions appear enabled, but VoiceInput's input monitor is not active yet. Quit and reopen VoiceInput.

                If it still fails, remove VoiceInput from Accessibility and Input Monitoring, then add /Applications/VoiceInput.app again.
                """,
                primarySettingsURL: nil,
                requiresReopenOnly: true
            )
        }

        return PermissionRecoveryGuidance(
            title: "Permissions Ready",
            detail: "All required permissions are active.",
            primarySettingsURL: nil,
            requiresReopenOnly: false
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
