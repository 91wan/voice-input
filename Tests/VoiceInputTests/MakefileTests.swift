import Foundation
import XCTest

final class MakefileTests: XCTestCase {
    func testMakefileDoesNotRunSwiftBuildDuringParse() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertFalse(
            makefile.contains("BUILD_DIR := $(shell swift build"),
            "Makefile variables must not run swift build at parse time; targets like clean should stay side-effect free until their recipe runs."
        )
    }

    func testBuildRecipeFailsFastBeforePackagingAppBundle() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("build:\n\t@set -e; \\"),
            "make build must stop immediately if swift build fails, otherwise it can package a stale executable from a previous successful build."
        )
    }

    func testVersionBumpFailsFastDuringVersionWrites() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("\t@set -e; \\\n\tVERSION_NO_V=$${VERSION#v}; \\"),
            "version-bump must stop on the first failed README or plist update so it never commits or tags a partial release bump."
        )
    }
}
