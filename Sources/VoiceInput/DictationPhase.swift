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

enum BusyDictationHintPolicy {
    static func shouldShowTransient(phase: DictationPhase, isOverlayVisible: Bool) -> Bool {
        !phase.isIdle && !isOverlayVisible
    }
}

enum RetryInsertAvailability: Equatable {
    case allowed
    case busy(String)
}

enum RetryInsertPolicy {
    static let busyMessage = "Finish the current dictation before retrying insertion."

    static func availability(phase: DictationPhase) -> RetryInsertAvailability {
        phase.isIdle ? .allowed : .busy(busyMessage)
    }
}

enum RetryInsertPresentationPlan: Equatable {
    case proceed
    case missingTargetApplication
    case showBusyStatus(String)
}

enum RetryInsertPresentationPolicy {
    static func plan(
        availability: RetryInsertAvailability,
        hasTargetApplication: Bool
    ) -> RetryInsertPresentationPlan {
        switch availability {
        case .allowed:
            return hasTargetApplication ? .proceed : .missingTargetApplication
        case .busy(let message):
            return .showBusyStatus(message)
        }
    }

    static func delayedPlan(availability: RetryInsertAvailability) -> RetryInsertPresentationPlan {
        plan(availability: availability, hasTargetApplication: true)
    }
}
