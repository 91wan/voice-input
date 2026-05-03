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
        XCTAssertEqual(
            guidance.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
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
        XCTAssertEqual(
            guidance.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
        XCTAssertTrue(guidance.detail.contains("Input Monitoring"))
        XCTAssertTrue(guidance.detail.localizedCaseInsensitiveContains("quit and reopen"))
        XCTAssertFalse(guidance.requiresReopenOnly)
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
        XCTAssertNil(guidance.primarySettingsURL)
        XCTAssertTrue(guidance.requiresReopenOnly)
        XCTAssertTrue(guidance.detail.localizedCaseInsensitiveContains("quit and reopen"))
        XCTAssertTrue(guidance.detail.contains("/Applications/VoiceInput.app"))
    }
}
