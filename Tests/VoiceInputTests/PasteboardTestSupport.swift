import AppKit
import XCTest

enum PasteboardTestSupport {
    static func makePasteboard(function: String = #function) -> NSPasteboard {
        let sanitizedFunction = function.replacingOccurrences(
            of: #"[^A-Za-z0-9_.-]"#,
            with: "-",
            options: .regularExpression
        )
        let name = NSPasteboard.Name(
            "VoiceInputTests.\(ProcessInfo.processInfo.processIdentifier).\(sanitizedFunction).\(UUID().uuidString)"
        )
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        return pasteboard
    }
}

final class PasteboardTestSupportTests: XCTestCase {
    func testIsolatedPasteboardsUseExplicitUniqueNames() {
        let firstPasteboard = PasteboardTestSupport.makePasteboard()
        let secondPasteboard = PasteboardTestSupport.makePasteboard()

        XCTAssertNotEqual(firstPasteboard.name, secondPasteboard.name)
        XCTAssertTrue(firstPasteboard.name.rawValue.hasPrefix("VoiceInputTests."))
        XCTAssertTrue(firstPasteboard.name.rawValue.contains("\(ProcessInfo.processInfo.processIdentifier)"))
    }
}
