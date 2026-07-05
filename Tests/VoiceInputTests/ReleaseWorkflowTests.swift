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
            workflow.contains("./scripts/extract-release-notes.sh CHANGELOG.md \"$TAG\""),
            "Release notes extraction should use the shared script so exact-match behavior is tested locally."
        )
        XCTAssertFalse(workflow.contains("awk -v tag=\"$TAG\""))
        XCTAssertFalse(
            workflow.contains("awk \"/^## \\[?${TAG}\\]?/"),
            "The old regex prefix match can extract notes from the wrong changelog section."
        )
    }

    func testReleaseNotesMissingForTagFailsClosed() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let script = try String(contentsOfFile: "scripts/extract-release-notes.sh", encoding: .utf8)

        XCTAssertFalse(
            workflow.contains("NOTES=\"Release ${TAG}\""),
            "Release workflow must not publish placeholder release notes when changelog notes are missing."
        )
        XCTAssertTrue(
            script.contains("CHANGELOG.md missing release notes for ${TAG}"),
            "Release workflow should emit an actionable changelog error."
        )
        XCTAssertTrue(
            workflow.contains("NOTES=\"$(./scripts/extract-release-notes.sh CHANGELOG.md \"$TAG\")\""),
            "Release workflow should fail closed through the release notes extraction script."
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

            XCTAssertTrue(readme.contains("make ci"), "\(path) should document make ci as the local CI gate.")
            XCTAssertTrue(readme.contains("make release-check"), "\(path) should document make release-check as the local release gate.")
            XCTAssertTrue(readme.contains("make version-bump"), "\(path) should document the version bump entry point.")
            XCTAssertTrue(readme.contains("local release gate"), "\(path) should say version-bump runs the local release gate.")
            XCTAssertTrue(readme.contains("CHANGELOG.md"), "\(path) should document that release notes are part of the version bump.")
            XCTAssertTrue(readme.localizedCaseInsensitiveContains("manual QA"), "\(path) should document that manual QA is still required for stable releases.")
            XCTAssertTrue(readme.contains("only `CHANGELOG.md`"), "\(path) should document that only CHANGELOG.md may be dirty before version-bump.")
            XCTAssertTrue(readme.contains("source/test/script/workflow"), "\(path) should require source, test, script, and workflow changes to be committed before version-bump.")
            XCTAssertTrue(readme.contains("local and remote tag collisions"), "\(path) should document local and remote tag collision checks.")
            XCTAssertTrue(readme.contains("configured release branch"), "\(path) should document the configured release branch requirement.")
            XCTAssertTrue(readme.contains("origin/main"), "\(path) should document that local HEAD must match origin/main by default.")
            XCTAssertTrue(readme.contains("REMOTE=upstream RELEASE_BRANCH=main"), "\(path) should document custom remote and branch version-bump usage.")
            XCTAssertFalse(readme.localizedCaseInsensitiveContains("full local gate"), "\(path) should not describe make ci as the full local gate.")
            XCTAssertTrue(readme.contains("Resources/AppIcon.icns"), "\(path) should document the required icon input.")
        }

        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        XCTAssertTrue(englishReadme.contains("Run unit tests only:"))
    }

    func testReadmesDocumentSettingsTestDoesNotPersistLLMConfig() throws {
        let expectationsByPath = [
            "README.md": [
                "`Test` uses the current Settings fields for one request only",
                "does not save the API key, API Base URL, or model",
                "`Save` to persist the API key to Keychain",
                "store the API Base URL / model defaults",
                "Editing fields after a test clears the test result",
                "run `Test` again to verify the current fields",
            ],
            "README.zh-CN.md": [
                "`Test` 只用当前输入框内容发起一次测试请求",
                "不会保存 API key、API Base URL 或 model",
                "只有点击 `Save` 才会把 API key 写入 Keychain",
                "保存 API Base URL / model 默认值",
                "测试后继续编辑字段会清除测试结果",
                "重新点击 `Test` 验证当前输入",
            ],
            "README.ja.md": [
                "`Test` は現在の Settings 入力欄だけを使って 1 回のテストリクエストを送信",
                "API key、API Base URL、model は保存しません",
                "`Save` をクリックしたときだけ API key を Keychain に保存",
                "API Base URL / model の既定値",
                "テスト後にフィールドを編集するとテスト結果はクリアされます",
                "現在の入力欄を確認するにはもう一度 `Test` を実行",
            ],
            "README.ko.md": [
                "`Test`는 현재 Settings 입력값만 사용해 한 번의 테스트 요청을 보냅니다",
                "API key, API Base URL, model을 저장하지 않습니다",
                "`Save`를 클릭해야 API key를 Keychain에 저장",
                "API Base URL / model 기본값",
                "테스트 후 필드를 편집하면 테스트 결과가 지워집니다",
                "현재 입력값을 확인하려면 `Test`를 다시 실행",
            ],
        ]

        for (path, expectedSnippets) in expectationsByPath {
            let readme = try String(contentsOfFile: path, encoding: .utf8)
            for snippet in expectedSnippets {
                XCTAssertTrue(readme.contains(snippet), "\(path) should document: \(snippet)")
            }
        }
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

        XCTAssertTrue(workflow.contains("make release-artifact VERSION=\"$VERSION\" DMG_PATH=VoiceInput.dmg"))
        XCTAssertFalse(workflow.contains("./scripts/package-dmg.sh VoiceInput.app VoiceInput.dmg VoiceInput"))
        XCTAssertTrue(
            packageScript.contains("ln -s /Applications \"$STAGING_DIR/Applications\""),
            "The DMG staging folder must include an /Applications shortcut for drag-to-install."
        )
        XCTAssertTrue(
            packageScript.contains("-srcfolder \"$STAGING_DIR\""),
            "The layout source DMG must be created from the staging folder that contains the app and Applications shortcut."
        )
    }

    func testReleaseDMGUsesPolishedFinderLayoutForIssue22() throws {
        let packageScript = try String(contentsOfFile: "scripts/package-dmg.sh", encoding: .utf8)

        XCTAssertTrue(
            packageScript.contains(".DS_Store"),
            "The DMG should persist Finder layout metadata instead of relying on default icon view."
        )
        let bounds = try Self.firstIntCaptures(
            in: packageScript,
            pattern: #"set bounds of container window of dmgFolder to \{([0-9]+), ([0-9]+), ([0-9]+), ([0-9]+)\}"#
        )
        let iconSize = try XCTUnwrap(Self.firstIntCapture(
            in: packageScript,
            pattern: #"set icon size of icon view options of container window of dmgFolder to ([0-9]+)"#
        ))
        let appPosition = try Self.firstIntCaptures(
            in: packageScript,
            pattern: #"set position of item "VoiceInput\.app" of dmgFolder to \{([0-9]+), ([0-9]+)\}"#
        )
        let applicationsPosition = try Self.firstIntCaptures(
            in: packageScript,
            pattern: #"set position of item "Applications" of dmgFolder to \{([0-9]+), ([0-9]+)\}"#
        )

        XCTAssertEqual(bounds.count, 4, "The DMG Finder window bounds should be explicit.")
        XCTAssertEqual(appPosition.count, 2, "The app icon position should be explicit.")
        XCTAssertEqual(applicationsPosition.count, 2, "The Applications shortcut position should be explicit.")
        guard bounds.count == 4, appPosition.count == 2, applicationsPosition.count == 2 else { return }

        XCTAssertGreaterThan(iconSize, 128, "Issue #22 requires icons visibly larger than the old 128 point layout.")
        XCTAssertGreaterThanOrEqual(iconSize, 160, "The DMG Finder view should use polished large drag targets.")
        XCTAssertGreaterThanOrEqual(bounds[2] - bounds[0], 880, "The DMG Finder window should be wide enough for the larger side-by-side icons.")
        XCTAssertGreaterThanOrEqual(bounds[3] - bounds[1], 500, "The DMG Finder window should be tall enough for the larger icon view.")
        XCTAssertTrue(
            packageScript.contains("set arrangement of icon view options of container window of dmgFolder to not arranged"),
            "Finder should not auto-sort the DMG icons after explicit positioning."
        )
        XCTAssertLessThan(appPosition[0], applicationsPosition[0], "VoiceInput.app should remain on the left side of the install window.")
        XCTAssertGreaterThanOrEqual(applicationsPosition[0] - appPosition[0], 360, "The app and Applications icons should be far enough apart to avoid overlap.")
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
        let layoutVerifier = try String(contentsOfFile: "scripts/verify-dmg-layout.sh", encoding: .utf8)

        XCTAssertTrue(workflow.contains("make release-artifact VERSION=\"$VERSION\" DMG_PATH=VoiceInput.dmg"))
        XCTAssertFalse(workflow.contains("./scripts/verify-dmg.sh VoiceInput.dmg \"$VERSION\" VoiceInput"))
        XCTAssertTrue(workflow.contains("VERSION=\"${GITHUB_REF_NAME#v}\""))
        XCTAssertTrue(verifier.contains("test -d \"$MOUNT_DIR/VoiceInput.app\""))
        XCTAssertTrue(verifier.contains("readlink \"$MOUNT_DIR/Applications\""))
        XCTAssertTrue(verifier.contains("test -f \"$MOUNT_DIR/.DS_Store\""))
        XCTAssertTrue(verifier.contains("CFBundleShortVersionString"))
        XCTAssertTrue(verifier.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(verifier.contains("spctl -a -vvv -t execute"))
        XCTAssertTrue(verifier.contains("grep -qi \"rejected\""))
        XCTAssertTrue(verifier.contains("./scripts/verify-dmg-layout.sh \"$MOUNT_DIR\""))
        XCTAssertTrue(layoutVerifier.contains("MIN_ICON_SIZE=160"))
        XCTAssertTrue(layoutVerifier.contains("MIN_HORIZONTAL_GAP=360"))
        XCTAssertTrue(layoutVerifier.contains("VoiceInput.app"))
        XCTAssertTrue(layoutVerifier.contains("Applications"))
        XCTAssertTrue(layoutVerifier.contains("icon size"))
        XCTAssertTrue(layoutVerifier.contains("bounds"))
        XCTAssertTrue(layoutVerifier.contains("position of item"))
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
            "The release checklist should name make ci as the PR/main automated gate."
        )
        XCTAssertTrue(
            checklist.contains("`make release-check VERSION=<version> DMG_PATH=/tmp/VoiceInput-test.dmg`"),
            "The release checklist should name make release-check as the local release gate."
        )
        XCTAssertTrue(
            checklist.contains("`make version-bump VERSION=vX.Y.Z`"),
            "The release checklist should document version-bump as the automated version metadata and tag entry point."
        )
        XCTAssertTrue(
            checklist.contains("runs the local release gate before commit/tag"),
            "The release checklist should document that version-bump cannot tag before local release verification."
        )
        XCTAssertTrue(
            checklist.contains("stages `README.md`, `Info.plist`, and `CHANGELOG.md`"),
            "The release checklist should document that changelog notes are included in the bump commit."
        )
        XCTAssertTrue(
            checklist.contains("only `CHANGELOG.md` may be dirty before `make version-bump`"),
            "The release checklist should document the exact pre-version-bump dirty tree invariant."
        )
        XCTAssertTrue(
            checklist.contains("source/test/script/workflow changes must be committed before `make version-bump`"),
            "The release checklist should require code and release infrastructure changes to be committed before version bumping."
        )
        XCTAssertTrue(
            checklist.contains("checks local and remote tag collisions"),
            "The release checklist should document local and remote tag collision checks."
        )
        XCTAssertTrue(
            checklist.contains("verifies Finder layout values: icon size, bounds, app position, and Applications position"),
            "The release checklist should document automated Finder layout verification as a release artifact gate."
        )
        XCTAssertTrue(
            checklist.contains("Version bump branch gate"),
            "The release checklist should document the release branch preflight."
        )
        XCTAssertTrue(
            checklist.contains("local HEAD must match `origin/main` before metadata mutation"),
            "The release checklist should document the default remote branch invariant."
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
        XCTAssertTrue(
            section.contains("Pasteboard test isolation"),
            "Unreleased should document the PR #19 parallel pasteboard fixture stabilization."
        )
        XCTAssertTrue(
            section.contains("Release bump hardening"),
            "Unreleased should document the version-bump release gate hardening."
        )
        XCTAssertTrue(
            section.contains("Release branch invariant"),
            "Unreleased should document the version-bump release branch invariant."
        )
        XCTAssertTrue(
            section.contains("DMG layout verification"),
            "Unreleased should document the release artifact Finder layout verifier."
        )
        XCTAssertTrue(
            section.contains("LLM Settings Test"),
            "Unreleased should document the Settings Test user-facing contract."
        )
        XCTAssertTrue(
            section.localizedCaseInsensitiveContains("unsaved one-shot settings"),
            "Unreleased should say Settings Test uses unsaved one-shot settings."
        )
        XCTAssertTrue(
            section.contains("Save remains the only persistence action"),
            "Unreleased should document Save as the only persistence action."
        )
        XCTAssertTrue(
            section.contains("LLM Settings Test freshness"),
            "Unreleased should document stale Settings Test result clearing."
        )
        XCTAssertTrue(
            section.contains("clears stale test results"),
            "Unreleased should say editing fields clears stale test results."
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
        XCTAssertTrue(checklist.contains("docs/manual-qa-log-template.md"))
        XCTAssertTrue(
            checklist.contains("does not replace manual QA"),
            "The release checklist should make clear that automated release-check does not replace real app, permission, and Fn QA."
        )
    }

    func testManualQALogTemplateDocumentsRequiredScenariosWithoutClaimingPass() throws {
        let template = try String(contentsOfFile: "docs/manual-qa-log-template.md", encoding: .utf8)

        XCTAssertTrue(template.contains("| Date | Build | macOS | Scenario | Result | Notes |"))
        XCTAssertTrue(template.contains("Fresh launch with no permissions"))
        XCTAssertTrue(template.contains("Accessibility enabled but Input Monitoring missing"))
        XCTAssertTrue(template.contains("Microphone missing"))
        XCTAssertTrue(template.contains("Speech Recognition missing"))
        XCTAssertTrue(template.contains("Fn pure dictation"))
        XCTAssertTrue(template.contains("Option + Fn prompt builder"))
        XCTAssertTrue(template.contains("Fn + normal key does not start dictation"))
        XCTAssertTrue(template.contains("Insert into TextEdit"))
        XCTAssertTrue(template.contains("Insert into browser field"))
        XCTAssertTrue(template.contains("Recent Results retry insert idle path"))
        XCTAssertTrue(template.contains("Recent Results retry insert busy path"))
        XCTAssertTrue(template.contains("LLM disabled basic dictation"))
        XCTAssertTrue(template.contains("LLM configured test request cancel/retry"))
        XCTAssertTrue(template.contains("Not run / Pass / Fail"))
        XCTAssertTrue(template.contains("does not mean manual QA has passed"))
    }

    func testReleaseNotesExtractionScriptHasFixtureCoverage() throws {
        let script = try String(contentsOfFile: "scripts/extract-release-notes.sh", encoding: .utf8)

        XCTAssertTrue(script.contains("CHANGELOG_FILE"))
        XCTAssertTrue(script.contains("TAG"))
        XCTAssertFalse(script.contains("Release ${TAG}"))

        let fixture = """
        # Changelog

        ## [Unreleased]

        - Work in progress.

        ## [v1.0.10] - 2026-01-10

        - Ten patch.

        ## [v1.0.1] - 2026-01-01

        - One patch.
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voiceinput-release-notes-\(UUID().uuidString).md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try Self.runReleaseNotesScript(changelog: url.path, tag: "v1.0.1").trimmingCharacters(in: .whitespacesAndNewlines), "- One patch.")
        XCTAssertEqual(try Self.runReleaseNotesScript(changelog: url.path, tag: "v1.0.10").trimmingCharacters(in: .whitespacesAndNewlines), "- Ten patch.")
        XCTAssertThrowsError(try Self.runReleaseNotesScript(changelog: url.path, tag: "v1.0.2"))
        XCTAssertThrowsError(try Self.runReleaseNotesScript(changelog: url.path, tag: "Unreleased"))
    }

    func testReleaseNotesExtractionFailsForEmptySection() throws {
        let fixture = """
        # Changelog

        ## [v1.0.0] - 2026-01-01

        ## [v0.9.0] - 2025-12-31

        - Previous release.
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voiceinput-empty-release-notes-\(UUID().uuidString).md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try Self.runReleaseNotesScript(changelog: url.path, tag: "v1.0.0"))
    }

    func testReleaseNotesExtractionStripsTrailingSeparator() throws {
        let fixture = """
        # Changelog

        ## [v1.0.0] - 2026-01-01

        - Public note.

        ---

        ## [v0.9.0] - 2025-12-31

        - Previous release.
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voiceinput-separator-release-notes-\(UUID().uuidString).md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try Self.runReleaseNotesScript(changelog: url.path, tag: "v1.0.0").trimmingCharacters(in: .whitespacesAndNewlines),
            "- Public note."
        )
    }

    func testReleaseNotesExtractionFailsWhenSectionOnlyHasSeparator() throws {
        let fixture = """
        # Changelog

        ## [v1.0.0] - 2026-01-01

        ---

        ## [v0.9.0] - 2025-12-31

        - Previous release.
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voiceinput-separator-only-release-notes-\(UUID().uuidString).md")
        try fixture.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try Self.runReleaseNotesScript(changelog: url.path, tag: "v1.0.0"))
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

    private static func firstIntCapture(in text: String, pattern: String) throws -> Int? {
        guard let capture = try firstCapture(in: text, pattern: pattern) else {
            return nil
        }
        return Int(capture)
    }

    private static func firstIntCaptures(in text: String, pattern: String) throws -> [Int] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return []
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            return Int(text[captureRange])
        }
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

    private static func runReleaseNotesScript(changelog: String, tag: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/extract-release-notes.sh", changelog, tag]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ReleaseNotesExtractionTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }
        return stdout
    }
}
