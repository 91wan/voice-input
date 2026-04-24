import XCTest
@testable import VoiceInput

final class DictionaryFilterTests: XCTestCase {
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
}
