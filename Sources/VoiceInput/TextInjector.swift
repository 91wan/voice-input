import AppKit
import ApplicationServices
import Carbon

enum TextInjectionFailure: LocalizedError, Equatable {
    case emptyText
    case accessibilityPermissionMissing
    case pasteboardWriteFailed
    case pasteCommandFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Nothing to paste."
        case .accessibilityPermissionMissing:
            return PermissionRecoveryGuidance.make(
                diagnostics: .make(
                    accessibilityTrusted: false,
                    inputMonitoringAccess: .granted,
                    microphoneAuthorization: .authorized,
                    speechAuthorization: .authorized
                ),
                eventMonitorStartFailed: false
            ).detail
        case .pasteboardWriteFailed:
            return "Paste failed. VoiceInput couldn't write to the clipboard."
        case .pasteCommandFailed:
            return "Paste failed. Text was copied to the clipboard."
        }
    }

    var shouldPromptForAccessibility: Bool {
        self == .accessibilityPermissionMissing
    }
}

enum TextInjectionResult: Equatable {
    case success
    case failure(TextInjectionFailure)
}

struct PasteboardItemSnapshot {
    let representations: [(type: NSPasteboard.PasteboardType, data: Data)]

    init(item: NSPasteboardItem) {
        representations = item.types.compactMap { type in
            guard let data = item.data(forType: type) else { return nil }
            return (type, data)
        }
    }

    func makePasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for representation in representations {
            item.setData(representation.data, forType: representation.type)
        }
        return item
    }
}

struct PasteboardSnapshot {
    let items: [PasteboardItemSnapshot]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map(PasteboardItemSnapshot.init)
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { $0.makePasteboardItem() }
        pasteboard.writeObjects(restoredItems)
    }
}

final class PasteboardInjectionCoordinator {
    private struct Ownership {
        let originalSnapshot: PasteboardSnapshot
        var latestInjectedChangeCount: Int?
        var generation: Int
    }

    private var ownership: Ownership?
    private var nextGeneration = 0

    func prepareInjection(on pasteboard: NSPasteboard) -> Int {
        let originalSnapshot: PasteboardSnapshot
        if let currentOwnership = ownership,
           currentOwnership.latestInjectedChangeCount == pasteboard.changeCount {
            originalSnapshot = currentOwnership.originalSnapshot
        } else {
            originalSnapshot = PasteboardSnapshot.capture(from: pasteboard)
        }

        nextGeneration += 1
        ownership = Ownership(
            originalSnapshot: originalSnapshot,
            latestInjectedChangeCount: nil,
            generation: nextGeneration
        )
        return nextGeneration
    }

    func recordInjectedChangeCount(_ changeCount: Int, generation: Int) {
        guard ownership?.generation == generation else { return }
        ownership?.latestInjectedChangeCount = changeCount
    }

    func restoreIfStillOwned(on pasteboard: NSPasteboard, generation: Int) {
        guard let currentOwnership = ownership else { return }
        guard currentOwnership.generation == generation else { return }
        guard currentOwnership.latestInjectedChangeCount == pasteboard.changeCount else {
            ownership = nil
            return
        }

        currentOwnership.originalSnapshot.restore(to: pasteboard)
        ownership = nil
    }

    func cancelInjection(on pasteboard: NSPasteboard, generation: Int, restoreOriginal: Bool) {
        guard let currentOwnership = ownership,
              currentOwnership.generation == generation
        else { return }

        if restoreOriginal {
            currentOwnership.originalSnapshot.restore(to: pasteboard)
        }
        ownership = nil
    }
}

final class TextInjector {
    static let defaultPasteboardRestoreDelay: TimeInterval = 1.5
    private static let sharedPasteboardCoordinator = PasteboardInjectionCoordinator()

    private let pasteboard: NSPasteboard
    private let pasteboardCoordinator: PasteboardInjectionCoordinator
    private let inputSourceRestoreDelay: TimeInterval
    private let pasteboardRestoreDelay: TimeInterval
    private let isProcessTrusted: () -> Bool
    private let postPasteCommandHandler: () -> Bool

