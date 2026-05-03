import AVFoundation
import Speech
import XCTest
@testable import VoiceInput

final class ReadinessDiagnosticsTests: XCTestCase {
    func testReadinessCombinesPermissionsLLMAndDictionaryState() {
        let readiness = ReadinessDiagnostics.make(
            permissionDiagnostics: .make(
                accessibilityTrusted: true,
                inputMonitoringAccess: .granted,
                microphoneAuthorization: .authorized,
                speechAuthorization: .authorized
            ),
            isLLMConfigured: true,
            dictionaryLoadIssue: nil,
            userDictionaryEntryCount: 3
        )

        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.title, "VoiceInput is ready")
        XCTAssertEqual(readiness.menuTitle, "Readiness: Ready")
        XCTAssertEqual(readiness.items.map(\.title), [
            "Accessibility",
            "Input Monitoring",
            "Microphone",
            "Speech Recognition",
            "LLM Refinement",
            "Dictation Mode",
            "Dictionary",
        ])
        XCTAssertEqual(readiness.items.first(where: { $0.title == "LLM Refinement" })?.detail, "Ready")
        XCTAssertEqual(
            readiness.items.first(where: { $0.title == "Dictation Mode" })?.detail,
            "Fn uses Precise Dictation. Option + Fn uses Prompt Builder once. LLM refinement is ready."
        )
        XCTAssertEqual(readiness.items.first(where: { $0.title == "Dictionary" })?.detail, "Loaded 3 user rules")
    }

    func testLLMConfigurationIsRecommendedButNotBlocking() {
        let readiness = ReadinessDiagnostics.make(
            permissionDiagnostics: .make(
                accessibilityTrusted: true,
                inputMonitoringAccess: .granted,
                microphoneAuthorization: .authorized,
                speechAuthorization: .authorized
            ),
            isLLMConfigured: false,
            dictionaryLoadIssue: nil,
            userDictionaryEntryCount: 0
        )

        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.title, "VoiceInput is ready")
        XCTAssertEqual(readiness.items.first(where: { $0.title == "LLM Refinement" })?.state, .optional)
        XCTAssertEqual(readiness.items.first(where: { $0.title == "LLM Refinement" })?.action, .openLLMSettings)
        XCTAssertTrue(
            readiness.items.first(where: { $0.title == "Dictation Mode" })?.detail
                .contains("ordinary Fn still uses Apple Speech + DictionaryFilter without extra errors") == true
        )
    }

    func testMissingPermissionAndDictionaryLoadIssueNeedAttention() {
        let readiness = ReadinessDiagnostics.make(
            permissionDiagnostics: .make(
                accessibilityTrusted: false,
                inputMonitoringAccess: .denied,
                microphoneAuthorization: .authorized,
                speechAuthorization: .authorized
            ),
            isLLMConfigured: true,
            dictionaryLoadIssue: "invalid dictionary",
            userDictionaryEntryCount: 0
        )

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.title, "VoiceInput needs attention")
        XCTAssertEqual(readiness.menuTitle, "Readiness: Needs Attention")
        XCTAssertEqual(readiness.primaryAction, .openAccessibilitySettings)
        XCTAssertTrue(
            readiness.items.first(where: { $0.title == "Accessibility" })?.detail
                .contains("Failed: Accessibility permission is missing or stale.") == true
        )
        XCTAssertTrue(
            readiness.items.first(where: { $0.title == "Input Monitoring" })?.detail
                .contains("Next: Open System Settings -> Privacy & Security -> Input Monitoring") == true
        )
        XCTAssertEqual(readiness.items.first(where: { $0.title == "Dictionary" })?.state, .attention)
        XCTAssertEqual(readiness.items.first(where: { $0.title == "Dictionary" })?.action, .openDictionary)
    }

    func testEventMonitorFailureWithReadyPermissionsSurfacesReopenAppStatus() {
        let readiness = ReadinessDiagnostics.make(
            permissionDiagnostics: .make(
                accessibilityTrusted: true,
                inputMonitoringAccess: .granted,
                microphoneAuthorization: .authorized,
                speechAuthorization: .authorized
            ),
            isLLMConfigured: true,
            dictionaryLoadIssue: nil,
            userDictionaryEntryCount: 0,
            eventMonitorStartFailed: true
        )

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.title, "VoiceInput needs a restart")
        XCTAssertEqual(readiness.menuTitle, "Readiness: Reopen App")
        XCTAssertNil(readiness.primaryAction)
        XCTAssertEqual(readiness.items.first?.title, "Reopen VoiceInput")
        XCTAssertTrue(readiness.items.first?.detail.localizedCaseInsensitiveContains("quit and reopen") == true)
        XCTAssertTrue(readiness.items.first?.detail.contains("Reopen: Required.") == true)
        XCTAssertTrue(readiness.items.first?.detail.contains("/Applications/VoiceInput.app") == true)
    }
}
