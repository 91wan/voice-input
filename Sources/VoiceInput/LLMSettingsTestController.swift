final class LLMSettingsTestController {
    private var activeTestRequest: CancellableRequest?
    private var generation = 0

    var isIdle: Bool {
        activeTestRequest == nil
    }

    @discardableResult
    func beginTest(request: CancellableRequest? = nil) -> Int {
        let generation = beginAttempt()
        activeTestRequest = request
        return generation
    }

    @discardableResult
    func beginAttempt() -> Int {
        cancelActiveRequestOnly()
        generation += 1
        return generation
    }

    func setActiveRequest(_ request: CancellableRequest?, generation: Int) {
        guard self.generation == generation else {
            request?.cancel()
            return
        }
        activeTestRequest = request
    }

    func finishTest(generation: Int) -> Bool {
        guard self.generation == generation else { return false }
        activeTestRequest = nil
        return true
    }

    func cancelActiveTest() {
        cancelActiveRequestOnly()
        generation += 1
    }

    private func cancelActiveRequestOnly() {
        activeTestRequest?.cancel()
        activeTestRequest = nil
    }
}
