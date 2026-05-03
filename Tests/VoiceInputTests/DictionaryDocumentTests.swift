import XCTest
@testable import VoiceInput

final class DictionaryDocumentTests: XCTestCase {
    func testImportValidRulesReturnsNormalizedEditableText() throws {
        let result = try DictionaryDocument.importText(
            """
            # exported from another machine
            open claw -> OpenClaw
            type script → TypeScript
            """
        )

        XCTAssertEqual(result.dictionary, [
            "open claw": "OpenClaw",
            "type script": "TypeScript",
        ])
        XCTAssertEqual(
            result.rulesText,
            """
            open claw → OpenClaw
            type script → TypeScript
            """
        )
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testImportInvalidRulesThrowsWithoutReturningPartialDictionary() {
        XCTAssertThrowsError(
            try DictionaryDocument.importText(
                """
                open claw -> OpenClaw
                malformed rule
                """
            )
        ) { error in
            guard case DictionaryDocumentError.invalidRules(let summary) = error else {
                return XCTFail("Expected invalidRules, got \(error)")
            }
            XCTAssertTrue(summary.contains("第 2 行"))
        }
    }

    func testImportDuplicateRulesKeepsLastValueAndExposesWarnings() throws {
        let result = try DictionaryDocument.importText(
            """
            open claw -> OpenClaw
            Open Claw -> OpenClaw Pro
            """
        )

        XCTAssertEqual(result.dictionary, ["Open Claw": "OpenClaw Pro"])
        XCTAssertEqual(result.rulesText, "Open Claw → OpenClaw Pro")
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testExportInvalidRulesThrowsInsteadOfWritingAmbiguousText() {
        XCTAssertThrowsError(try DictionaryDocument.exportText("broken rule")) { error in
            guard case DictionaryDocumentError.invalidRules(let summary) = error else {
                return XCTFail("Expected invalidRules, got \(error)")
            }
            XCTAssertTrue(summary.contains("第 1 行"))
        }
    }

    func testExportValidRulesUsesExistingDictionarySerialization() throws {
        let exported = try DictionaryDocument.exportText(
            """
            type script -> TypeScript
            open claw -> OpenClaw
            """
        )

        XCTAssertEqual(
            exported,
            """
            open claw → OpenClaw
            type script → TypeScript
            """
        )
    }

    func testExportDuplicateRulesReturnsNormalizedTextAndWarnings() throws {
        let result = try DictionaryDocument.export(
            """
            open claw -> OpenClaw
            Open Claw -> OpenClaw Pro
            """
        )

        XCTAssertEqual(result.rulesText, "Open Claw → OpenClaw Pro")
        XCTAssertEqual(result.warnings.count, 1)
    }
}
