import Foundation
import XCTest

final class ReleaseWorkflowTests: XCTestCase {
    func testReleaseNotesExtractionUsesExactTagMatch() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        XCTAssertTrue(
            workflow.contains("awk -v tag=\"$TAG\""),
            "Release notes extraction should pass the tag as an awk variable instead of interpolating it into a regex."
        )
        XCTAssertTrue(
            workflow.contains("heading == tag"),
            "Release notes extraction must compare normalized changelog headings exactly so v1.0.1 cannot match v1.0.10."
        )
        XCTAssertFalse(
            workflow.contains("awk \"/^## \\[?${TAG}\\]?/"),
            "The old regex prefix match can extract notes from the wrong changelog section."
        )
    }

    func testWorkflowUsesNode24CompatibleActions() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        XCTAssertTrue(
            workflow.contains("uses: actions/checkout@v6"),
            "CI should use the Node 24-compatible checkout action line to avoid GitHub Actions Node 20 deprecation warnings."
        )
        XCTAssertTrue(
            workflow.contains("uses: softprops/action-gh-release@v3"),
            "Release publishing should use the Node 24-compatible action-gh-release line."
        )
        XCTAssertFalse(
            workflow.contains("uses: actions/checkout@v4"),
            "actions/checkout@v4 runs on Node 20 and will reintroduce deprecation warnings."
        )
        XCTAssertFalse(
            workflow.contains("uses: softprops/action-gh-release@v2"),
            "softprops/action-gh-release@v2 runs on Node 20 and will reintroduce deprecation warnings."
        )
    }
}
