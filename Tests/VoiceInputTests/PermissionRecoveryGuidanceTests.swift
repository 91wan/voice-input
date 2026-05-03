import AVFoundation
import Speech
import XCTest
@testable import VoiceInput

final class PermissionRecoveryGuidanceTests: XCTestCase {
    func testAccessibilityMissingGuidanceTellsUserHowToRecover() {
        let diagnostics = PermissionDiagnostics.make(
            accessibilityTrusted: false,
            inputMonitoringAccess: .granted,
            microphoneAuthorization: .authorized,
            speechAuthorization: .authorized
        )

        let guidance = PermissionRecoveryGuidance.make(
            diagnostics: diagnostics,
            eventMonitorStartFailed: false
        )

        XCTAssertEqual(guidance.title, "Fix Accessibility Permission")
        XCTAssertEqual(guidance.failurePoint, "Accessibility permission is missing or stale.")
        XCTAssertEqual(
            guidance.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertTrue(guidance.detail.contains("Failed: Accessibility permission is missing or stale."))
        XCTAssertTrue(guidance.detail.contains("Next:"))
        XCTAssertTrue(guidance.detail.contains("Reopen:"))
        XCTAssertTrue(guidance.detail.contains("enable VoiceInput"))
        XCTAssertTrue(guidance.detail.localizedCaseInsensitiveContains("quit and reopen"))
        XCTAssertFalse(guidance.requiresReopenOnly)
    }

    func testInputMonitoringMissingGuidancePointsToInputMonitoring() {
        let diagnostics = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            inputMonitoringAccess: .denied,
            microphoneAuthorization: .authorized,
            speechAuthorization: .authorized
        )

        let guidance = PermissionRecoveryGuidance.make(
            diagnostics: diagnostics,
            eventMonitorStartFailed: false
        )

        XCTAssertEqual(guidance.title, "Fix Input Monitoring Permission")
        XCTAssertEqual(guidance.failurePoint, "Input Monitoring permission is missing or stale.")
        XCTAssertEqual(
            guidance.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
        XCTAssertTrue(guidance.detail.contains("Failed: Input Monitoring permission is missing or stale."))
        XCTAssertTrue(guidance.detail.contains("Next:"))
        XCTAssertTrue(guidance.detail.contains("Reopen:"))
        XCTAssertTrue(guidance.detail.contains("Input Monitoring"))
        XCTAssertTrue(guidance.detail.localizedCaseInsensitiveContains("quit and reopen"))
        XCTAssertFalse(guidance.requiresReopenOnly)
    }

    func testMicrophoneMissingGuidanceIncludesFailureNextStepAndReopenPolicy() {
        let diagnostics = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            inputMonitoringAccess: .granted,
            microphoneAuthorization: .denied,
            speechAuthorization: .authorized
        )

        let guidance = PermissionRecoveryGuidance.make(
            diagnostics: diagnostics,
            eventMonitorStartFailed: false
        )

        XCTAssertEqual(guidance.title, "Fix Microphone Permission")
        XCTAssertEqual(guidance.failurePoint, "Microphone permission is missing.")
        XCTAssertTrue(guidance.detail.contains("Failed: Microphone permission is missing."))
        XCTAssertTrue(guidance.detail.contains("Next: Open System Settings -> Privacy & Security -> Microphone"))
        XCTAssertTrue(guidance.detail.contains("Reopen: Reopen VoiceInput if the status does not refresh."))
    }

    func testSpeechRecognitionMissingGuidanceIncludesFailureNextStepAndReopenPolicy() {
        let diagnostics = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            inputMonitoringAccess: .granted,
            microphoneAuthorization: .authorized,
            speechAuthorization: .denied
        )

        let guidance = PermissionRecoveryGuidance.make(
            diagnostics: diagnostics,
            eventMonitorStartFailed: false
        )

        XCTAssertEqual(guidance.title, "Fix Speech Recognition Permission")
        XCTAssertEqual(guidance.failurePoint, "Speech Recognition permission is missing.")
        XCTAssertTrue(guidance.detail.contains("Failed: Speech Recognition permission is missing."))
        XCTAssertTrue(guidance.detail.contains("Next: Open System Settings -> Privacy & Security -> Speech Recognition"))
        XCTAssertTrue(guidance.detail.contains("Reopen: Reopen VoiceInput if the status does not refresh."))
    }

    func testAllPermissionsReadyButEventMonitorFailedRequiresReopen() {
        let diagnostics = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            inputMonitoringAccess: .granted,
            microphoneAuthorization: .authorized,
            speechAuthorization: .authorized
        )

        let guidance = PermissionRecoveryGuidance.make(
            diagnostics: diagnostics,
            eventMonitorStartFailed: true
        )

        XCTAssertEqual(guidance.title, "Reopen VoiceInput Required")
        XCTAssertEqual(guidance.failurePoint, "Input monitor is not active even though permissions appear enabled.")
        XCTAssertNil(guidance.primarySettingsURL)
        XCTAssertTrue(guidance.requiresReopenOnly)
        XCTAssertTrue(guidance.detail.contains("Failed: Input monitor is not active even though permissions appear enabled."))
        XCTAssertTrue(guidance.detail.contains("Next: Quit and reopen VoiceInput."))
        XCTAssertTrue(guidance.detail.contains("Reopen: Required."))
        XCTAssertTrue(guidance.detail.localizedCaseInsensitiveContains("quit and reopen"))
        XCTAssertTrue(guidance.detail.contains("/Applications/VoiceInput.app"))
    }
}
