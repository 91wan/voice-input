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

    func testVersionMetadataIsBumpedForV120() throws {
        let englishReadme = try String(contentsOfFile: "README.md", encoding: .utf8)
        XCTAssertTrue(englishReadme.contains("version-v1.2.0"))

        let rootPlist = NSDictionary(contentsOf: URL(fileURLWithPath: "Info.plist"))
        XCTAssertEqual(rootPlist?["CFBundleShortVersionString"] as? String, "1.2.0")
        XCTAssertEqual(rootPlist?["CFBundleVersion"] as? String, "1.2.0")

        let appPlist = NSDictionary(contentsOf: URL(fileURLWithPath: "VoiceInput.app/Contents/Info.plist"))
        XCTAssertEqual(appPlist?["CFBundleShortVersionString"] as? String, "1.2.0")
        XCTAssertEqual(appPlist?["CFBundleVersion"] as? String, "1.2.0")
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
}
