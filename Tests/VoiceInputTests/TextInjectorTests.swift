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
        let pasteboard = NSPasteboard.withUniqueName()
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
        let pasteboard = NSPasteboard.withUniqueName()
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
        let pasteboard = NSPasteboard.withUniqueName()
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

    func testPasteboardSnapshotRoundTripsStringAndCustomData() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let customType = NSPasteboard.PasteboardType("com.voiceinput.test")
        let customData = Data([0x01, 0x02, 0x03, 0x04])

        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(customData, forType: customType)

        pasteboard.clearContents()
        assertWrite(item, to: pasteboard)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        let temporaryItem = NSPasteboardItem()
        temporaryItem.setString("temporary", forType: .string)
        assertWrite(temporaryItem, to: pasteboard)

        snapshot.restore(to: pasteboard)

        let restoredItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(restoredItem.string(forType: .string), "hello")
        XCTAssertEqual(restoredItem.data(forType: customType), customData)
    }

    func testShouldRestorePasteboardOnlyWhileClipboardIsStillOwnedByInjection() {
        XCTAssertTrue(TextInjector.shouldRestorePasteboard(currentChangeCount: 12, injectedChangeCount: 12))
        XCTAssertFalse(TextInjector.shouldRestorePasteboard(currentChangeCount: 13, injectedChangeCount: 12))
    }
}
