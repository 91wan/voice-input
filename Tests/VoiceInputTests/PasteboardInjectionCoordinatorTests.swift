import AppKit
import XCTest
@testable import VoiceInput

final class PasteboardInjectionCoordinatorTests: XCTestCase {
    private func writeString(_ value: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([item]))
    }

    func testSingleInjectionRestoresOriginalClipboardWhenStillOwned() {
        let pasteboard = NSPasteboard.withUniqueName()
        writeString("original", to: pasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let generation = coordinator.prepareInjection(on: pasteboard)
        writeString("generated", to: pasteboard)
        coordinator.recordInjectedChangeCount(pasteboard.changeCount, generation: generation)
        coordinator.restoreIfStillOwned(on: pasteboard, generation: generation)

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testUserClipboardChangePreventsRestore() {
        let pasteboard = NSPasteboard.withUniqueName()
        writeString("original", to: pasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let generation = coordinator.prepareInjection(on: pasteboard)
        writeString("generated", to: pasteboard)
        coordinator.recordInjectedChangeCount(pasteboard.changeCount, generation: generation)
        writeString("user copied", to: pasteboard)
        coordinator.restoreIfStillOwned(on: pasteboard, generation: generation)

        XCTAssertEqual(pasteboard.string(forType: .string), "user copied")
    }

    func testTwoConsecutiveInjectionsRestoreFirstOriginalClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        writeString("original", to: pasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let firstGeneration = coordinator.prepareInjection(on: pasteboard)
        writeString("first generated", to: pasteboard)
        coordinator.recordInjectedChangeCount(pasteboard.changeCount, generation: firstGeneration)

        let secondGeneration = coordinator.prepareInjection(on: pasteboard)
        writeString("second generated", to: pasteboard)
        coordinator.recordInjectedChangeCount(pasteboard.changeCount, generation: secondGeneration)

        coordinator.restoreIfStillOwned(on: pasteboard, generation: firstGeneration)
        XCTAssertEqual(pasteboard.string(forType: .string), "second generated")

        coordinator.restoreIfStillOwned(on: pasteboard, generation: secondGeneration)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testTwoConsecutiveInjectionsDoNotRestoreAfterUserClipboardChange() {
        let pasteboard = NSPasteboard.withUniqueName()
        writeString("original", to: pasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let firstGeneration = coordinator.prepareInjection(on: pasteboard)
        writeString("first generated", to: pasteboard)
        coordinator.recordInjectedChangeCount(pasteboard.changeCount, generation: firstGeneration)

        let secondGeneration = coordinator.prepareInjection(on: pasteboard)
        writeString("second generated", to: pasteboard)
        coordinator.recordInjectedChangeCount(pasteboard.changeCount, generation: secondGeneration)
        writeString("user copied", to: pasteboard)

        coordinator.restoreIfStillOwned(on: pasteboard, generation: secondGeneration)

        XCTAssertEqual(pasteboard.string(forType: .string), "user copied")
    }
}
