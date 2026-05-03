import Cocoa

enum DictationShortcutMode: Equatable {
    case defaultMode
    case promptBuilder
}

enum KeyMonitorAction: Equatable {
    case fnDown(mode: DictationShortcutMode)
    case fnUp
}

struct KeyMonitorState {
    private var fnPressed = false
    private var fnBlockedUntilRelease = false

    mutating func transition(
        fnDown: Bool,
        optionDown: Bool = false,
        disallowedModifierDown: Bool = false
    ) -> KeyMonitorAction? {
        if !fnDown {
            fnBlockedUntilRelease = false
            if fnPressed {
                fnPressed = false
                return .fnUp
            }
            return nil
        }

        if disallowedModifierDown {
            fnBlockedUntilRelease = true
            if fnPressed {
                fnPressed = false
                return .fnUp
            }
            return nil
        }

        guard !fnBlockedUntilRelease else { return nil }

        if !fnPressed {
            fnPressed = true
            return .fnDown(mode: optionDown ? .promptBuilder : .defaultMode)
        }

        return nil
    }

    mutating func resetForTapDisable() -> KeyMonitorAction? {
        fnBlockedUntilRelease = false
        guard fnPressed else { return nil }
        fnPressed = false
        return .fnUp
    }

    mutating func cancelForNonModifierKeyDown(fnDown: Bool) -> KeyMonitorAction? {
        guard fnDown else { return nil }
        fnBlockedUntilRelease = true
        guard fnPressed else { return nil }
        fnPressed = false
        return .fnUp
    }
}

final class KeyMonitor {
    var onFnDown: ((DictationShortcutMode) -> Void)?
    var onFnUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var state = KeyMonitorState()

    static let monitoredEventMask = CGEventMask(
        (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
    )

    deinit {
        stop()
    }

    /// Start monitoring. Returns false if accessibility permission is missing.
    func start() -> Bool {
        stop()

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.monitoredEventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        state = KeyMonitorState()
    }

    // MARK: - Private

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if the system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            dispatch(state.resetForTapDisable())
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        if type == .keyDown {
            dispatch(state.cancelForNonModifierKeyDown(fnDown: flags.contains(.maskSecondaryFn)))
            return Unmanaged.passUnretained(event)
        }

        let fnDown = flags.contains(.maskSecondaryFn)
        let optionDown = flags.contains(.maskAlternate)
        let disallowedModifierDown = flags.contains(.maskControl)
            || flags.contains(.maskCommand)
            || flags.contains(.maskShift)
        if let action = state.transition(
            fnDown: fnDown,
            optionDown: optionDown,
            disallowedModifierDown: disallowedModifierDown
        ) {
            dispatch(action)
            return nil // suppress Fn press/release (prevents emoji picker)
        }

        return Unmanaged.passUnretained(event)
    }

    private func dispatch(_ action: KeyMonitorAction?) {
        guard let action else { return }
        switch action {
        case .fnDown(let mode):
            DispatchQueue.main.async { [weak self] in self?.onFnDown?(mode) }
        case .fnUp:
            DispatchQueue.main.async { [weak self] in self?.onFnUp?() }
        }
    }
}
