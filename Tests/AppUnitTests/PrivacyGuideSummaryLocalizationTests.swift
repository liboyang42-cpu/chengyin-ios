import XCTest
@testable import Questify

final class PrivacyGuideSummaryLocalizationTests: XCTestCase {
    private func languageBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
    func testChineseResourcesPreserveEveryOriginalSummaryWord() throws {
        let bundle = try languageBundle("zh-Hans")
        XCTAssertEqual(PrivacyGuideSummaryPresentation.defaultItems.count, 3)
        for item in PrivacyGuideSummaryPresentation.defaultItems {
            XCTAssertEqual(bundle.localizedString(forKey: item.id + ".title", value: nil, table: "PrivacyGuideSummary"), item.title)
            XCTAssertEqual(bundle.localizedString(forKey: item.id + ".detail", value: nil, table: "PrivacyGuideSummary"), item.detail)
        }
    }
    func testEnglishSummaryResourcesAreCompleteAndDoNotFallBackToChineseOrKeys() throws {
        let bundle = try languageBundle("en")
        let titles = ["collection_scope": "Information collected", "permission_usage": "How permissions are used",
                      "revoke_and_deregister": "Withdraw consent or request account deletion"]
        for item in PrivacyGuideSummaryPresentation.defaultItems {
            XCTAssertEqual(bundle.localizedString(forKey: item.id + ".title", value: nil, table: "PrivacyGuideSummary"), titles[item.id])
            let key = item.id + ".detail"
            let detail = bundle.localizedString(forKey: key, value: nil, table: "PrivacyGuideSummary")
            XCTAssertFalse(detail.isEmpty)
            XCTAssertNotEqual(detail, key)
            XCTAssertNotEqual(detail, item.detail)
        }
    }
}
