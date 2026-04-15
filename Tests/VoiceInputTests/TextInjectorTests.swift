import AppKit
import XCTest
@testable import VoiceInput

final class TextInjectorTests: XCTestCase {
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
