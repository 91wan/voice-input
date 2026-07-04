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

    func testBuildRecipeCopiesIconFromSourceResources() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("APP_ICON_SOURCE := Resources/AppIcon.icns"),
            "The source icon should live outside the generated app bundle."
        )
        XCTAssertTrue(
            makefile.contains("cp \"$(APP_ICON_SOURCE)\" \"$(APP_ICON)\""),
            "make build must copy the source icon into the generated app bundle."
        )
    }

    func testBuildFailsWhenSourceIconMissingOrEmpty() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("test -s \"$(APP_ICON_SOURCE)\""),
            "make build should fail fast when the declared icon source is missing or empty."
        )
        XCTAssertTrue(
            makefile.contains("Missing or empty $(APP_ICON_SOURCE)"),
            "make build should explain the icon failure clearly."
        )
        XCTAssertFalse(
            makefile.contains("app will build without a custom icon"),
            "make build should not create release-incompatible bundles with a warning-only icon path."
        )
    }

    func testCleanRemovesGeneratedBundleAndDMG() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("rm -rf $(APP_BUNDLE)"),
            "make clean must remove the entire generated app bundle, not just the executable."
        )
        XCTAssertTrue(
            makefile.contains("rm -f $(APP_NAME).dmg"),
            "make clean should remove the generated DMG artifact."
        )
    }

    func testCIGateRunsDocumentedLocalVerification() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(
            makefile.contains("test -s $(APP_ICON_SOURCE)"),
            "make ci must fail fast if the declared app icon source is missing or empty."
        )
        XCTAssertTrue(
            makefile.contains("ci:\n\t@set -e; \\"),
            "Makefile should expose a single ci target for local and GitHub verification."
        )
        XCTAssertTrue(
            makefile.contains("swift test --parallel"),
            "make ci must run the same parallel test command documented in the release checklist."
        )
        XCTAssertTrue(
            makefile.contains("swift build -Xswiftc -warnings-as-errors"),
            "make ci must fail on Swift warnings before release packaging."
        )
        XCTAssertTrue(
            makefile.contains("$(MAKE) build"),
            "make ci must build the signed app bundle through the existing build target."
        )
    }

    func testReleaseCheckPackagesAndVerifiesDMGArtifact() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertTrue(makefile.contains("DMG_PATH ?= VoiceInput.dmg"))
        XCTAssertTrue(makefile.contains("VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"))
        XCTAssertTrue(makefile.contains("package-dmg: build"))
        XCTAssertTrue(makefile.contains("./scripts/package-dmg.sh $(APP_BUNDLE) $(DMG_PATH) $(APP_NAME)"))
        XCTAssertTrue(makefile.contains("verify-dmg:"))
        XCTAssertTrue(makefile.contains("./scripts/verify-dmg.sh $(DMG_PATH) \"$(VERSION)\" $(APP_NAME)"))
        XCTAssertTrue(makefile.contains("release-artifact: package-dmg verify-dmg"))
        XCTAssertTrue(makefile.contains("release-check: ci"))
        XCTAssertTrue(makefile.contains("$(MAKE) release-artifact VERSION=\"$(VERSION)\" DMG_PATH=\"$(DMG_PATH)\""))
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

    func testVersionBumpDoesNotEditGeneratedAppBundle() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)

        XCTAssertFalse(
            makefile.contains("VoiceInput.app/Contents/Info.plist"),
            "version-bump must only update source metadata; generated app bundle plists are build artifacts."
        )
        XCTAssertFalse(
            makefile.contains("git add README.md Info.plist VoiceInput.app"),
            "version-bump must not stage generated app bundle files."
        )
    }
}
