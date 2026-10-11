import XCTest
@testable import QuestifyCore

final class ProfilePreferenceRemovalTests: XCTestCase {
    private func snapshot(_ changes: [String: Any] = [:]) throws -> ProfileEditSnapshot {
        var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
            "avatar": " avatar ", "wechat": " QR ", "casePics": " one ;two ", "caseIntroducton": "Case", "tagIds": " 4, 7007 "]
        fields.merge(changes) { _, new in new }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testStrictParsingAcceptsOrderedPositiveIDsAndEmptySelection() {
        XCTAssertEqual(ProfilePreferenceRemoval.parse(" 4, 7007 "), [4, 7007])
        XCTAssertEqual(ProfilePreferenceRemoval.parse(""), []); XCTAssertEqual(ProfilePreferenceRemoval.parse(" \n"), [])
        XCTAssertEqual(ProfilePreferenceRemoval.parse("004,7007"), [4, 7007])
    }
    func testMalformedDuplicateOverflowAndSignedIDsAreNotSilentlyDropped() {
        for raw in ["4,,7007", "4,", ",4", "0", "-4", "+4", "4,4", "04,4", "4,no", "4.0", "４", "99999999999999999999999999999999999"] {
            XCTAssertNil(ProfilePreferenceRemoval.parse(raw), raw)
        }
    }
    func testRemovalAllowsOnlyAnOrderedSubsetIncludingClearAndNoOp() {
        XCTAssertTrue(ProfilePreferenceRemoval.isOrderedSubset([4], of: [4, 7007]))
        XCTAssertTrue(ProfilePreferenceRemoval.isOrderedSubset([], of: [4, 7007]))
        XCTAssertTrue(ProfilePreferenceRemoval.isOrderedSubset([4, 7007], of: [4, 7007]))
        XCTAssertFalse(ProfilePreferenceRemoval.isOrderedSubset([7007, 4], of: [4, 7007]))
        XCTAssertFalse(ProfilePreferenceRemoval.isOrderedSubset([8], of: [4, 7007]))
        XCTAssertFalse(ProfilePreferenceRemoval.isOrderedSubset([4, 4], of: [4, 7007]))
        XCTAssertFalse(ProfilePreferenceRemoval.isOrderedSubset([], of: [4, 4]))
    }
    func testStagedSelectionTakesPrecedenceAndInvalidStagingFailsClosed() throws {
        let original = try snapshot(); var draft = original.draft
        XCTAssertEqual(ProfilePreferenceRemoval.selection(draft: draft, snapshot: original), [4, 7007])
        draft.routePreferenceIDs = [9, 4]; XCTAssertEqual(ProfilePreferenceRemoval.selection(draft: draft, snapshot: original), [9, 4])
        draft.routePreferenceIDs = []; XCTAssertEqual(ProfilePreferenceRemoval.selection(draft: draft, snapshot: original), [])
        draft.routePreferenceIDs = [4, 4]; XCTAssertNil(ProfilePreferenceRemoval.selection(draft: draft, snapshot: original))
    }
    func testSelfLabelsAreOptionalExactDisplayMetadataWithIDFallback() throws {
        let value = try snapshot(["sysCategoryList": [["id": 4, "categoryName": " City walks "], ["id": 7007]]])
        XCTAssertEqual(value.preferenceNames[4], " City walks "); XCTAssertNil(value.preferenceNames[7007])
        XCTAssertTrue(try snapshot(["sysCategoryList": "malformed-labels"]).preferenceNames.isEmpty)
        XCTAssertEqual(try snapshot(["sysCategoryList": "malformed-labels"]).tagIds, " 4, 7007 ")
    }
    func testAmbiguousDuplicateBlankAndNonpositiveLabelsAreNotUsed() throws {
        let labels: [[String: Any]] = [["id": 4, "categoryName": "One"], ["id": 4, "categoryName": "Other"],
            ["id": 7007, "categoryName": " "], ["id": 0, "categoryName": "Invalid"], ["id": 9, "categoryName": "Valid"]]
        XCTAssertEqual(try snapshot(["sysCategoryList": labels]).preferenceNames, [9: "Valid"])
    }
    func testExistingMissingTagIDsReadbackContractStillUsesSysCategoryList() throws {
        let fields: [String: Any] = ["id": 901, "nickname": "Name", "introduction": "", "avatar": "", "wechat": "", "casePics": "",
            "sysCategoryList": [["id": 4, "categoryName": "Walks"], ["id": 7007, "categoryName": "Retired"]]]
        let value = try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(value.tagIds, "4,7007"); XCTAssertEqual(value.preferenceNames[7007], "Retired")
    }
    func testReviewMetadataIsNotEncodedAndOtherReplacementFieldsArePreserved() throws {
        let original = try snapshot(); var draft = original.draft; draft.routePreferenceIDs = [4]
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertEqual(payload.preferenceIDs, [4]); XCTAssertEqual(payload.tagIds, "4")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertNil(object["preferenceIDs"]); XCTAssertNil(object["preferenceNames"]); XCTAssertNil(object["member_id"])
        XCTAssertEqual(Set(object.keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds"]))
        XCTAssertEqual(payload.wechat, original.wechat); XCTAssertEqual(payload.casePics, original.casePics); XCTAssertEqual(payload.avatar, original.avatar)
    }
    func testClearIsExplicitEmptyStringAndReadbackRequiresTheExactSelection() throws {
        let original = try snapshot(); var draft = original.draft; draft.routePreferenceIDs = []
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertEqual(payload.tagIds, ""); XCTAssertEqual(payload.preferenceIDs, [])
        XCTAssertTrue(payload.matches(try snapshot(["tagIds": ""]))); XCTAssertFalse(payload.matches(original))
    }
    func testNoProposalPreservesOriginalWireBytesAndNoReviewMetadata() throws {
        let original = try snapshot(); let payload = try ProfileEditPayload(draft: original.draft, preserving: original)
        XCTAssertEqual(Array(payload.tagIds.utf8), Array(original.tagIds.utf8)); XCTAssertNil(payload.preferenceIDs)
    }
}
