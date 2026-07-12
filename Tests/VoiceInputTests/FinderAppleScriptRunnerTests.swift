import Darwin
import Foundation
import XCTest

final class FinderAppleScriptRunnerTests: XCTestCase {
    private struct RunnerResult {
        let status: Int32
        let stdout: String
        let stderr: String
        let elapsed: TimeInterval
    }

    func testSuccessPreservesStdoutAndExitCode() throws {
        let fixture = try makeFixture(
            script: """
                #!/usr/bin/env bash
                printf 'iconSize=160\\nbounds=100,100,980,620\\nappPosition=260,240\\napplicationsPosition=700,240\\n'
                """
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try runRunner(fakeOsaScript: fixture.executable)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(
            result.stdout,
            "iconSize=160\nbounds=100,100,980,620\nappPosition=260,240\napplicationsPosition=700,240\n"
        )
        XCTAssertEqual(result.stderr, "")
    }

    func testFailurePreservesNonzeroStatusAndAddsActionableGuidance() throws {
        let fixture = try makeFixture(
            script: """
                #!/usr/bin/env bash
                echo 'Not authorized to send Apple events to Finder' >&2
                exit 1
                """
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = try runRunner(fakeOsaScript: fixture.executable)

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Not authorized to send Apple events to Finder"))
        XCTAssertTrue(result.stderr.contains("logged-in GUI session"))
        XCTAssertTrue(result.stderr.contains("Finder Automation access"))
        XCTAssertFalse(result.stderr.localizedCaseInsensitiveContains("success"))
    }

    func testTimeoutReturns124WithinBoundAndTerminatesChild() throws {
        let fixture = try makeFixture(
            script: """
                #!/usr/bin/env bash
                echo $$ > "$PID_FILE"
                trap 'echo terminated > "$TERMINATED_MARKER"; exit 143' TERM
                while :; do sleep 1; done
                """
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let pidFile = fixture.directory.appendingPathComponent("child.pid")
        let terminatedMarker = fixture.directory.appendingPathComponent("terminated")

        let result = try runRunner(
            fakeOsaScript: fixture.executable,
            environment: [
                "FINDER_AUTOMATION_TIMEOUT_SECONDS": "1",
                "PID_FILE": pidFile.path,
                "TERMINATED_MARKER": terminatedMarker.path,
            ]
        )

        XCTAssertEqual(result.status, 124)
        XCTAssertLessThan(result.elapsed, 5)
        XCTAssertTrue(result.stderr.contains("Finder automation timed out"))
        XCTAssertTrue(result.stderr.contains("logged-in GUI session"))
        XCTAssertTrue(result.stderr.contains("Finder Automation access"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: terminatedMarker.path))

        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(Int32(pidText))
        XCTAssertEqual(kill(pid, 0), -1, "Owned fake osascript child must be gone before the helper returns")
        XCTAssertEqual(errno, ESRCH)
    }

    func testInvalidTimeoutFailsBeforeLaunchingOsaScript() throws {
        for invalidTimeout in ["0", "abc"] {
            let fixture = try makeFixture(
                script: """
                    #!/usr/bin/env bash
                    touch "$LAUNCH_MARKER"
                    """
            )
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let launchMarker = fixture.directory.appendingPathComponent("launched")

            let result = try runRunner(
                fakeOsaScript: fixture.executable,
                environment: [
                    "FINDER_AUTOMATION_TIMEOUT_SECONDS": invalidTimeout,
                    "LAUNCH_MARKER": launchMarker.path,
                ]
            )

            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.stderr.contains("positive integer"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: launchMarker.path))
        }
    }

    private func makeFixture(script: String) throws -> (directory: URL, executable: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderAppleScriptRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-osascript")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory, executable)
    }

    private func runRunner(
        fakeOsaScript: URL,
        environment: [String: String] = [:],
        testTimeout: TimeInterval = 5
    ) throws -> RunnerResult {
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let runnerURL = repositoryURL.appendingPathComponent("scripts/run-finder-applescript.sh")
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment["OSASCRIPT_BIN"] = fakeOsaScript.path
        for (key, value) in environment {
            processEnvironment[key] = value
        }

        process.executableURL = runnerURL
        process.currentDirectoryURL = repositoryURL
        process.environment = processEnvironment
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let completed = expectation(description: "Finder AppleScript helper exits")
        process.terminationHandler = { _ in completed.fulfill() }
        let startedAt = Date()
        try process.run()
        standardInput.fileHandleForWriting.write(Data("return \"test\"\n".utf8))
        try standardInput.fileHandleForWriting.close()

        if XCTWaiter.wait(for: [completed], timeout: testTimeout) == .timedOut {
            process.terminate()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            XCTFail("Finder AppleScript helper exceeded the test-level timeout")
        }

        let stdout = String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return RunnerResult(
            status: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }
}
