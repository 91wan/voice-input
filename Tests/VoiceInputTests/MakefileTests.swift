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

    func testVersionBumpRequiresTagThatTriggersReleaseWorkflow() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("case \"$(VERSION)\" in v*) ;; *)"),
            "version-bump must reject versions that do not start with v, because only v* tags trigger the release workflow."
        )
        XCTAssertTrue(
            makefile.contains("\t\tesac"),
            "version-bump's v* guard must close the shell case statement with esac."
        )
    }

    func testVersionBumpRequiresSemanticVersionShape() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("grep -Eq '^v[0-9]+\\.[0-9]+\\.[0-9]+$$'"),
            "version-bump must reject malformed v* tags like v, because they produce empty or invalid bundle versions."
        )
    }

    func testVersionBumpRequiresMatchingChangelogEntryBeforeTagging() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("awk -v tag=\"$(VERSION)\""),
            "version-bump must verify CHANGELOG.md has notes for the exact version before creating a tag."
        )
        XCTAssertTrue(
            makefile.contains("CHANGELOG.md 缺少 $(VERSION) 条目"),
            "version-bump should fail with an actionable message when patch or minor release notes are missing."
        )
    }

    func testVersionBumpDoesNotRewriteCommandNameInReadme() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("s/version-v[0-9][0-9a-z._-]*/version-$(VERSION)/g"),
            "version-bump should update the README version badge without matching the literal command name `version-bump`."
        )
        XCTAssertFalse(
            makefile.contains("s/version-[0-9a-z._-]*/version-$(VERSION)/g"),
            "A broad version-* replacement corrupts README examples like `make version-bump VERSION=v1.0.2`."
        )
    }
}
