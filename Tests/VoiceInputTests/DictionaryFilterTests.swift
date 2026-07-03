import XCTest
@testable import VoiceInput

final class DictionaryFilterTests: XCTestCase {
    private func makeTemporaryDictionaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("dictionary.json")
    }

    private func writeDictionary(_ dictionary: [String: String], to url: URL) throws {
        let data = try JSONEncoder().encode(dictionary)
        try data.write(to: url)
    }

    func testParseReportsMalformedRulesWithoutSilentlySavingThem() {
        let parseResult = DictionaryFilter.parse(
            """
            open claw -> OpenClaw
            missing arrow
            empty value ->
            """
        )

        XCTAssertFalse(parseResult.canSave)
        XCTAssertEqual(parseResult.dictionary, ["open claw": "OpenClaw"])
        XCTAssertEqual(parseResult.errors.count, 2)
        XCTAssertTrue(parseResult.summary().contains("第 2 行"))
    }

    func testParseWarnsOnDuplicateRulesAndKeepsLastValue() {
        let parseResult = DictionaryFilter.parse(
            """
            open claw -> OpenClaw
            Open Claw -> OpenClaw Pro
            """
        )

        XCTAssertTrue(parseResult.canSave)
        XCTAssertEqual(parseResult.warnings.count, 1)
        XCTAssertEqual(parseResult.dictionary, ["Open Claw": "OpenClaw Pro"])
    }

    func testApplyingReturnsMatchesForTypicalTechnicalTerms() {
        let filter = DictionaryFilter(
            builtinMap: [
                "open claw": "OpenClaw",
                "type script": "TypeScript",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("open claw 和 type script")

        XCTAssertEqual(result.text, "OpenClaw 和 TypeScript")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "type script", replacement: "TypeScript", count: 1),
            DictionaryMatch(source: "open claw", replacement: "OpenClaw", count: 1),
        ])
    }

    func testApplyingDoesNotCascadeIntoReplacementText() {
        let filter = DictionaryFilter(
            builtinMap: [
                "java script": "JavaScript",
                "script": "ScriptLang",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("java script")

        XCTAssertEqual(result.text, "JavaScript")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "java script", replacement: "JavaScript", count: 1),
        ])
    }

    func testApplyingStillHandlesSeparateNonOverlappingMatches() {
        let filter = DictionaryFilter(
            builtinMap: [
                "java script": "JavaScript",
                "script": "ScriptLang",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("java script and script")

        XCTAssertEqual(result.text, "JavaScript and ScriptLang")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "java script", replacement: "JavaScript", count: 1),
            DictionaryMatch(source: "script", replacement: "ScriptLang", count: 1),
        ])
    }

    func testPureASCIIRuleDoesNotMatchInsideLongerWord() {
        let filter = DictionaryFilter(
            builtinMap: [
                "ai": "AI",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("said ai plainly")

        XCTAssertEqual(result.text, "said AI plainly")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "ai", replacement: "AI", count: 1),
        ])
    }

    func testPureASCIIRuleMatchesStandaloneTechnicalTerm() {
        let filter = DictionaryFilter(
            builtinMap: [
                "ai": "AI",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("use ai now")

        XCTAssertEqual(result.text, "use AI now")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "ai", replacement: "AI", count: 1),
        ])
    }

    func testBoundaryProtectionKeepsPhraseAndCJKRulesWorking() {
        let filter = DictionaryFilter(
            builtinMap: [
                "type script": "TypeScript",
                "杰森": "JSON",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("type script 和 杰森")

        XCTAssertEqual(result.text, "TypeScript 和 JSON")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "type script", replacement: "TypeScript", count: 1),
            DictionaryMatch(source: "杰森", replacement: "JSON", count: 1),
        ])
    }

    func testUserDictionaryOverridesBuiltinRulesCaseInsensitively() {
        let filter = DictionaryFilter(
            builtinMap: [
                "open claw": "OpenClaw",
            ],
            userMap: [
                "Open Claw": "OpenClaw Pro",
            ],
            notificationCenter: NotificationCenter()
        )

        let result = filter.applying("open claw")

        XCTAssertEqual(result.text, "OpenClaw Pro")
        XCTAssertEqual(result.matches, [
            DictionaryMatch(source: "Open Claw", replacement: "OpenClaw Pro", count: 1),
        ])
    }

    func testLoadUserDictionaryAcceptsValidJSONRules() throws {
        let url = try makeTemporaryDictionaryURL()
        try writeDictionary(["open claw": "OpenClaw Pro"], to: url)

        let filter = DictionaryFilter(
            builtinMap: [:],
            notificationCenter: NotificationCenter(),
            dictionaryURLProvider: { url }
        )

        let result = filter.loadUserDictionary()

        XCTAssertEqual(result, DictionaryLoadResult.success(entryCount: 1))
        XCTAssertEqual(filter.userMap, ["open claw": "OpenClaw Pro"])
        XCTAssertNil(filter.lastLoadIssue)
    }

    func testLoadUserDictionaryRejectsBlankRulesFromJSON() throws {
        let url = try makeTemporaryDictionaryURL()
        try writeDictionary(["   ": "OpenClaw", "valid": ""], to: url)

        let filter = DictionaryFilter(
            builtinMap: [:],
            notificationCenter: NotificationCenter(),
            dictionaryURLProvider: { url }
        )

        let result = filter.loadUserDictionary()

        guard case .failure(let message) = result else {
            return XCTFail("Expected invalid JSON rules to fail loading")
        }
        XCTAssertTrue(message.contains("左侧错误词不能为空"))
        XCTAssertTrue(message.contains("右侧正确词不能为空"))
        XCTAssertTrue(filter.userMap.isEmpty)
        XCTAssertEqual(filter.lastLoadIssue, message)
    }

    func testLoadUserDictionaryRejectsNormalizedDuplicateRulesFromJSON() throws {
        let url = try makeTemporaryDictionaryURL()
        try writeDictionary(
            [
                "open claw": "OpenClaw",
                "Open Claw": "OpenClaw Pro",
            ],
            to: url
        )

        let filter = DictionaryFilter(
            builtinMap: [:],
            notificationCenter: NotificationCenter(),
            dictionaryURLProvider: { url }
        )

        let result = filter.loadUserDictionary()

        guard case .failure(let message) = result else {
            return XCTFail("Expected normalized duplicate JSON rules to fail loading")
        }
        XCTAssertTrue(message.contains("冲突"))
        XCTAssertTrue(filter.userMap.isEmpty)
        XCTAssertEqual(filter.lastLoadIssue, message)
    }

    func testSaveUserDictionaryRejectsInvalidRulesBeforeWriting() throws {
        let url = try makeTemporaryDictionaryURL()
        let filter = DictionaryFilter(
            builtinMap: [:],
            notificationCenter: NotificationCenter(),
            dictionaryURLProvider: { url }
        )

        XCTAssertThrowsError(try filter.saveUserDictionary(["": "OpenClaw"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("左侧错误词不能为空"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(filter.userMap.isEmpty)
    }

    func testWorkbenchEvaluatesPhraseAgainstEditableRules() {
        let evaluation = DictionaryWorkbench.evaluate(
            phrase: "open claw and type script",
            rulesText: "open claw -> OpenClaw\n"
        )

        XCTAssertTrue(evaluation.canEvaluate)
        XCTAssertEqual(evaluation.outputText, "OpenClaw and TypeScript")
        XCTAssertEqual(evaluation.matchSummary, "type script → TypeScript, open claw → OpenClaw")
    }

    func testWorkbenchReportsRuleErrorsInsteadOfApplyingInvalidRules() {
        let evaluation = DictionaryWorkbench.evaluate(
            phrase: "open claw",
            rulesText: "broken rule"
        )

        XCTAssertFalse(evaluation.canEvaluate)
        XCTAssertTrue(evaluation.outputText.isEmpty)
        XCTAssertTrue(evaluation.matchSummary.contains("第 1 行"))
    }
}
