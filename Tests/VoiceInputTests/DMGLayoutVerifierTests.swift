import Foundation
import XCTest

final class DMGLayoutVerifierTests: XCTestCase {
    func testValidLayoutValuesPass() throws {
        let result = try runLayoutVerifier(arguments: [
            "--validate-values",
            "160",
            "100,100,980,620",
            "260,240",
            "700,240",
        ])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("Verified DMG Finder layout"))
        XCTAssertTrue(result.combinedOutput.contains("iconSize=160"))
        XCTAssertTrue(result.combinedOutput.contains("VoiceInput.app={260,240}"))
        XCTAssertTrue(result.combinedOutput.contains("Applications={700,240}"))
    }

    func testRejectsSmallIconSize() throws {
        let result = try runLayoutVerifier(arguments: [
            "--validate-values",
            "128",
            "100,100,980,620",
            "260,240",
            "700,240",
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("icon size too small"))
    }

    func testRejectsApplicationsOnLeftSide() throws {
        let result = try runLayoutVerifier(arguments: [
            "--validate-values",
            "160",
            "100,100,980,620",
            "700,240",
            "260,240",
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("VoiceInput.app must be left of Applications"))
    }

    func testRejectsSmallHorizontalGap() throws {
        let result = try runLayoutVerifier(arguments: [
            "--validate-values",
            "160",
            "100,100,980,620",
            "260,240",
            "500,240",
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("horizontal gap too small"))
    }

    func testRejectsNarrowWindow() throws {
        let result = try runLayoutVerifier(arguments: [
            "--validate-values",
            "160",
            "100,100,900,620",
            "260,240",
            "700,240",
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("window width too small"))
    }

    func testRejectsShortWindow() throws {
        let result = try runLayoutVerifier(arguments: [
            "--validate-values",
            "160",
            "100,100,980,560",
            "260,240",
            "700,240",
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.combinedOutput.contains("window height too small"))
    }

    private func runLayoutVerifier(arguments: [String]) throws -> DMGLayoutCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/verify-dmg-layout.sh"] + arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return DMGLayoutCommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

private struct DMGLayoutCommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        stdout + stderr
    }
}
