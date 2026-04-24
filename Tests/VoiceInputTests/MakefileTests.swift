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
}
