import XCTest
@testable import QuestifyCore

/// Mini-program `infomation` / `infomationdetail` read mapping (w2-07).
final class W2GuideXcxParityTests: XCTestCase {
    private func decode(_ json: String) throws -> SocialInformation {
        try JSONDecoder().decode(SocialInformation.self, from: Data(json.utf8))
    }

    func testDetailKeepsSourceCreateTimeVerbatim() throws {
        let row = try decode(#"{"id":7,"title":"城市定向","subtitle":"规则","contents":"<p>a</p>","createTime":"2026-10-01 08:30:00"}"#)
        XCTAssertEqual(row.createTime, "2026-10-01 08:30:00")
        XCTAssertTrue(row.isUsable)
    }

    func testMissingCreateTimeStaysAbsent() throws {
        XCTAssertNil(try decode(#"{"id":7,"title":"城市定向","contents":"x"}"#).createTime)
    }

    func testNumericTitleWithoutDistinctSubtitleIsUnusableLikeSource() throws {
        XCTAssertFalse(try decode(#"{"id":11,"title":"11","subtitle":"11","contents":"x"}"#).isUsable)
        XCTAssertFalse(try decode(#"{"id":11,"title":"11","contents":"x"}"#).isUsable)
        XCTAssertTrue(try decode(#"{"id":12,"title":"2024","subtitle":"年度城市定向回顾","contents":"x"}"#).isUsable)
    }

    func testSubtitleEqualToTitleIsNotRepeatedAsDescription() throws {
        XCTAssertNil(try decode(#"{"id":3,"title":"漫游","subtitle":" 漫游 ","contents":"x"}"#).summary)
    }
}
