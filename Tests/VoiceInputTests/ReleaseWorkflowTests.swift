import Foundation
import XCTest

final class ReleaseWorkflowTests: XCTestCase {
    func testReleaseWorkflowTestsAvoidHistoricalVersionFunctionNames() throws {
        let source = try String(contentsOfFile: "Tests/VoiceInputTests/ReleaseWorkflowTests.swift", encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"func\s+test\w*ReleaseNotesArePublishedForV"#)
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)

        XCTAssertNil(
            regex.firstMatch(in: source, range: sourceRange),
            "Release workflow tests should verify current metadata and workflow structure, not hard-code one test per historical release."
        )
    }

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

    func testReleaseNotesMissingForTagFailsClosed() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        XCTAssertFalse(
            workflow.contains("NOTES=\"Release ${TAG}\""),
            "Release workflow must not publish placeholder release notes when changelog notes are missing."
        )
        XCTAssertTrue(
            workflow.contains("::error::CHANGELOG.md missing release notes for ${TAG}"),
            "Release workflow should emit an actionable changelog error."
        )
        XCTAssertTrue(
            workflow.contains("exit 1"),
            "Release workflow should fail closed instead of publishing empty notes."
        )
    }

    func testReadmesDocumentMakeCIAsLocalGate() throws {
        let readmePaths = [
            "README.md",
            "README.zh-CN.md",
            "README.ja.md",
            "README.ko.md",
        ]

        for path in readmePaths {
            let readme = try String(contentsOfFile: path, encoding: .utf8)

            XCTAssertTrue(readme.contains("make ci"), "\(path) should document make ci as the full local gate.")
            XCTAssertTrue(readme.contains("Resources/AppIcon.icns"), "\(path) should document the required icon input.")
        }

        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        XCTAssertTrue(englishReadme.contains("Run unit tests only:"))
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

    func testReleaseDMGIncludesApplicationsShortcut() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let packageScript = try String(contentsOfFile: "scripts/package-dmg.sh", encoding: .utf8)

        XCTAssertTrue(
            workflow.contains("./scripts/package-dmg.sh"),
            "Release workflow should use the shared packaging script so local and CI DMGs have the same install layout."
        )
        XCTAssertTrue(
            packageScript.contains("ln -s /Applications \"$STAGING_DIR/Applications\""),
            "The DMG staging folder must include an /Applications shortcut for drag-to-install."
        )
        XCTAssertTrue(
            packageScript.contains("-srcfolder \"$STAGING_DIR\""),
            "The layout source DMG must be created from the staging folder that contains the app and Applications shortcut."
        )
    }

    func testReleaseDMGWritesFinderLayout() throws {
        let packageScript = try String(contentsOfFile: "scripts/package-dmg.sh", encoding: .utf8)

        XCTAssertTrue(
            packageScript.contains(".DS_Store"),
            "The DMG should persist Finder layout metadata instead of relying on default icon view."
        )
        XCTAssertTrue(
            packageScript.contains("set icon size of icon view options of container window of dmgFolder to 128"),
            "The DMG Finder view should use larger 128 point icons."
        )
        XCTAssertTrue(
            packageScript.contains("set arrangement of icon view options of container window of dmgFolder to not arranged"),
            "Finder should not auto-sort the DMG icons after explicit positioning."
        )
        XCTAssertTrue(
            packageScript.contains("set position of item \"VoiceInput.app\" of dmgFolder to {200, 180}"),
            "VoiceInput.app should be on the left side of the install window."
        )
        XCTAssertTrue(
            packageScript.contains("set position of item \"Applications\" of dmgFolder to {520, 180}"),
            "Applications should be on the right side of the install window."
        )
    }

    func testVersionMetadataIsConsistentAcrossSourceFiles() throws {
        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let readmeVersion = try XCTUnwrap(Self.firstCapture(in: englishReadme, pattern: #"version-v([0-9]+\.[0-9]+\.[0-9]+)"#))
        let expectedTag = "v\(readmeVersion)"

        let rootPlist = NSDictionary(contentsOf: URL(fileURLWithPath: "Info.plist"))
        XCTAssertEqual(rootPlist?["CFBundleShortVersionString"] as? String, String(readmeVersion))
        XCTAssertEqual(rootPlist?["CFBundleVersion"] as? String, String(readmeVersion))

        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        XCTAssertTrue(
            changelog.contains("## [\(expectedTag)]"),
            "CHANGELOG.md must contain release notes for the README/Info.plist version."
        )
    }

    func testCurrentChangelogSectionIsPresentAndNonEmpty() throws {
        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let readmeVersion = try XCTUnwrap(Self.firstCapture(in: englishReadme, pattern: #"version-v([0-9]+\.[0-9]+\.[0-9]+)"#))
        let section = try XCTUnwrap(Self.changelogSection(for: "v\(readmeVersion)"))

        XCTAssertTrue(
            section.contains("- "),
            "The current release changelog section should contain user-facing bullets for release notes."
        )
        XCTAssertFalse(section.localizedCaseInsensitiveContains("todo"))
    }

    func testGeneratedAppBundleIsIgnored() throws {
        let gitignore = try String(contentsOfFile: ".gitignore", encoding: .utf8)

        XCTAssertTrue(
            gitignore.components(separatedBy: .newlines).contains("VoiceInput.app/"),
            ".gitignore must ignore the full generated app bundle."
        )
        XCTAssertTrue(
            gitignore.components(separatedBy: .newlines).contains("*.dmg"),
            ".gitignore must ignore generated DMG artifacts."
        )
        XCTAssertFalse(
            gitignore.contains("VoiceInput.app/Contents/MacOS/VoiceInput"),
            "Ignoring only selected files inside the app bundle can still leave tracked generated metadata."
        )
    }

    func testReleaseWorkflowValidatesUnsignedDMGArtifactBeforePublishing() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let verifier = try String(contentsOfFile: "scripts/verify-dmg.sh", encoding: .utf8)

        XCTAssertTrue(workflow.contains("./scripts/verify-dmg.sh VoiceInput.dmg \"$VERSION\" VoiceInput"))
        XCTAssertTrue(workflow.contains("VERSION=\"${GITHUB_REF_NAME#v}\""))
        XCTAssertTrue(verifier.contains("test -d \"$MOUNT_DIR/VoiceInput.app\""))
        XCTAssertTrue(verifier.contains("readlink \"$MOUNT_DIR/Applications\""))
        XCTAssertTrue(verifier.contains("test -f \"$MOUNT_DIR/.DS_Store\""))
        XCTAssertTrue(verifier.contains("CFBundleShortVersionString"))
        XCTAssertTrue(verifier.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(verifier.contains("spctl -a -vvv -t execute"))
        XCTAssertTrue(verifier.contains("grep -qi \"rejected\""))
    }

    func testReleaseWorkflowUsesMakeCIGate() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let checklist = try String(contentsOfFile: "docs/release-qa-checklist.md", encoding: .utf8)

        XCTAssertTrue(
            workflow.contains("- name: Run CI gate\n        run: make ci"),
            "The release workflow test job should call the same make ci gate developers run locally."
        )
        XCTAssertFalse(
            workflow.contains("run: swift test\n"),
            "The workflow should not use a weaker test command than the release checklist."
        )
        XCTAssertTrue(
            checklist.contains("`make ci`"),
            "The release checklist should name make ci as the local automated gate."
        )
    }

    func testPullRequestsToMainRunCIGateBeforeMerge() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        XCTAssertTrue(
            workflow.contains("pull_request:\n    branches:\n      - main"),
            "Pull requests should run the test job before merge instead of waiting for main push."
        )
    }

    func testWorkflowUsesReadOnlyTopLevelPermissionsAndWriteOnlyForRelease() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        XCTAssertTrue(
            workflow.contains("permissions:\n  contents: read"),
            "Workflow default permissions should be read-only."
        )
        XCTAssertTrue(
            workflow.contains("release:\n    name:") &&
            workflow.contains("    permissions:\n      contents: write"),
            "Only the release job should request write permission for publishing GitHub Releases."
        )
    }

    func testMainPushDoesNotAutoCommitReadmeDate() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)

        XCTAssertFalse(
            workflow.contains("auto-doc:"),
            "Main branch pushes should not run an auto-doc job that creates follow-up README date commits."
        )
        XCTAssertFalse(
            workflow.contains("Update README date"),
            "README date updates should be explicit release metadata changes, not automatic push side effects."
        )
        XCTAssertFalse(
            workflow.contains("git push"),
            "The release workflow should not push automatic documentation commits back to main."
        )
    }

    func testUnreleasedChangelogSectionDocumentsPostReleaseChanges() throws {
        let section = try XCTUnwrap(Self.changelogSection(for: "Unreleased"))

        XCTAssertTrue(
            section.contains("- "),
            "Unreleased should capture post-release changes before the next version bump."
        )
        XCTAssertFalse(section.localizedCaseInsensitiveContains("todo"))
    }

    func testDMGVerifierChecksAppIconExistsAndIsNonEmpty() throws {
        let verifier = try String(contentsOfFile: "scripts/verify-dmg.sh", encoding: .utf8)

        XCTAssertTrue(verifier.contains("VoiceInput.app/Contents/Resources/AppIcon.icns"))
        XCTAssertTrue(verifier.contains("test -s"))
    }

    func testReleaseQAChecklistDocumentsV12ManualCoverage() throws {
        let checklist = try String(contentsOfFile: "docs/release-qa-checklist.md", encoding: .utf8)

        XCTAssertTrue(checklist.contains("Stable Release Gate"))
        XCTAssertTrue(checklist.contains("Install / first launch / permission / Fn / Option + Fn"))
        XCTAssertTrue(checklist.contains("Fn + normal key"))
        XCTAssertTrue(checklist.contains("Option + Fn"))
        XCTAssertTrue(checklist.contains("Accessibility enabled but Input Monitoring missing"))
        XCTAssertTrue(checklist.contains("LLM disabled"))
        XCTAssertTrue(checklist.contains("Developer ID signing and notarization are out of scope"))
    }

    private static func firstCapture(in text: String, pattern: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func changelogSection(for tag: String) throws -> String? {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        guard let headingRange = changelog.range(of: "## [\(tag)]") else {
            return nil
        }

        let sectionStart = headingRange.upperBound
        let remainingText = changelog[sectionStart...]
        let sectionEnd = remainingText.range(of: "\n## ")?.lowerBound ?? changelog.endIndex
        return String(changelog[sectionStart..<sectionEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
