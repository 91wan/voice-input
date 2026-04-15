struct SessionCounter {
    private(set) var currentID: Int = 0

    mutating func begin() -> Int {
        currentID += 1
        return currentID
    }

    mutating func invalidate() {
        currentID += 1
    }

    func isCurrent(_ id: Int) -> Bool {
        id == currentID
    }
}
