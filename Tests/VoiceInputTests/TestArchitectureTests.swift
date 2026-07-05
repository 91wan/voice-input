import Foundation
import XCTest

final class TestArchitectureTests: XCTestCase {
    func testVoiceInputTestsDoNotReadProductionSwiftSources() throws {
        let testDirectory = URL(fileURLWithPath: "Tests/VoiceInputTests", isDirectory: true)
        let swiftFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: testDirectory,
                includingPropertiesForKeys: nil
            )?.compactMap { item -> URL? in
                guard let file = item as? URL, file.pathExtension == "swift" else { return nil }
                return file
            }.sorted { $0.path < $1.path }
        )

        let violations = try swiftFiles.flatMap { file -> [String] in
            let source = try String(contentsOf: file, encoding: .utf8)
            return Self.productionSwiftSourceTextReadViolations(in: source).map { "\(file.path): \($0)" }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Tests must not validate production Swift behavior by reading Sources/VoiceInput/*.swift as text.
            Use value objects, small policy seams, internal/public behavior seams, or real behavior tests instead.
            Violations:
            \(Set(violations).sorted().joined(separator: "\n"))
            """
        )
    }

    func testProductionSwiftSourceTextReadGuardRejectsCommonBypasses() {
        let productionSourcePath = "Sources/" + "VoiceInput/" + "LLMRefiner.swift"
        let forbiddenSamples = [
            #"String(contentsOfFile: ""# + productionSourcePath + #"", encoding: .utf8)"#,
            #"String(contentsOf: URL(fileURLWithPath: ""# + productionSourcePath + #""))"#,
            #"Data(contentsOf: URL(fileURLWithPath: ""# + productionSourcePath + #""))"#,
            #"FileManager.default.contents(atPath: ""# + productionSourcePath + #"")"#,
            #"let url = URL(fileURLWithPath: ""# + productionSourcePath + #"")"#,
        ]

        for sample in forbiddenSamples {
            XCTAssertFalse(
                Self.productionSwiftSourceTextReadViolations(in: sample).isEmpty,
                "Expected guard to reject: \(sample)"
            )
        }
    }

    func testProductionSwiftSourceTextReadGuardRejectsSplitPathBypasses() {
        let productionSourcePath = "Sources/" + "VoiceInput/" + "LLMRefiner.swift"
        let forbiddenSamples = [
            """
            let path = "\(productionSourcePath)"
            let url = URL(fileURLWithPath: path)
            let source = try String(contentsOf: url, encoding: .utf8)
            """,
            """
            let path = "\(productionSourcePath)"
            let data = FileManager.default.contents(atPath: path)
            """,
        ]

        for sample in forbiddenSamples {
            XCTAssertFalse(
                Self.productionSwiftSourceTextReadViolations(in: sample).isEmpty,
                "Expected guard to reject split path bypass: \(sample)"
            )
        }
    }

    func testProductionSwiftSourceTextReadGuardAllowsTextAssetTests() {
        let allowedSamples = [
            #"String(contentsOfFile: "README.md", encoding: .utf8)"#,
            #"String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)"#,
            #"String(contentsOfFile: "Makefile", encoding: .utf8)"#,
            #"String(contentsOfFile: "scripts/package-dmg.sh", encoding: .utf8)"#,
            #"String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)"#,
            #"String(contentsOfFile: "docs/release-qa-checklist.md", encoding: .utf8)"#,
        ]

        for sample in allowedSamples {
            XCTAssertTrue(
                Self.productionSwiftSourceTextReadViolations(in: sample).isEmpty,
                "Expected guard to allow: \(sample)"
            )
        }
    }

    private static func productionSwiftSourceTextReadViolations(in source: String) -> [String] {
        let sourcePath = "Sources/" + "VoiceInput/"
        let textReadFragments = [
            "String(contentsOfFile:",
            "String(contentsOf:",
            "Data(contentsOf:",
            "contents(atPath:",
        ]
        let fileURLFragment = "URL(" + "fileURLWithPath:"

        var productionPathNames = Set<String>()
        var productionURLNames = Set<String>()
        var violations: [String] = []

        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let text = String(line)
            let lineHasProductionPath = text.contains(sourcePath)

            if lineHasProductionPath, let assignedName = assignedName(in: text) {
                productionPathNames.insert(assignedName)
            }

            if lineHasProductionPath {
                violations += textReadFragments
                    .filter { text.contains($0) }
                    .map { "line \(lineNumber): \($0)" }
                if text.contains(fileURLFragment) {
                    violations.append("line \(lineNumber): \(fileURLFragment)")
                }
            }

            if text.contains(fileURLFragment),
               productionPathNames.contains(where: { text.contains($0) }) {
                violations.append("line \(lineNumber): \(fileURLFragment) with production source path variable")
                if let assignedName = assignedName(in: text) {
                    productionURLNames.insert(assignedName)
                }
            }

            for fragment in textReadFragments where text.contains(fragment) {
                if productionPathNames.contains(where: { text.contains($0) }) {
                    violations.append("line \(lineNumber): \(fragment) with production source path variable")
                }
                if productionURLNames.contains(where: { text.contains($0) }) {
                    violations.append("line \(lineNumber): \(fragment) with production source URL variable")
                }
            }
        }

        return Array(Set(violations)).sorted()
    }

    private static func assignedName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["let ", "var "]
        guard let prefix = prefixes.first(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }

        let remainder = trimmed.dropFirst(prefix.count)
        let name = remainder.prefix { character in
            character.isLetter || character.isNumber || character == "_"
        }
        return name.isEmpty ? nil : String(name)
    }
}
