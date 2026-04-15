import Foundation
import XCTest
@testable import VoiceInput

final class SpeechPermissionIssueTests: XCTestCase {
    func testMicrophoneIssueExposesMessageAndSettingsLink() {
        XCTAssertEqual(
            SpeechPermissionIssue.microphoneDenied.message,
            "Microphone access denied.\nGrant in System Settings → Privacy & Security → Microphone."
        )
        XCTAssertEqual(
            SpeechPermissionIssue.microphoneDenied.settingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testSpeechRecognitionIssueExposesMessageAndSettingsLink() {
        XCTAssertEqual(
            SpeechPermissionIssue.speechRecognitionDenied.message,
            "Speech recognition denied.\nGrant in System Settings → Privacy & Security → Speech Recognition."
        )
        XCTAssertEqual(
            SpeechPermissionIssue.speechRecognitionDenied.settingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        )
    }

    func testNotDeterminedIssueDoesNotExposeSettingsLink() {
        XCTAssertEqual(
            SpeechPermissionIssue.speechRecognitionNotDetermined.message,
            "Speech recognition permission not determined."
        )
        XCTAssertNil(SpeechPermissionIssue.speechRecognitionNotDetermined.settingsURL)
    }
}
