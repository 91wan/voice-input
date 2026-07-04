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

    private func writeString(_ value: String, to pasteboard: NSPasteboard, untilChangeCount targetChangeCount: Int) {
        precondition(pasteboard.changeCount <= targetChangeCount)
        repeat {
            writeString(value, to: pasteboard)
        } while pasteboard.changeCount < targetChangeCount
        XCTAssertEqual(pasteboard.changeCount, targetChangeCount)
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

    func testDifferentPasteboardsWithMatchingChangeCountDoNotReuseOriginalSnapshot() {
        let firstPasteboard = NSPasteboard.withUniqueName()
        let secondPasteboard = NSPasteboard.withUniqueName()
        writeString("first original", to: firstPasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let firstGeneration = coordinator.prepareInjection(on: firstPasteboard)
        writeString("first generated", to: firstPasteboard)
        coordinator.recordInjectedChangeCount(firstPasteboard.changeCount, generation: firstGeneration)

        writeString("second original", to: secondPasteboard, untilChangeCount: firstPasteboard.changeCount)
        let secondGeneration = coordinator.prepareInjection(on: secondPasteboard)
        writeString("second generated", to: secondPasteboard)
        coordinator.recordInjectedChangeCount(secondPasteboard.changeCount, generation: secondGeneration)
        coordinator.restoreIfStillOwned(on: secondPasteboard, generation: secondGeneration)

        XCTAssertEqual(secondPasteboard.string(forType: .string), "second original")
    }

    func testRestoreOnDifferentPasteboardDoesNotConsumeOwnership() {
        let firstPasteboard = NSPasteboard.withUniqueName()
        let secondPasteboard = NSPasteboard.withUniqueName()
        writeString("first original", to: firstPasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let generation = coordinator.prepareInjection(on: firstPasteboard)
        writeString("first generated", to: firstPasteboard)
        coordinator.recordInjectedChangeCount(firstPasteboard.changeCount, generation: generation)
        writeString("second original", to: secondPasteboard, untilChangeCount: firstPasteboard.changeCount)

        coordinator.restoreIfStillOwned(on: secondPasteboard, generation: generation)
        XCTAssertEqual(secondPasteboard.string(forType: .string), "second original")

        coordinator.restoreIfStillOwned(on: firstPasteboard, generation: generation)
        XCTAssertEqual(firstPasteboard.string(forType: .string), "first original")
    }

    func testCancelOnDifferentPasteboardDoesNotRestoreOrClearOwnership() {
        let firstPasteboard = NSPasteboard.withUniqueName()
        let secondPasteboard = NSPasteboard.withUniqueName()
        writeString("first original", to: firstPasteboard)
        writeString("second original", to: secondPasteboard)
        let coordinator = PasteboardInjectionCoordinator()

        let generation = coordinator.prepareInjection(on: firstPasteboard)
        writeString("first generated", to: firstPasteboard)
        coordinator.recordInjectedChangeCount(firstPasteboard.changeCount, generation: generation)

        coordinator.cancelInjection(on: secondPasteboard, generation: generation, restoreOriginal: true)
        XCTAssertEqual(secondPasteboard.string(forType: .string), "second original")

        coordinator.restoreIfStillOwned(on: firstPasteboard, generation: generation)
        XCTAssertEqual(firstPasteboard.string(forType: .string), "first original")
    }
}
