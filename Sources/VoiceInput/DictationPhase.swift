enum DictationPhase: Equatable {
    case idle
    case holding
    case recording(sessionID: Int)
    case resolving(sessionID: Int)
    case injecting(sessionID: Int)

    var isIdle: Bool {
        self == .idle
    }

    mutating func fnDown() -> DictationPhaseAction {
        guard self == .idle else { return .rejectBecauseBusy }
        self = .holding
        return .startHold
    }

    mutating func holdThresholdReached(sessionID: Int) -> DictationPhaseAction {
        guard self == .holding else { return .rejectBecauseBusy }
        self = .recording(sessionID: sessionID)
        return .startRecording(sessionID: sessionID)
    }

    mutating func fnUp() -> DictationPhaseAction {
        guard case .recording(let sessionID) = self else { return .rejectBecauseBusy }
        self = .resolving(sessionID: sessionID)
        return .stopRecording(sessionID: sessionID)
    }

    mutating func beginInjection(sessionID: Int) -> DictationPhaseAction {
        guard case .resolving(let currentSessionID) = self,
              currentSessionID == sessionID
        else { return .rejectBecauseBusy }
        self = .injecting(sessionID: sessionID)
        return .beginInjecting(sessionID: sessionID)
    }

    mutating func finishInjection(sessionID: Int) -> DictationPhaseAction {
        guard case .injecting(let currentSessionID) = self,
              currentSessionID == sessionID
        else { return .rejectBecauseBusy }
        self = .idle
        return .finish
    }

    mutating func reset() -> DictationPhaseAction {
        self = .idle
        return .reset
    }
}

enum DictationPhaseAction: Equatable {
    case startHold
    case startRecording(sessionID: Int)
    case stopRecording(sessionID: Int)
    case beginInjecting(sessionID: Int)
    case rejectBecauseBusy
    case finish
    case reset
}
