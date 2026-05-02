import ApplicationServices
import AVFoundation
import Foundation
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

struct PermissionDiagnostics: Equatable {
    let accessibility: PermissionDiagnostic
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
        [accessibility, microphone, speechRecognition]
    }

    static func capture() -> PermissionDiagnostics {
        make(
            accessibilityTrusted: AXIsProcessTrusted(),
            microphoneAuthorization: AVCaptureDevice.authorizationStatus(for: .audio),
            speechAuthorization: SFSpeechRecognizer.authorizationStatus()
        )
    }

    static func make(
        accessibilityTrusted: Bool,
        microphoneAuthorization: AVAuthorizationStatus,
        speechAuthorization: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionDiagnostics {
        PermissionDiagnostics(
            accessibility: PermissionDiagnostic(
                name: "Accessibility",
                state: accessibilityTrusted ? .ready : .missing,
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
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
