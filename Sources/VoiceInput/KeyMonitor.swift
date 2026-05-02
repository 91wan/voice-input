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

    mutating func transition(fnDown: Bool, optionDown: Bool = false) -> KeyMonitorAction? {
        if fnDown && !fnPressed {
            fnPressed = true
            return .fnDown(mode: optionDown ? .promptBuilder : .defaultMode)
        }

        if !fnDown && fnPressed {
            fnPressed = false
            return .fnUp
        }

        return nil
    }

    mutating func resetForTapDisable() -> KeyMonitorAction? {
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

    deinit {
        stop()
    }

    /// Start monitoring. Returns false if accessibility permission is missing.
    func start() -> Bool {
        stop()

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
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
        let fnDown = flags.contains(.maskSecondaryFn)
        let optionDown = flags.contains(.maskAlternate)
        if let action = state.transition(fnDown: fnDown, optionDown: optionDown) {
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
