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
            makefile.contains("test -s \"$(APP_ICON_SOURCE)\""),
            "make ci must fail fast if the declared app icon source is missing or empty."
        )
        XCTAssertTrue(
            makefile.contains("APP_ICON_MASTER := Resources/AppIcon-master.png"),
            "The canonical app icon master should have one declared source path."
        )
        XCTAssertTrue(
            makefile.contains("test -s \"$(APP_ICON_MASTER)\""),
            "make ci must fail fast if the canonical app icon master is missing or empty."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/verify-app-icon.sh"),
            "make ci should require the focused app icon verifier to remain executable."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/run-finder-applescript.sh"),
            "make ci should catch a missing Finder AppleScript helper executable bit before release jobs."
        )
        XCTAssertTrue(
            makefile.contains("./scripts/verify-app-icon.sh \"$(APP_ICON_SOURCE)\" \"$(APP_ICON_MASTER)\""),
            "make ci must validate the ICNS container and canonical master before Swift verification."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/package-dmg.sh"),
            "make ci should catch a missing package-dmg executable bit before tag-only release jobs."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/verify-dmg.sh"),
            "make ci should catch a missing verify-dmg executable bit before tag-only release jobs."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/verify-dmg-layout.sh"),
            "make ci should catch a missing DMG layout verifier executable bit before tag-only release jobs."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/extract-release-notes.sh"),
            "make ci should catch a missing release-notes executable bit before tag-only release jobs."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/check-version-bump-source-state.sh"),
            "make ci should catch a missing version-bump source-state preflight executable bit before releases."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/check-version-bump-branch-state.sh"),
            "make ci should catch a missing version-bump branch-state preflight executable bit before releases."
        )
        XCTAssertTrue(
            makefile.contains("test -x scripts/check-version-bump-tag-state.sh"),
            "make ci should catch a missing version-bump tag-state preflight executable bit before releases."
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
        XCTAssertTrue(makefile.contains("./scripts/package-dmg.sh \"$(APP_BUNDLE)\" \"$(DMG_PATH)\" \"$(APP_NAME)\""))
        XCTAssertTrue(makefile.contains("verify-dmg:"))
        XCTAssertTrue(makefile.contains("./scripts/verify-dmg.sh \"$(DMG_PATH)\" \"$(VERSION)\" \"$(APP_NAME)\""))
        XCTAssertFalse(
            makefile.contains("release-artifact: package-dmg verify-dmg"),
            "release-artifact must not list package and verify as parallel prerequisites; make -j can verify before packaging finishes."
        )
        XCTAssertTrue(
            makefile.contains("release-artifact:\n\t@set -e; \\"),
            "release-artifact should use an explicit sequential recipe."
        )
        XCTAssertTrue(
            makefile.contains("$(MAKE) package-dmg DMG_PATH=\"$(DMG_PATH)\"") &&
            makefile.contains("$(MAKE) verify-dmg VERSION=\"$(VERSION)\" DMG_PATH=\"$(DMG_PATH)\""),
            "release-artifact should package first, then verify the same DMG path."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: "$(MAKE) package-dmg DMG_PATH=\"$(DMG_PATH)\"")?.lowerBound),
            try XCTUnwrap(makefile.range(of: "$(MAKE) verify-dmg VERSION=\"$(VERSION)\" DMG_PATH=\"$(DMG_PATH)\"")?.lowerBound),
            "release-artifact should call package before verify."
        )
        XCTAssertTrue(makefile.contains("release-check: ci"))
        XCTAssertTrue(makefile.contains("$(MAKE) release-artifact VERSION=\"$(VERSION)\" DMG_PATH=\"$(DMG_PATH)\""))
    }

    func testVersionBumpFailsFastDuringVersionWrites() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)
        let setE = "\t@set -e; \\"
        let versionAssignment = "VERSION_NO_V=$${VERSION#v}; \\"

        XCTAssertTrue(
            makefile.contains(setE),
            "version-bump must stop on the first failed README or plist update so it never commits or tags a partial release bump."
        )
        XCTAssertTrue(makefile.contains(versionAssignment))
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: setE)?.lowerBound),
            try XCTUnwrap(makefile.range(of: versionAssignment)?.lowerBound),
            "version-bump should enable set -e before mutating release metadata."
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
            makefile.contains("./scripts/extract-release-notes.sh CHANGELOG.md \"$(VERSION)\" >/dev/null"),
            "version-bump must reuse the same release-notes extractor as the GitHub Release workflow before creating a tag."
        )
        XCTAssertFalse(
            makefile.contains("awk -v tag=\"$(VERSION)\""),
            "version-bump must not keep a second inline awk changelog parser that can drift from the release workflow."
        )
        XCTAssertFalse(
            makefile.contains("CHANGELOG.md 缺少 $(VERSION) 条目"),
            "version-bump should rely on the shared release-notes extractor for missing or empty changelog sections."
        )
    }

    func testVersionBumpRunsSourceStatePreflightBeforeMetadataMutation() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)
        let preflight = "./scripts/check-version-bump-source-state.sh pre"
        let metadataMutation = "sed -i '' -e 's/version-v[0-9][0-9a-z._-]*/version-$(VERSION)/g' README.md"

        XCTAssertTrue(
            makefile.contains(preflight),
            "version-bump must verify that only CHANGELOG.md is dirty before it mutates README or Info.plist."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: preflight)?.lowerBound),
            try XCTUnwrap(makefile.range(of: metadataMutation)?.lowerBound),
            "source-state preflight must run before metadata mutation."
        )
    }

    func testVersionBumpRunsBranchStatePreflightBeforeMetadataMutation() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)
        let branchCheck = "./scripts/check-version-bump-branch-state.sh \"$(RELEASE_BRANCH)\" \"$(REMOTE)\""
        let metadataMutation = "sed -i '' -e 's/version-v[0-9][0-9a-z._-]*/version-$(VERSION)/g' README.md"

        XCTAssertTrue(
            makefile.contains("REMOTE ?= origin"),
            "version-bump should allow release maintainers to configure the remote used for branch and tag checks."
        )
        XCTAssertTrue(
            makefile.contains("RELEASE_BRANCH ?= main"),
            "version-bump should default to tagging from main unless a release maintainer explicitly configures another branch."
        )
        XCTAssertTrue(
            makefile.contains(branchCheck),
            "version-bump must verify that local HEAD matches the configured remote release branch before mutating release metadata."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: branchCheck)?.lowerBound),
            try XCTUnwrap(makefile.range(of: metadataMutation)?.lowerBound),
            "branch-state preflight must run before metadata mutation."
        )
    }

    func testVersionBumpChecksTagStateBeforeMetadataMutation() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)
        let tagCheck = "./scripts/check-version-bump-tag-state.sh \"$(VERSION)\" \"$(REMOTE)\""
        let metadataMutation = "sed -i '' -e 's/version-v[0-9][0-9a-z._-]*/version-$(VERSION)/g' README.md"

        XCTAssertTrue(
            makefile.contains(tagCheck),
            "version-bump must reject local and remote tag collisions before mutating release metadata."
        )
        XCTAssertFalse(
            makefile.contains("./scripts/check-version-bump-tag-state.sh \"$(VERSION)\" origin"),
            "version-bump must pass $(REMOTE) into the tag-state preflight instead of hard-coding origin."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: tagCheck)?.lowerBound),
            try XCTUnwrap(makefile.range(of: metadataMutation)?.lowerBound),
            "tag-state preflight must run before metadata mutation."
        )
        XCTAssertFalse(
            makefile.contains("git rev-parse -q --verify \"refs/tags/$(VERSION)\" >/dev/null"),
            "tag collision checks should live in the executable tag-state preflight instead of growing inline Makefile shell."
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

        XCTAssertTrue(
            makefile.contains("git add README.md Info.plist CHANGELOG.md"),
            "version-bump must stage the changelog entry with the README and source Info.plist so the tag commit contains release notes."
        )
        XCTAssertFalse(
            makefile.contains("VoiceInput.app/Contents/Info.plist"),
            "version-bump must only update source metadata; generated app bundle plists are build artifacts."
        )
        XCTAssertFalse(
            makefile.contains("git add README.md Info.plist VoiceInput.app"),
            "version-bump must not stage generated app bundle files."
        )
        XCTAssertFalse(
            makefile.contains("git add README.md Info.plist CHANGELOG.md VoiceInput.app"),
            "version-bump must not stage generated app bundle files with the source release metadata."
        )
        XCTAssertFalse(
            makefile.contains("git add README.md Info.plist CHANGELOG.md VoiceInput.dmg"),
            "version-bump must not stage generated DMG artifacts."
        )
        XCTAssertFalse(
            makefile.contains("git add README.md Info.plist CHANGELOG.md .build"),
            "version-bump must not stage SwiftPM build artifacts."
        )
    }

    func testVersionBumpRunsReleaseCheckBeforeCommitAndTag() throws {
        let makefile = try String(contentsOfFile: "Makefile", encoding: .utf8)
        let releaseCheck = "\"$${MAKE:-make}\" release-check VERSION=\"$$VERSION_NO_V\" DMG_PATH=\"/tmp/VoiceInput-$(VERSION).dmg\""
        let postCheck = "./scripts/check-version-bump-source-state.sh post"
        let commit = "git commit -m \"chore: bump version to $(VERSION)\""
        let tag = "git tag $(VERSION)"

        XCTAssertTrue(
            makefile.contains(releaseCheck),
            "version-bump must run the full local release gate after metadata is updated and before creating a release tag."
        )
        XCTAssertFalse(
            makefile.contains("$(MAKE) release-check VERSION=\"$$VERSION_NO_V\" DMG_PATH=\"/tmp/VoiceInput-$(VERSION).dmg\""),
            "version-bump must not put direct $(MAKE) release-check in a recipe line with metadata writes, because `make -n` executes recursive make lines."
        )
        XCTAssertFalse(
            makefile.contains("MAKE_CMD=\"$(MAKE)\""),
            "version-bump must not hide $(MAKE) in a shell assignment, because make still treats that recipe line as recursive during `make -n`."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: releaseCheck)?.lowerBound),
            try XCTUnwrap(makefile.range(of: commit)?.lowerBound),
            "release-check must run before git commit so failing verification cannot create a bump commit."
        )
        XCTAssertTrue(
            makefile.contains(postCheck),
            "version-bump must verify that release-check left only release metadata files dirty before staging the commit."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: postCheck)?.lowerBound),
            try XCTUnwrap(makefile.range(of: "git add README.md Info.plist CHANGELOG.md")?.lowerBound),
            "post release-check source-state validation must run before git add."
        )
        XCTAssertLessThan(
            try XCTUnwrap(makefile.range(of: releaseCheck)?.lowerBound),
            try XCTUnwrap(makefile.range(of: tag)?.lowerBound),
            "release-check must run before git tag so failing verification cannot create a release tag."
        )
    }

    func testVersionBumpRejectsExistingLocalTag() throws {
        let tagScript = try String(contentsOfFile: "scripts/check-version-bump-tag-state.sh", encoding: .utf8)

        XCTAssertTrue(
            tagScript.contains("git rev-parse -q --verify \"refs/tags/${VERSION}\" >/dev/null"),
            "version-bump must check for an existing local tag before modifying release metadata."
        )
        XCTAssertTrue(
            tagScript.contains("Tag ${VERSION} already exists locally"),
            "version-bump should fail with a clear tag collision message."
        )
        XCTAssertFalse(
            tagScript.contains("git rev-parse -q --verify \"refs/tags/${VERSION}\" >/dev/null &&"),
            "version-bump should not use a tag check form that can hide unrelated shell errors behind `|| true`."
        )
        XCTAssertTrue(
            tagScript.contains("git ls-remote --exit-code --tags \"${REMOTE}\" \"refs/tags/${VERSION}\""),
            "version-bump must fail closed when the remote already has the release tag."
        )
    }
}
