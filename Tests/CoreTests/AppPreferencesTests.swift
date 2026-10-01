import XCTest
@testable import QuestifyCore

final class AppPreferencesTests: XCTestCase {
    func testUnknownStoredLanguageFallsBackToSystem() {
        XCTAssertEqual(AppLanguage(storedValue: "removed-language"), .system)
    }
    func testStoredLanguagesRoundTrip() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage(storedValue: language.rawValue), language)
        }
    }
    func testExplicitLocales() {
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.locale.identifier, "zh-Hans")
    }
    func testRegistrationIntentsRemainSeparate() {
        XCTAssertEqual(Set(RegistrationIntent.allCases.map(\.rawValue)), ["player", "merchant"])
    }
}
