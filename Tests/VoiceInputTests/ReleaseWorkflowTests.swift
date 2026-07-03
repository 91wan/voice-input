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

    func testUnsignedDistributionGuidanceIsPublishedForV112() throws {
        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let chineseReadme = try String(contentsOfFile: "README.zh-CN.md", encoding: .utf8)
        let japaneseReadme = try String(contentsOfFile: "README.ja.md", encoding: .utf8)
        let koreanReadme = try String(contentsOfFile: "README.ko.md", encoding: .utf8)
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(englishReadme.contains("unsigned / not notarized"))
        XCTAssertTrue(englishReadme.contains("Right-click `VoiceInput.app`"))
        XCTAssertTrue(englishReadme.contains("System Settings -> Privacy & Security"))

        XCTAssertTrue(chineseReadme.contains("未签名 / 未 notarized"))
        XCTAssertTrue(chineseReadme.contains("右键 `VoiceInput.app`"))
        XCTAssertTrue(chineseReadme.contains("系统设置 -> 隐私与安全性"))

        XCTAssertTrue(japaneseReadme.contains("署名なし / notarized されていない"))
        XCTAssertTrue(japaneseReadme.contains("右クリック `VoiceInput.app`"))
        XCTAssertTrue(japaneseReadme.contains("システム設定 -> プライバシーとセキュリティ"))

        XCTAssertTrue(koreanReadme.contains("서명되지 않았고 notarized 되지 않은"))
        XCTAssertTrue(koreanReadme.contains("`VoiceInput.app`을 우클릭"))
        XCTAssertTrue(koreanReadme.contains("시스템 설정 -> 개인정보 보호 및 보안"))

        XCTAssertTrue(changelog.contains("## [v1.1.2] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("not notarized"))
        XCTAssertTrue(changelog.contains("右键 `VoiceInput.app`"))
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

    func testModifierChordFixReleaseNotesArePublishedForV113() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.1.3] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Fn + Control"))
        XCTAssertTrue(changelog.contains("纯 `Fn` 和纯 `Option + Fn`"))
    }

    func testDMGLayoutReleaseNotesArePublishedForV114() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.1.4] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("图标大小"))
        XCTAssertTrue(changelog.contains("左侧"))
        XCTAssertTrue(changelog.contains("右侧"))
    }

    func testFnKeyDownChordReleaseNotesArePublishedForV115() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.1.5] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Fn + 普通按键"))
        XCTAssertTrue(changelog.contains("不会启动听写"))
    }

    func testInputMonitoringReleaseNotesArePublishedForV116() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.1.6] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Input Monitoring"))
        XCTAssertTrue(changelog.contains("Accessibility 已开启但仍失败"))
    }

    func testPermissionRecoveryReleaseNotesArePublishedForV117() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.1.7] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Reopen App"))
        XCTAssertTrue(changelog.contains("Fix Permission"))
    }

    func testStableDistributionReleaseNotesArePublishedForV120() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.2.0] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("首次安装完整路径"))
        XCTAssertTrue(changelog.contains("更新后权限失效恢复路径"))
        XCTAssertTrue(changelog.contains("Release QA checklist"))
    }

    func testDictionaryImportExportReleaseNotesArePublishedForV130() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let chineseReadme = try String(contentsOfFile: "README.zh-CN.md", encoding: .utf8)
        let japaneseReadme = try String(contentsOfFile: "README.ja.md", encoding: .utf8)
        let koreanReadme = try String(contentsOfFile: "README.ko.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.3.0] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Dictionary import/export"))
        XCTAssertTrue(changelog.contains("不会自动覆盖已保存词典"))
        XCTAssertTrue(englishReadme.contains("Import..."))
        XCTAssertTrue(englishReadme.contains("Export..."))
        XCTAssertTrue(chineseReadme.contains("Import..."))
        XCTAssertTrue(chineseReadme.contains("Export..."))
        XCTAssertTrue(japaneseReadme.contains("Import..."))
        XCTAssertTrue(japaneseReadme.contains("Export..."))
        XCTAssertTrue(koreanReadme.contains("Import..."))
        XCTAssertTrue(koreanReadme.contains("Export..."))
    }

    func testPermissionRepairReleaseNotesArePublishedForV140() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let chineseReadme = try String(contentsOfFile: "README.zh-CN.md", encoding: .utf8)
        let japaneseReadme = try String(contentsOfFile: "README.ja.md", encoding: .utf8)
        let koreanReadme = try String(contentsOfFile: "README.ko.md", encoding: .utf8)
        let checklist = try String(contentsOfFile: "docs/release-qa-checklist.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.4.0] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("First-Run / Permission Repair"))
        XCTAssertTrue(changelog.contains("Failed / Next / Reopen"))
        XCTAssertTrue(readme.contains("Failed / Next / Reopen"))
        XCTAssertTrue(chineseReadme.contains("Failed / Next / Reopen"))
        XCTAssertTrue(japaneseReadme.contains("Failed / Next / Reopen"))
        XCTAssertTrue(koreanReadme.contains("Failed / Next / Reopen"))
        XCTAssertTrue(checklist.contains("Failed / Next / Reopen"))
    }

    func testDictationWorkflowReleaseNotesArePublishedForV150() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.5.0] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Dictation Workflow Clarity"))
        XCTAssertTrue(changelog.contains("Option + Fn"))
        XCTAssertTrue(changelog.contains("ordinary Fn still uses Apple Speech + DictionaryFilter"))
        XCTAssertTrue(readme.contains("Option + Fn uses Prompt Builder once"))
        XCTAssertTrue(readme.contains("ordinary Fn still uses Apple Speech + DictionaryFilter"))
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

    func testUnsignedDistributionHardeningReleaseNotesArePublishedForV160() throws {
        let changelog = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let checklist = try String(contentsOfFile: "docs/release-qa-checklist.md", encoding: .utf8)

        XCTAssertTrue(changelog.contains("## [v1.6.0] - 2026-05-03"))
        XCTAssertTrue(changelog.contains("Unsigned Distribution Hardening"))
        XCTAssertTrue(changelog.contains("not notarized"))
        XCTAssertTrue(changelog.contains("spctl rejected"))
        XCTAssertTrue(readme.contains("Automated release gates verify the unsigned DMG layout"))
        XCTAssertTrue(checklist.contains("## Automated Release Gate"))
        XCTAssertTrue(checklist.contains("## Manual Permission And Fn QA"))
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
}
