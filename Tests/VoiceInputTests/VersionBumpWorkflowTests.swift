import Foundation
import XCTest

final class VersionBumpWorkflowTests: XCTestCase {
    private let fileManager = FileManager.default

    func testVersionBumpRejectsDirtySourceFileBeforeMetadataMutation() throws {
        let repo = try makeTemporaryRepo()
        try append("Sources/VoiceInput/AppDelegate.swift", "\n// local source change\n", in: repo)

        let result = runScript("scripts/check-version-bump-source-state.sh", ["pre"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Sources/VoiceInput/AppDelegate.swift"))
        XCTAssertTrue(result.combinedOutput.contains("unexpected dirty files"))
    }

    func testVersionBumpAllowsDirtyChangelogOnly() throws {
        let repo = try makeTemporaryRepo()
        try append("CHANGELOG.md", "\n## [v9.9.9] - 2026-07-04\n\n- Test release.\n", in: repo)

        let unstagedResult = runScript("scripts/check-version-bump-source-state.sh", ["pre"], in: repo)
        XCTAssertEqual(unstagedResult.status, 0, unstagedResult.combinedOutput)

        try runGit(["add", "CHANGELOG.md"], in: repo).checkSuccess()
        let stagedResult = runScript("scripts/check-version-bump-source-state.sh", ["pre"], in: repo)
        XCTAssertEqual(stagedResult.status, 0, stagedResult.combinedOutput)
    }

    func testVersionBumpRejectsUntrackedFileButAllowsIgnoredArtifacts() throws {
        let repo = try makeTemporaryRepo()
        try write("VoiceInput.app/Contents/Info.plist", "ignored app artifact", in: repo)
        try write(".build/debug/placeholder", "ignored build artifact", in: repo)
        try write("VoiceInput.dmg", "ignored dmg artifact", in: repo)

        let ignoredResult = runScript("scripts/check-version-bump-source-state.sh", ["pre"], in: repo)
        XCTAssertEqual(ignoredResult.status, 0, ignoredResult.combinedOutput)

        try write("tmp.txt", "untracked release debris", in: repo)
        let untrackedResult = runScript("scripts/check-version-bump-source-state.sh", ["pre"], in: repo)

        XCTAssertNotEqual(untrackedResult.status, 0)
        XCTAssertTrue(untrackedResult.combinedOutput.contains("untracked files"))
        XCTAssertTrue(untrackedResult.combinedOutput.contains("tmp.txt"))
    }

    func testVersionBumpRejectsExistingLocalTag() throws {
        let repo = try makeTemporaryRepo()
        try runGit(["tag", "v9.9.9"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-tag-state.sh", ["v9.9.9"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Tag v9.9.9 already exists locally"))
    }

    func testVersionBumpRejectsExistingRemoteTag() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try runGit(["remote", "add", "origin", remote.path], in: repo).checkSuccess()
        try runGit(["push", "origin", "HEAD:main"], in: repo).checkSuccess()
        try runGit(["tag", "v9.9.9"], in: repo).checkSuccess()
        try runGit(["push", "origin", "v9.9.9"], in: repo).checkSuccess()
        try runGit(["tag", "-d", "v9.9.9"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-tag-state.sh", ["v9.9.9"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Tag v9.9.9 already exists on origin"))
    }

    func testVersionBumpFailsClosedWhenRemoteTagStateCannotBeVerified() throws {
        let repo = try makeTemporaryRepo()
        try runGit(["remote", "add", "origin", "/tmp/voiceinput-missing-\(UUID().uuidString).git"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-tag-state.sh", ["v9.9.9"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Unable to verify remote tag state"))
    }

    func testVersionBumpPostCheckAllowsOnlyReleaseMetadataFiles() throws {
        let repo = try makeTemporaryRepo()
        try append("README.md", "\nversion-v9.9.9\n", in: repo)
        try append("Info.plist", "\n<!-- 9.9.9 -->\n", in: repo)
        try append("CHANGELOG.md", "\n## [v9.9.9] - 2026-07-04\n\n- Test release.\n", in: repo)

        let result = runScript("scripts/check-version-bump-source-state.sh", ["post"], in: repo)

        XCTAssertEqual(result.status, 0, result.combinedOutput)
    }

    func testVersionBumpRejectsUnexpectedPostReleaseCheckDirtyFile() throws {
        let repo = try makeTemporaryRepo()
        try append("README.md", "\nversion-v9.9.9\n", in: repo)
        try append("Info.plist", "\n<!-- 9.9.9 -->\n", in: repo)
        try append("CHANGELOG.md", "\n## [v9.9.9] - 2026-07-04\n\n- Test release.\n", in: repo)
        try append("Tests/VoiceInputTests/MakefileTests.swift", "\n// accidental test mutation\n", in: repo)

        let result = runScript("scripts/check-version-bump-source-state.sh", ["post"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Tests/VoiceInputTests/MakefileTests.swift"))
    }

    func testVersionBumpBranchStateAllowsMainMatchingOriginMain() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("main", from: repo, to: remote, remoteName: "origin")

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertEqual(result.status, 0, result.combinedOutput)
    }

    func testVersionBumpBranchStateRejectsFeatureBranch() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("main", from: repo, to: remote, remoteName: "origin")
        try runGit(["checkout", "-b", "feature/foo"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("current branch is feature/foo"))
        XCTAssertTrue(result.combinedOutput.contains("must run on main"))
    }

    func testVersionBumpBranchStateRejectsDetachedHead() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("main", from: repo, to: remote, remoteName: "origin")
        try runGit(["checkout", "--detach", "HEAD"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("detached HEAD"))
    }

    func testVersionBumpBranchStateRejectsLocalMainBehindOriginMain() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("main", from: repo, to: remote, remoteName: "origin")
        let initialHead = try runGit(["rev-parse", "HEAD"], in: repo).checkedStdout()
        try append("CHANGELOG.md", "\n- Remote-only release note.\n", in: repo)
        try runGit(["add", "CHANGELOG.md"], in: repo).checkSuccess()
        try runGit(["commit", "-m", "remote update"], in: repo).checkSuccess()
        try runGit(["push", "origin", "HEAD:refs/heads/main"], in: repo).checkSuccess()
        try runGit(["reset", "--hard", initialHead], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Local main is not identical to origin/main"))
        XCTAssertTrue(result.combinedOutput.contains("Sync main with origin/main"))
    }

    func testVersionBumpBranchStateRejectsLocalMainAheadOfOriginMain() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("main", from: repo, to: remote, remoteName: "origin")
        try append("CHANGELOG.md", "\n- Local-only release note.\n", in: repo)
        try runGit(["add", "CHANGELOG.md"], in: repo).checkSuccess()
        try runGit(["commit", "-m", "local update"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Local main is not identical to origin/main"))
    }

    func testVersionBumpBranchStateRejectsDivergedLocalAndRemoteMain() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("main", from: repo, to: remote, remoteName: "origin")
        try commitInRemoteClone(remote, branch: "main", path: "README.md", contents: "\nRemote divergent change.\n")
        try append("CHANGELOG.md", "\n- Local divergent change.\n", in: repo)
        try runGit(["add", "CHANGELOG.md"], in: repo).checkSuccess()
        try runGit(["commit", "-m", "local divergent update"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Local main is not identical to origin/main"))
    }

    func testVersionBumpBranchStateRejectsMissingRemoteBranch() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try runGit(["branch", "-M", "main"], in: repo).checkSuccess()
        try runGit(["remote", "add", "origin", remote.path], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Unable to fetch origin/main"))
    }

    func testVersionBumpBranchStateRejectsInaccessibleRemote() throws {
        let repo = try makeTemporaryRepo()
        try runGit(["branch", "-M", "main"], in: repo).checkSuccess()
        try runGit(["remote", "add", "origin", "/tmp/voiceinput-missing-\(UUID().uuidString).git"], in: repo).checkSuccess()

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["main", "origin"], in: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Unable to fetch origin/main"))
    }

    func testVersionBumpBranchStateAllowsConfiguredReleaseBranchAndRemote() throws {
        let repo = try makeTemporaryRepo()
        let remote = try makeBareRemote()
        try publishReleaseBranch("release/1.7", from: repo, to: remote, remoteName: "upstream")

        let result = runScript("scripts/check-version-bump-branch-state.sh", ["release/1.7", "upstream"], in: repo)

        XCTAssertEqual(result.status, 0, result.combinedOutput)
    }

    private func makeTemporaryRepo() throws -> URL {
        let repo = fileManager.temporaryDirectory
            .appendingPathComponent("voiceinput-version-bump-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
        try write(".gitignore", ".build/\nVoiceInput.app/\n*.dmg\n", in: repo)
        try write("README.md", "# VoiceInput\n\n> version-v1.6.0 | date-2026-05-03\n", in: repo)
        try write("Info.plist", "<plist><dict><key>CFBundleShortVersionString</key><string>1.6.0</string></dict></plist>\n", in: repo)
        try write("CHANGELOG.md", "# Changelog\n\n## [v1.6.0] - 2026-05-03\n\n- Existing release.\n", in: repo)
        try write("Sources/VoiceInput/AppDelegate.swift", "final class AppDelegate {}\n", in: repo)
        try write("Tests/VoiceInputTests/MakefileTests.swift", "import XCTest\n", in: repo)

        try runGit(["init"], in: repo).checkSuccess()
        try runGit(["config", "user.name", "VoiceInput Test"], in: repo).checkSuccess()
        try runGit(["config", "user.email", "voiceinput-test@example.invalid"], in: repo).checkSuccess()
        try runGit(["add", "."], in: repo).checkSuccess()
        try runGit(["commit", "-m", "initial"], in: repo).checkSuccess()
        return repo
    }

    private func publishReleaseBranch(_ branch: String, from repo: URL, to remote: URL, remoteName: String) throws {
        try runGit(["branch", "-M", branch], in: repo).checkSuccess()
        try runGit(["remote", "add", remoteName, remote.path], in: repo).checkSuccess()
        try runGit(["push", remoteName, "HEAD:refs/heads/\(branch)"], in: repo).checkSuccess()
    }

    private func commitInRemoteClone(_ remote: URL, branch: String, path: String, contents: String) throws {
        let clone = fileManager.temporaryDirectory
            .appendingPathComponent("voiceinput-version-bump-clone-\(UUID().uuidString)", isDirectory: true)
        try run("/usr/bin/env", ["git", "clone", "--branch", branch, remote.path, clone.path], in: fileManager.temporaryDirectory)
            .checkSuccess()
        try runGit(["config", "user.name", "VoiceInput Test"], in: clone).checkSuccess()
        try runGit(["config", "user.email", "voiceinput-test@example.invalid"], in: clone).checkSuccess()
        try append(path, contents, in: clone)
        try runGit(["add", path], in: clone).checkSuccess()
        try runGit(["commit", "-m", "remote divergent update"], in: clone).checkSuccess()
        try runGit(["push", "origin", "HEAD:refs/heads/\(branch)"], in: clone).checkSuccess()
    }

    private func makeBareRemote() throws -> URL {
        let remote = fileManager.temporaryDirectory
            .appendingPathComponent("voiceinput-version-bump-remote-\(UUID().uuidString).git", isDirectory: true)
        try fileManager.createDirectory(at: remote, withIntermediateDirectories: true)
        try run("/usr/bin/env", ["git", "init", "--bare"], in: remote).checkSuccess()
        return remote
    }

    private func write(_ path: String, _ contents: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func append(_ path: String, _ contents: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (existing + contents).write(to: url, atomically: true, encoding: .utf8)
    }

    private func runScript(_ relativePath: String, _ arguments: [String], in directory: URL) -> CommandResult {
        let script = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(relativePath)
        return run("/bin/bash", [script.path] + arguments, in: directory)
    }

    private func runGit(_ arguments: [String], in directory: URL) -> CommandResult {
        run("/usr/bin/env", ["git"] + arguments, in: directory)
    }

    private func run(_ executable: String, _ arguments: [String], in directory: URL) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
        ]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: String(describing: error))
        }

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        stdout + stderr
    }

    func checkSuccess(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(status, 0, combinedOutput, file: file, line: line)
    }

    func checkedStdout(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        XCTAssertEqual(status, 0, combinedOutput, file: file, line: line)
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
