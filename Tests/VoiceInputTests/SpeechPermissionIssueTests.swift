import Foundation
import XCTest
@testable import VoiceInput

final class SpeechPermissionIssueTests: XCTestCase {
    func testMicrophoneIssueExposesMessageAndSettingsLink() {
        XCTAssertEqual(
            SpeechPermissionIssue.microphoneDenied.message,
            """
            Failed: Microphone permission is missing.
            Next: Open System Settings -> Privacy & Security -> Microphone and enable VoiceInput.
            Reopen: Reopen VoiceInput if the status does not refresh.
            """
        )
        XCTAssertEqual(
            SpeechPermissionIssue.microphoneDenied.settingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testSpeechRecognitionIssueExposesMessageAndSettingsLink() {
        XCTAssertEqual(
            SpeechPermissionIssue.speechRecognitionDenied.message,
            """
            Failed: Speech Recognition permission is missing.
            Next: Open System Settings -> Privacy & Security -> Speech Recognition and enable VoiceInput.
            Reopen: Reopen VoiceInput if the status does not refresh.
            """
        )
        XCTAssertEqual(
            SpeechPermissionIssue.speechRecognitionDenied.settingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        )
    }

    func testNotDeterminedIssueDoesNotExposeSettingsLink() {
        XCTAssertEqual(
            SpeechPermissionIssue.speechRecognitionNotDetermined.message,
            """
            Failed: Speech Recognition permission has not been decided yet.
            Next: Start dictation again and approve the system permission prompt.
            Reopen: Reopen VoiceInput if the status does not refresh.
            """
        )
        XCTAssertNil(SpeechPermissionIssue.speechRecognitionNotDetermined.settingsURL)
    }

    func testInputFormatRequiresSampleRateAndChannelCount() {
        XCTAssertTrue(SpeechEngine.isValidInputFormat(sampleRate: 44_100, channelCount: 1))
        XCTAssertFalse(SpeechEngine.isValidInputFormat(sampleRate: 0, channelCount: 1))
        XCTAssertFalse(SpeechEngine.isValidInputFormat(sampleRate: 44_100, channelCount: 0))
    }

    func testSilentRecognitionErrorsAreNotSurfaced() {
        XCTAssertFalse(SpeechEngine.shouldSurfaceRecognitionError(code: 216, hasDeliveredFinalResult: false))
        XCTAssertFalse(SpeechEngine.shouldSurfaceRecognitionError(code: 1110, hasDeliveredFinalResult: false))
    }

    func testNonSilentRecognitionErrorsSurfaceBeforeFinalResult() {
        XCTAssertTrue(SpeechEngine.shouldSurfaceRecognitionError(code: 203, hasDeliveredFinalResult: false))
    }

    func testRecognitionErrorsAreNotSurfacedAfterFinalResult() {
        XCTAssertFalse(SpeechEngine.shouldSurfaceRecognitionError(code: 203, hasDeliveredFinalResult: true))
    }

    func testSpeechCallbacksCanBeDeliveredOnMainThread() {
        let expectation = expectation(description: "callback delivered on main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            SpeechEngine.deliverOnMain {
                XCTAssertTrue(Thread.isMainThread)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1)
    }
}
