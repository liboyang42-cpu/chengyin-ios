import XCTest
@testable import QuestifyCore

final class ProfileIdentityShareCardTests: XCTestCase {
    private func profile(_ values: [String: Any] = ["id": 7, "nickname": "Synthetic explorer", "introduction": "City walks"]) throws -> SocialPublicProfile {
        try JSONDecoder().decode(SocialPublicProfile.self, from: JSONSerialization.data(withJSONObject: values))
    }
    func testSelfCardExportsOnlyNameAndIntroduction() throws {
        let p = try profile(["id": 7, "nickname": "Synthetic", "introduction": "City walks", "avatar": "https://private.invalid/a", "wechat": "contact", "token": "secret", "levelId": 9])
        let card = try XCTUnwrap(ProfileIdentityShareCard(profile: p, owner: .init(accountID: 7, epoch: 1)))
        XCTAssertEqual(card.text(title: "City identity card"), "City identity card\n\nSynthetic\n\nCity walks")
    }
    func testOtherMemberCannotProduceSelfCard() throws {
        XCTAssertNil(ProfileIdentityShareCard(profile: try profile(), owner: .init(accountID: 8, epoch: 1)))
    }
    func testGuestCannotProduceSelfCard() throws {
        XCTAssertNil(ProfileIdentityShareCard(profile: try profile(), owner: .init(accountID: nil, epoch: 1)))
    }
    func testMissingNameHasNoInventedIdentity() throws {
        XCTAssertNil(ProfileIdentityShareCard(profile: try profile(["id": 7]), owner: .init(accountID: 7, epoch: 1)))
    }
    func testMissingIntroductionIsNotSynthesized() throws {
        let c = try XCTUnwrap(ProfileIdentityShareCard(profile: try profile(["id": 7, "nickname": "Synthetic"]), owner: .init(accountID: 7, epoch: 1)))
        XCTAssertEqual(c.text(title: "Card"), "Card\n\nSynthetic")
    }
    func testOversizedPublicFieldsFailClosedWithoutTruncation() throws {
        for row in [["id": 7, "nickname": String(repeating: "a", count: 1025)], ["id": 7, "nickname": "Synthetic", "introduction": String(repeating: "a", count: 16385)]] as [[String: Any]] {
            XCTAssertNil(ProfileIdentityShareCard(profile: try profile(row), owner: .init(accountID: 7, epoch: 1)))
        }
    }
    func testIdentityKeyUsesExactUnicodeBytes() throws {
        let a = try profile(["id": 7, "nickname": "caf\u{00e9}"]), b = try profile(["id": 7, "nickname": "cafe\u{0301}"])
        XCTAssertNotEqual(ProfileIdentityShareSource(profile: a), ProfileIdentityShareSource(profile: b))
        XCTAssertNotEqual(ProfileIdentityShareCard(profile: a, owner: .init(accountID: 7, epoch: 1)), ProfileIdentityShareCard(profile: b, owner: .init(accountID: 7, epoch: 1)))
    }
    func testLiteralPublicTextIsNotInterpretedAsMarkupOrURL() throws {
        let c = try XCTUnwrap(ProfileIdentityShareCard(profile: try profile(["id": 7, "nickname": "%@ <name>", "introduction": "Literal **text**"]), owner: .init(accountID: 7, epoch: 1)))
        XCTAssertEqual(c.text(title: "Card"), "Card\n\n%@ <name>\n\nLiteral **text**")
    }
}
