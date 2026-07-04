import XCTest
@testable import VoiceInput

final class AppDelegateTests: XCTestCase {
    func testEmptyLocaleCodeResolvesToSystemCurrentLocale() {
        XCTAssertEqual(
            AppDelegate.locale(forSelectedLocaleCode: "").identifier,
            Locale.current.identifier
        )
    }

    func testExplicitLocaleCodeResolvesToRequestedLocale() {
        XCTAssertEqual(
            AppDelegate.locale(forSelectedLocaleCode: "en-US").identifier,
            Locale(identifier: "en-US").identifier
        )
    }

    func testLocaleCodeTrimsWhitespaceBeforeResolving() {
        XCTAssertEqual(
            AppDelegate.normalizedLocaleCode("  en-US  "),
            "en-US"
        )
        XCTAssertEqual(
            AppDelegate.locale(forSelectedLocaleCode: "  en-US  ").identifier,
            Locale(identifier: "en-US").identifier
        )
    }

    func testUnsupportedLocaleCodeFallsBackToDefault() {
        XCTAssertEqual(AppDelegate.normalizedLocaleCode("fr-FR"), "zh-CN")
        XCTAssertEqual(
            AppDelegate.locale(forSelectedLocaleCode: "fr-FR").identifier,
            Locale(identifier: "zh-CN").identifier
        )
    }

    func testSpeechCallbacksAreRejectedAfterSessionCompletionClaimed() {
        var sessions = SessionCounter()
        let sessionID = sessions.begin()

        XCTAssertTrue(AppDelegate.shouldAcceptSpeechCallback(activeSessionID: sessionID, sessions: sessions))

        XCTAssertTrue(sessions.claimCurrent(sessionID))
        XCTAssertFalse(AppDelegate.shouldAcceptSpeechCallback(activeSessionID: sessionID, sessions: sessions))
    }

    func testSpeechCallbacksAreRejectedForExpiredSession() {
        var sessions = SessionCounter()
        let expiredSessionID = sessions.begin()
        sessions.invalidate()

        XCTAssertFalse(AppDelegate.shouldAcceptSpeechCallback(activeSessionID: expiredSessionID, sessions: sessions))
    }

    func testOnlyLatestDictationCompletionCanMutateCurrentSession() {
        var sessions = SessionCounter()
        let firstSessionID = sessions.begin()
        XCTAssertTrue(sessions.claimCurrent(firstSessionID))

        let latestSessionID = sessions.begin()
        XCTAssertTrue(sessions.claimCurrent(latestSessionID))

        XCTAssertFalse(AppDelegate.shouldAcceptTranscriptionCompletion(activeSessionID: firstSessionID, sessions: sessions))
        XCTAssertTrue(AppDelegate.shouldAcceptTranscriptionCompletion(activeSessionID: latestSessionID, sessions: sessions))
    }

    func testBusyDictationPhaseDoesNotStartNewDictationSession() {
        XCTAssertTrue(AppDelegate.shouldStartNewDictation(isEnabled: true, phase: .idle))
        XCTAssertFalse(AppDelegate.shouldStartNewDictation(isEnabled: false, phase: .idle))
        XCTAssertFalse(AppDelegate.shouldStartNewDictation(isEnabled: true, phase: .resolving(sessionID: 1)))
        XCTAssertFalse(AppDelegate.shouldStartNewDictation(isEnabled: true, phase: .injecting(sessionID: 1)))
    }

    func testFinalRetryInsertGateReturnsBusyFailureWithoutInjecting() {
        var didInject = false

        let result = AppDelegate.retryInsertResult(
            finalText: "hello",
            phase: .resolving(sessionID: 1)
        ) { _ in
            didInject = true
            return .success
        }

        XCTAssertEqual(result, .failure(.dictationBusy))
        XCTAssertFalse(didInject)
    }

    func testShortcutModeMapsToSingleUsePromptBuilderOverride() {
        XCTAssertEqual(
            AppDelegate.refinementMode(for: .defaultMode, defaultMode: .precise),
            .precise
        )
        XCTAssertEqual(
            AppDelegate.refinementMode(for: .defaultMode, defaultMode: .promptBuilder),
            .promptBuilder
        )
        XCTAssertEqual(
            AppDelegate.refinementMode(for: .promptBuilder, defaultMode: .precise),
            .promptBuilder
        )
    }

    func testShortcutMenuTitleReflectsDefaultMode() {
        XCTAssertEqual(
            AppDelegate.defaultShortcutMenuTitle(defaultMode: .precise),
            "Fn: Precise Dictation (default)"
        )
        XCTAssertEqual(
            AppDelegate.defaultShortcutMenuTitle(defaultMode: .promptBuilder),
            "Fn: Prompt Builder (default)"
        )
    }

    func testPromptBuilderShortcutMenuTitleMarksOneShotOverride() {
        XCTAssertEqual(
            AppDelegate.promptBuilderShortcutMenuTitle(),
            "Option + Fn: Prompt Builder (one shot)"
        )
    }

    func testScheduledOneShotTimerFiresOnce() {
        let expectation = expectation(description: "timer fired")
        var fireCount = 0

        let timer = AppDelegate.scheduleOneShotTimer(interval: 0.01) { _ in
            fireCount += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertFalse(timer.isValid)
        XCTAssertEqual(fireCount, 1)
    }

    func testFinishTranscriptionFinishesSpeechEngineResourcesAfterNonEmptyTextBeforeFiltering() throws {
        let source = try String(contentsOfFile: "Sources/VoiceInput/AppDelegate.swift", encoding: .utf8)
        let methodStart = try XCTUnwrap(source.range(of: "private func finishTranscription(sessionID: Int)")?.lowerBound)
        let methodEnd = try XCTUnwrap(source.range(of: "let dictionaryResult = DictionaryFilter.shared.applying(text)", range: methodStart..<source.endIndex)?.upperBound)
        let methodSource = String(source[methodStart..<methodEnd])

        let claim = try XCTUnwrap(methodSource.range(of: "guard transcriptionSessions.claimCurrent(sessionID) else { return }")?.lowerBound)
        let trim = try XCTUnwrap(methodSource.range(of: "let text = lastPartialResult.trimmingCharacters(in: .whitespacesAndNewlines)")?.lowerBound)
        let emptyGuard = try XCTUnwrap(methodSource.range(of: "guard !text.isEmpty else")?.lowerBound)
        let finish = try XCTUnwrap(methodSource.range(of: "speechEngine.finishAfterResultConsumed()")?.lowerBound)
        let dictionary = try XCTUnwrap(methodSource.range(of: "let dictionaryResult = DictionaryFilter.shared.applying(text)")?.lowerBound)

        XCTAssertLessThan(claim, trim)
        XCTAssertLessThan(trim, emptyGuard)
        XCTAssertLessThan(emptyGuard, finish)
        XCTAssertLessThan(finish, dictionary)
    }
}
