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

        let productionSourcePrefix = "Sources/" + "VoiceInput/"
        let forbiddenNeedles = [
            #"String(contentsOfFile: ""# + productionSourcePrefix,
            #"String(contentsOfFile: \""# + productionSourcePrefix,
            #"contentsOfFile: ""# + productionSourcePrefix,
        ]

        let violations = try swiftFiles.flatMap { file -> [String] in
            let source = try String(contentsOf: file, encoding: .utf8)
            return forbiddenNeedles.compactMap { needle in
                source.contains(needle) ? file.path : nil
            }
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
}