    init(
        pasteboard: NSPasteboard = .general,
        pasteboardCoordinator: PasteboardInjectionCoordinator = TextInjector.sharedPasteboardCoordinator,
        inputSourceRestoreDelay: TimeInterval = 0.3,
        pasteboardRestoreDelay: TimeInterval = TextInjector.defaultPasteboardRestoreDelay,
        isProcessTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        postPasteCommandHandler: @escaping () -> Bool = TextInjector.defaultPostPasteCommand
    ) {
        self.pasteboard = pasteboard
        self.pasteboardCoordinator = pasteboardCoordinator
        self.inputSourceRestoreDelay = inputSourceRestoreDelay
        self.pasteboardRestoreDelay = pasteboardRestoreDelay
        self.isProcessTrusted = isProcessTrusted
        self.postPasteCommandHandler = postPasteCommandHandler
    }

    @discardableResult
    func inject(_ text: String) -> TextInjectionResult {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return .failure(.emptyText) }
        guard isProcessTrusted() else { return .failure(.accessibilityPermissionMissing) }

        let injectionGeneration = pasteboardCoordinator.prepareInjection(on: pasteboard)

        let injectedItem = NSPasteboardItem()
        guard injectedItem.setString(normalizedText, forType: .string) else {
            pasteboardCoordinator.cancelInjection(
                on: pasteboard,
                generation: injectionGeneration,
                restoreOriginal: false
            )
            return .failure(.pasteboardWriteFailed)
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([injectedItem]) else {
            pasteboardCoordinator.cancelInjection(
                on: pasteboard,
                generation: injectionGeneration,
                restoreOriginal: true
            )
            return .failure(.pasteboardWriteFailed)
        }

        let injectedChangeCount = pasteboard.changeCount
        pasteboardCoordinator.recordInjectedChangeCount(
            injectedChangeCount,
            generation: injectionGeneration
        )

        let originalSource = currentKeyboardInputSource()
        let needSwitch = originalSource.map { !isASCIICapable($0) } ?? false
        let temporarySource = needSwitch ? findASCIICapableSource() : nil

        if let temporarySource {
            TISSelectInputSource(temporarySource)
            usleep(50_000) // 50ms for system to settle
        }

        guard postPasteCommandHandler() else {
            restoreInputSourceIfStillUsingTemporary(originalSource: originalSource, temporarySource: temporarySource)
            return .failure(.pasteCommandFailed)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + inputSourceRestoreDelay) { [weak self] in
            guard let self else { return }
            self.restoreInputSourceIfStillUsingTemporary(
                originalSource: originalSource,
                temporarySource: temporarySource
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteboardRestoreDelay) { [weak self] in
            guard let self else { return }
            self.restorePasteboardIfStillOwned(generation: injectionGeneration)
        }

        return .success
    }

    static func shouldRestorePasteboard(currentChangeCount: Int, injectedChangeCount: Int) -> Bool {
        currentChangeCount == injectedChangeCount
    }

    // MARK: - Pasteboard / Event helpers

    private func restorePasteboardIfStillOwned(generation: Int) {
        pasteboardCoordinator.restoreIfStillOwned(on: pasteboard, generation: generation)
    }

    private static func defaultPostPasteCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    // MARK: - Input Source Helpers

    private func restoreInputSourceIfStillUsingTemporary(
        originalSource: TISInputSource?,
        temporarySource: TISInputSource?
    ) {
        guard let originalSource else { return }
        guard let temporarySource else { return }
        guard currentInputSourceID() == inputSourceID(for: temporarySource) else { return }
        TISSelectInputSource(originalSource)
    }

    private func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else {
            return false
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func findASCIICapableSource() -> TISInputSource? {
        let criteria = [
            kTISPropertyInputSourceIsASCIICapable: true,
            kTISPropertyInputSourceIsEnabled: true,
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(criteria, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        // Prefer ABC or US keyboard
        for source in sourceList {
            if let id = inputSourceID(for: source),
               id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US" {
                return source
            }
        }

        return sourceList.first
    }

    private func currentInputSourceID() -> String? {
        guard let currentSource = currentKeyboardInputSource() else { return nil }
        return inputSourceID(for: currentSource)
    }

    private func currentKeyboardInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func inputSourceID(for source: TISInputSource) -> String? {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }
}
