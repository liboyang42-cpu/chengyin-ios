import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantStoreHoursTests: XCTestCase {
    func testCanonicalDaytimeAndOvernightWithoutTimezone() throws {
        var hours = MerchantStoreHours()
        XCTAssertEqual(try hours.wireValue(), "周一至周日 10:00-22:00")
        hours.days = [6, 0, 4]; hours.startMinutes = 1320; hours.endMinutes = 90
        XCTAssertEqual(try hours.wireValue(), "周一、五、日 22:00-次日01:30")
        XCTAssertEqual(MerchantStoreHours(wireValue: try hours.wireValue()), hours)
        hours.startMinutes = 0; hours.endMinutes = 1439
        XCTAssertEqual(try hours.wireValue(), "周一、五、日 00:00-23:59")
    }
    func testRejectsMalformedEqualMissingDaysAndIncorrectOvernight() throws {
        for wire in ["", "每天 10:00-22:00", "10:00-22:00", "周一 24:00-01:00", "周一 10:60-22:00", "周一 10:00-10:00", "周一 22:00-01:00", "周一 10:00-次日22:00", "周一 10:00-22:00\n"] {
            XCTAssertNil(MerchantStoreHours(wireValue: wire), wire)
        }
        var hours = MerchantStoreHours(); hours.days = []
        XCTAssertThrowsError(try hours.wireValue())
        hours.days = [7]; XCTAssertThrowsError(try hours.wireValue())
        hours.days = [1]; hours.startMinutes = -1; XCTAssertThrowsError(try hours.wireValue())
        hours.startMinutes = 1440; XCTAssertThrowsError(try hours.wireValue())
        hours.startMinutes = hours.endMinutes; XCTAssertThrowsError(try hours.wireValue())
    }
    func testMissingNullAndLegacyHoursAreNeverResubmittedImplicitly() throws {
        for json in [#"{"id":31}"#, #"{"id":31,"businessTime":null}"#, #"{"id":31,"businessTime":"每天营业旧格式"}"#] {
            var profile = try JSONDecoder().decode(MerchantStoreProfile.self, from: Data(json.utf8))
            let original = profile.businessTime
            profile.name = "Another edit"
            XCTAssertNil(profile.fields["businessTime"]); XCTAssertNil(profile.hoursBlocker)
            profile.businessTimeReplacement = try MerchantStoreHours().wireValue()
            XCTAssertEqual(profile.fields["businessTime"] as? String, "周一至周日 10:00-22:00")
            XCTAssertEqual(profile.businessTime, original)
            XCTAssertEqual(MerchantOperationsDraft.profile(profile).reviewLines.last?.value, profile.businessTimeReplacement)
            profile.businessTimeReplacement = nil
            XCTAssertNil(profile.fields["businessTime"]); XCTAssertEqual(profile.displayedBusinessTime, original)
        }
    }
    func testInvalidReplacementCannotReviewOrPreviewAndStoryOmitsHours() throws {
        var store = try JSONDecoder().decode(MerchantStorefront.self, from: Data(#"{"id":31,"businessTime":"legacy"}"#.utf8))
        store.profile.businessTimeReplacement = ""
        XCTAssertEqual(MerchantOperationsDraft.profile(store.profile).blocker, "merchant.operations.hoursInvalid")
        XCTAssertThrowsError(try MerchantOperationsDraft.profile(store.profile).previews())
        XCTAssertNil(store.profile.legacyFields["businessTime"])
        let request = try XCTUnwrap(MerchantOperationsDraft.story(store).previews().last)
        XCTAssertNil((try JSONSerialization.jsonObject(with: request.json) as? [String: Any])?["businessTime"])
    }
}
