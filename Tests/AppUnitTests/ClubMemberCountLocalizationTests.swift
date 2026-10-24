import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ClubMemberCountLocalizationTests: XCTestCase {
    func testEnglishZeroOneAndManyUseExactCountGrammar() {
        let locale = Locale(identifier: "en")
        XCTAssertEqual(ClubMemberCountLocalization.text(0, locale: locale), "0 members")
        XCTAssertEqual(ClubMemberCountLocalization.text(1, locale: locale), "1 member")
        XCTAssertEqual(ClubMemberCountLocalization.text(2, locale: locale), "2 members")
        XCTAssertEqual(ClubMemberCountLocalization.text(21, locale: locale), "21 members")
    }

    func testChineseZeroOneAndManyKeepTheSameMemberMeasureWord() {
        let locale = Locale(identifier: "zh-Hans")
        for count in [0, 1, 2, 21] {
            XCTAssertEqual(ClubMemberCountLocalization.text(count, locale: locale), "\(count) 名成员")
        }
    }

    func testExplicitUILocaleCanChangeInBothDirectionsWithoutCachedLanguage() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(ClubMemberCountLocalization.text(1, locale: english), "1 member")
        XCTAssertEqual(ClubMemberCountLocalization.text(1, locale: chinese), "1 名成员")
        XCTAssertEqual(ClubMemberCountLocalization.text(1, locale: english), "1 member")
        XCTAssertEqual(ClubMemberCountLocalization.text(2, locale: chinese), "2 名成员")
    }

    func testResourceRetainsSelectedLocaleAndOnlyExactlyOneIsSingular() {
        for language in ["en-GB", "zh-Hans-CN"] {
            let locale = Locale(identifier: language)
            for count in [-1, 0, 1, 2, 101, Int.max] {
                let resource = ClubMemberCountLocalization.resource(count, locale: locale)
                XCTAssertEqual(resource.locale, locale)
                XCTAssertEqual(resource.key, count == 1 ? "club.memberCount.singular %lld" : "club.memberCount %lld")
            }
        }
    }

    func testSourceCountIsNotClampedOrNarrowed() {
        for count in [-1, 10_000, Int.max] {
            XCTAssertEqual(ClubMemberCountLocalization.text(count, locale: Locale(identifier: "en")), "\(count) members")
            XCTAssertEqual(ClubMemberCountLocalization.text(count, locale: Locale(identifier: "zh-Hans")), "\(count) 名成员")
        }
    }

    func testNormalClubCardRendersBothLanguagesAtMaximumTextWithoutChangingMembership() throws {
        let club = try JSONDecoder().decode(ClubRecord.self, from: Data(#"{"id":71,"name":"Local club","memberCount":1,"isOwner":false,"isJoined":false}"#.utf8))
        for language in ["en", "zh-Hans"] {
            let view = ClubRow(club: club)
                .environment(\.locale, Locale(identifier: language))
                .dynamicTypeSize(.accessibility5)
            let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 320, height: 20_000))
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(size.width, 321)
        }
        XCTAssertEqual(club.memberCount, 1)
        XCTAssertFalse(club.isOwner)
        XCTAssertFalse(club.isJoined)
    }
}
