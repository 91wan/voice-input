import XCTest
@testable import VoiceInput

final class SettingsWindowTests: XCTestCase {
    func testSettingsValidationRejectsInvalidNonBlankAPIBaseURL() {
        XCTAssertThrowsError(
            try SettingsWindow.validatedSettings(
                apiBaseURL: "localhost:1234/v1",
                model: "gpt-4o-mini"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid API base URL"))
        }
    }

    func testSettingsValidationAllowsBlankAPIBaseURLForDefaultFallback() throws {
        let settings = try SettingsWindow.validatedSettings(
            apiBaseURL: "   ",
            model: "   "
        )

        XCTAssertEqual(settings.apiBaseURL, "")
        XCTAssertEqual(settings.model, "")
    }
}
