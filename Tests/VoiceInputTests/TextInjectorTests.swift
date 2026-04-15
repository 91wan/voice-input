import AppKit
import XCTest
@testable import VoiceInput

final class TextInjectorTests: XCTestCase {
    func testInjectFailsFastWithoutAccessibilityPermission() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()

        let initialItem = NSPasteboardItem()
        initialItem.setString("original", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([initialItem]))
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

    func testInjectRestoresClipboardWhenPasteCommandFails() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()

        let initialItem = NSPasteboardItem()
        initialItem.setString("original", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([initialItem]))

        let injector = TextInjector(
            pasteboard: pasteboard,
            inputSourceRestoreDelay: 0,
            pasteboardRestoreDelay: 0,
            isProcessTrusted: { true },
            postPasteCommandHandler: { false }
        )

        XCTAssertEqual(injector.inject("hello"), .failure(.pasteCommandFailed))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testPasteboardSnapshotRoundTripsStringAndCustomData() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let customType = NSPasteboard.PasteboardType("com.voiceinput.test")
        let customData = Data([0x01, 0x02, 0x03, 0x04])

        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(customData, forType: customType)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        let temporaryItem = NSPasteboardItem()
        temporaryItem.setString("temporary", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([temporaryItem]))

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
