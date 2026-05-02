import AVFoundation
import Speech
import XCTest
@testable import VoiceInput

final class PermissionDiagnosticsTests: XCTestCase {
    func testReadySummaryRequiresAllCorePermissions() {
        let ready = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            microphoneAuthorization: .authorized,
            speechAuthorization: .authorized
        )
        let missingAccessibility = PermissionDiagnostics.make(
            accessibilityTrusted: false,
            microphoneAuthorization: .authorized,
            speechAuthorization: .authorized
        )

        XCTAssertTrue(ready.isReady)
        XCTAssertEqual(ready.menuTitle, "Permissions: Ready")
        XCTAssertFalse(missingAccessibility.isReady)
        XCTAssertEqual(missingAccessibility.menuTitle, "Permissions: Needs Attention")
    }

    func testDetailTextExplainsMissingPermissionsWithoutPrompting() {
        let diagnostics = PermissionDiagnostics.make(
            accessibilityTrusted: false,
            microphoneAuthorization: .denied,
            speechAuthorization: .notDetermined
        )

        XCTAssertTrue(diagnostics.detailText.contains("Accessibility: Missing"))
        XCTAssertTrue(diagnostics.detailText.contains("Microphone: Missing"))
        XCTAssertTrue(diagnostics.detailText.contains("Speech Recognition: Not Determined"))
        XCTAssertTrue(diagnostics.detailText.contains("VoiceInput will not request permissions from this diagnostics view."))
    }

    func testPrimarySettingsURLPrioritizesAccessibilityThenMicrophoneThenSpeech() {
        let accessibilityMissing = PermissionDiagnostics.make(
            accessibilityTrusted: false,
            microphoneAuthorization: .denied,
            speechAuthorization: .denied
        )
        let microphoneMissing = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            microphoneAuthorization: .denied,
            speechAuthorization: .denied
        )
        let speechMissing = PermissionDiagnostics.make(
            accessibilityTrusted: true,
            microphoneAuthorization: .authorized,
            speechAuthorization: .denied
        )

        XCTAssertEqual(
            accessibilityMissing.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertEqual(
            microphoneMissing.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            speechMissing.primarySettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        )
    }
}
