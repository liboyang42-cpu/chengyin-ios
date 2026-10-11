import XCTest
@testable import QuestifyCore

final class ProfileContactQRRemovalTests: XCTestCase {
    private func snapshot(wechat: String = " https://qr.invalid/e\u{301}.png ") throws -> ProfileEditSnapshot {
        let fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
            "avatar": " avatar ", "wechat": wechat, "casePics": " one ;two ", "caseIntroducton": "Case", "tagIds": "7,4"]
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func json(_ payload: ProfileEditPayload) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    }
    func testNoProposalPreservesExactQRBytesAndExistingPayloadKeys() throws {
        let original = try snapshot(), payload = try ProfileEditPayload(draft: original.draft, preserving: original)
        XCTAssertEqual(Array(payload.wechat.utf8), Array(original.wechat.utf8)); XCTAssertFalse(payload.removesContactQR)
        XCTAssertEqual(Set(try json(payload).keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds"]))
    }
    func testExplicitRemovalSerializesOnlyEmptyWechatWithNoNewCapabilityFields() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesContactQR = true
        let payload = try ProfileEditPayload(draft: draft, preserving: original), object = try json(payload)
        XCTAssertEqual(object["wechat"] as? String, ""); XCTAssertTrue(payload.removesContactQR)
        XCTAssertNil(object["removesContactQR"]); XCTAssertNil(object["member_id"]); XCTAssertNil(object["accountID"])
        XCTAssertEqual(Set(object.keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds"]))
    }
    func testRemovalPreservesOtherTextMediaPreferencesAndCaseProposal() throws {
        let original = try snapshot(); var draft = original.draft
        draft.caseIntroduction = " New case e\u{301}\n"; draft.routePreferenceIDs = [4, 7]; draft.removesContactQR = true
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertEqual(payload.name, original.nickname); XCTAssertEqual(payload.introduction, original.introduction)
        XCTAssertEqual(Array(payload.avatar.utf8), Array(original.avatar.utf8)); XCTAssertEqual(Array(payload.casePics.utf8), Array(original.casePics.utf8))
        XCTAssertEqual(payload.caseIntroduction, draft.caseIntroduction); XCTAssertEqual(payload.tagIds, "4,7")
    }
    func testRestoreMeansExactOriginalAndNoDirtyContactChange() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesContactQR = true
        XCTAssertTrue(draft.hasChanges(comparedTo: original)); draft.removesContactQR = false
        XCTAssertFalse(draft.hasChanges(comparedTo: original))
        XCTAssertEqual(Array(try ProfileEditPayload(draft: draft, preserving: original).wechat.utf8), Array(original.wechat.utf8))
    }
    func testAlreadyEmptyQRRemovalIsNoOpAndNotShownAsRemovalReview() throws {
        let original = try snapshot(wechat: ""); var draft = original.draft; draft.removesContactQR = true
        XCTAssertFalse(draft.hasChanges(comparedTo: original))
        XCTAssertFalse(try ProfileEditPayload(draft: draft, preserving: original).removesContactQR)
    }
    func testNormalizationPreservesRemovalIntentAndAvatarFingerprintBindsIt() throws {
        let original = try snapshot(); var draft = original.draft
        let before = ProfileAvatarExact.draft(draft); draft.removesContactQR = true
        XCTAssertTrue(draft.normalized.removesContactQR); XCTAssertNotEqual(ProfileAvatarExact.draft(draft), before)
        draft.removesContactQR = false; XCTAssertEqual(ProfileAvatarExact.draft(draft), before)
    }
    func testRemovalReadbackRequiresEmptyQRCode() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesContactQR = true
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertTrue(payload.matches(try snapshot(wechat: "")))
        XCTAssertFalse(payload.matches(original)); XCTAssertFalse(payload.matches(try snapshot(wechat: " ")))
        XCTAssertFalse(payload.matches(try snapshot(wechat: "https://qr.invalid/replacement.png")))
    }
    func testBothCaseDescriptionAndQRChangesMustMatchReadback() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesContactQR = true; draft.caseIntroduction = "Local"
        XCTAssertFalse(try ProfileEditPayload(draft: draft, preserving: original).matches(snapshot(wechat: "")))
    }
}
