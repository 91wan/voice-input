import Foundation

final class RecentTranscriptionStore {
    private let capacity: Int
    private(set) var results: [LastTranscriptionResult] = []

    init(capacity: Int = 10) {
        self.capacity = max(1, capacity)
    }

    func record(_ result: LastTranscriptionResult) {
        results.insert(result, at: 0)
        if results.count > capacity {
            results.removeLast(results.count - capacity)
        }
    }

    func updateMostRecentInjectionResult(_ injectionResult: TextInjectionResult) {
        guard let latest = results.first else { return }
        results[0] = latest.withInjectionResult(injectionResult)
    }

    func updateInjectionResult(_ injectionResult: TextInjectionResult, for selectedResult: LastTranscriptionResult) {
        guard let index = results.firstIndex(where: { $0.hasSameIdentity(as: selectedResult) }) else { return }
        results[index] = results[index].withInjectionResult(injectionResult)
    }

    func clear() {
        results.removeAll()
    }
}
