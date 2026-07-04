import AppKit
import XCTest
@testable import VoiceInput

final class TextInjectorTests: XCTestCase {
    private func assertWrite(
        _ item: NSPasteboardItem,
        to pasteboard: NSPasteboard,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<3 {
            if pasteboard.writeObjects([item]) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Failed to write test item to pasteboard", file: file, line: line)
    }

    func testInjectFailsFastWithoutAccessibilityPermission() throws {
        let pasteboard = PasteboardTestSupport.makePasteboard()
        pasteboard.clearContents()

        let initialItem = NSPasteboardItem()
        initialItem.setString("original", forType: .string)
        assertWrite(initialItem, to: pasteboard)
        let initialChangeCount = pasteboard.changeCount

        let injector = TextInjector(
            pasteboard: pasteboard,
            inputSourceRestoreDelay: 0,
            pasteboardRestoreDelay: 0,
            isProcessTrusted: { false },
            postPasteCommandHandler: {
                XCTFail("Paste command should not be attempted without accessibility permission")
                return false
            }
        )

        XCTAssertEqual(injector.inject("hello"), .failure(.accessibilityPermissionMissing))
        XCTAssertEqual(pasteboard.changeCount, initialChangeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testAccessibilityFailureExplainsStalePermissionState() {
        let message = TextInjectionFailure.accessibilityPermissionMissing.localizedDescription

        XCTAssertTrue(message.contains("Failed: Accessibility permission is missing or stale."))
        XCTAssertTrue(message.contains("Next:"))
        XCTAssertTrue(message.contains("Reopen:"))
        XCTAssertTrue(message.contains("/Applications/VoiceInput.app"))
    }

    func testInjectTreatsWhitespaceOnlyTextAsEmpty() {
        let pasteboard = PasteboardTestSupport.makePasteboard()
        pasteboard.clearContents()
        let initialChangeCount = pasteboard.changeCount

        let injector = TextInjector(
            pasteboard: pasteboard,
            inputSourceRestoreDelay: 0,
            pasteboardRestoreDelay: 0,
            isProcessTrusted: { true },
            postPasteCommandHandler: {
                XCTFail("Paste command should not be attempted for whitespace-only text")
                return false
            }
        )

        XCTAssertEqual(injector.inject(" \n\t "), .failure(.emptyText))
        XCTAssertEqual(pasteboard.changeCount, initialChangeCount)
    }

    func testInjectLeavesTextOnClipboardWhenPasteCommandFails() {
        let pasteboard = PasteboardTestSupport.makePasteboard()
        pasteboard.clearContents()

        let initialItem = NSPasteboardItem()
        initialItem.setString("original", forType: .string)
        assertWrite(initialItem, to: pasteboard)

        let injector = TextInjector(
            pasteboard: pasteboard,
            inputSourceRestoreDelay: 0,
            pasteboardRestoreDelay: 0,
            isProcessTrusted: { true },
            postPasteCommandHandler: { false }
        )

        XCTAssertEqual(injector.inject("hello"), .failure(.pasteCommandFailed))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertTrue(
            TextInjectionFailure.pasteCommandFailed.localizedDescription.localizedCaseInsensitiveContains("clipboard")
        )
    }

    func testDictationBusyFailureDoesNotClaimClipboardOrPasteCommand() {
        let message = TextInjectionFailure.dictationBusy.localizedDescription

        XCTAssertTrue(message.contains("Finish the current dictation before retrying insertion."))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("copied"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("paste command sent"))
    }

    func testPasteCommandFailureThenUserClipboardChangeMakesNextRestoreUseNewBaseline() {
        let pasteboard = PasteboardTestSupport.makePasteboard()
        pasteboard.clearContents()
        writeString("original", to: pasteboard)

        var shouldPasteSucceed = false
        let injector = TextInjector(
            pasteboard: pasteboard,
            inputSourceRestoreDelay: 0,
            pasteboardRestoreDelay: 0,
            isProcessTrusted: { true },
            postPasteCommandHandler: { shouldPasteSucceed }
        )

        XCTAssertEqual(injector.inject("failed generated"), .failure(.pasteCommandFailed))
        XCTAssertEqual(pasteboard.string(forType: .string), "failed generated")

        writeString("user copied", to: pasteboard)
        shouldPasteSucceed = true
        XCTAssertEqual(injector.inject("second generated"), .success)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(pasteboard.string(forType: .string), "user copied")
    }

    func testPasteCommandFailureWithoutUserClipboardChangeMakesNextRestoreUseOriginalBaseline() {
        let pasteboard = PasteboardTestSupport.makePasteboard()
        pasteboard.clearContents()
        writeString("original", to: pasteboard)

        var shouldPasteSucceed = false
        let injector = TextInjector(
            pasteboard: pasteboard,
            inputSourceRestoreDelay: 0,
            pasteboardRestoreDelay: 0,
            isProcessTrusted: { true },
            postPasteCommandHandler: { shouldPasteSucceed }
        )

        XCTAssertEqual(injector.inject("failed generated"), .failure(.pasteCommandFailed))
        XCTAssertEqual(pasteboard.string(forType: .string), "failed generated")

        shouldPasteSucceed = true
        XCTAssertEqual(injector.inject("second generated"), .success)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testDefaultPasteboardRestoreDelayAllowsSlowPasteConsumers() {
        XCTAssertEqual(TextInjector.defaultPasteboardRestoreDelay, 1.5)
    }

    func testPasteboardSnapshotRoundTripsStringAndNonStringData() throws {
        let pasteboard = PasteboardTestSupport.makePasteboard()
        let dataType = NSPasteboard.PasteboardType.rtf
        let nonStringData = Data([0x7b, 0x5c, 0x72, 0x74, 0x66, 0x31, 0x20, 0x68, 0x69, 0x7d])

        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(nonStringData, forType: dataType)

        pasteboard.clearContents()
        assertWrite(item, to: pasteboard)
        let writtenItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(writtenItem.data(forType: dataType), nonStringData)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        let temporaryItem = NSPasteboardItem()
        temporaryItem.setString("temporary", forType: .string)
        assertWrite(temporaryItem, to: pasteboard)

        snapshot.restore(to: pasteboard)

        let restoredItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(restoredItem.string(forType: .string), "hello")
        XCTAssertEqual(restoredItem.data(forType: dataType), nonStringData)
    }

    func testShouldRestorePasteboardOnlyWhileClipboardIsStillOwnedByInjection() {
        XCTAssertTrue(TextInjector.shouldRestorePasteboard(currentChangeCount: 12, injectedChangeCount: 12))
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(currentChangeCount: 13, injectedChangeCount: 12))
    }

    private func writeString(_ value: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        assertWrite(item, to: pasteboard)
    }
}
