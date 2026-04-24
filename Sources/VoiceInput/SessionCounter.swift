struct SessionCounter {
    private(set) var currentID: Int = 0
    private var claimedID: Int?

    mutating func begin() -> Int {
        currentID += 1
        claimedID = nil
        return currentID
    }

    mutating func invalidate() {
        currentID += 1
        claimedID = nil
    }

    func isCurrent(_ id: Int) -> Bool {
        id == currentID
    }

    mutating func claimCurrent(_ id: Int) -> Bool {
        guard isCurrent(id), claimedID != id else { return false }
        claimedID = id
        return true
    }
}
