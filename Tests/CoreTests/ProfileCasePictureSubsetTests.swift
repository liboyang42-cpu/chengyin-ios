import XCTest
@testable import QuestifyCore

final class ProfileCasePictureSubsetTests: XCTestCase {
    private func snapshot(_ pictures: String = " first ;; duplicate ; duplicate ;last;") throws -> ProfileEditSnapshot {
        try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id": 901, "nickname": "Original", "introduction": "Intro", "avatar": "avatar",
             "wechat": "qr", "casePics": pictures, "caseIntroducton": "Case", "tagIds": "7,4"]))
    }
    func testDuplicateReferencesKeepDistinctOriginalPositionsAndBytes() throws {
        let source = try snapshot(), subset = try ProfileCasePictureSubset(source: source.casePics, retainedIndices: [0, 2, 3])
        XCTAssertEqual(subset.originalCount, 4); XCTAssertEqual(subset.retainedCount, 3)
        XCTAssertEqual(Array(subset.wireValue.utf8), Array(" first ; duplicate ;last".utf8))
        XCTAssertTrue(subset.hasChanges)
    }
    func testNilAndFullSelectionsPreserveOriginalDelimiters() throws {
        let source = try snapshot(), full = try ProfileCasePictureSubset(source: source.casePics, retainedIndices: [0,1,2,3])
        XCTAssertFalse(full.hasChanges); XCTAssertEqual(Array(full.wireValue.utf8), Array(source.casePics.utf8))
        var draft = source.draft; draft.casePictureSubset = full
        let payload = try ProfileEditPayload(draft: draft, preserving: source)
        XCTAssertFalse(payload.changesCasePictures); XCTAssertFalse(draft.hasChanges(comparedTo: source))
        XCTAssertEqual(Array(payload.casePics.utf8), Array(source.casePics.utf8))
    }
    func testEmptySubsetIsExplicitClearButEmptySourceIsNoOp() throws {
        let source = try snapshot(), empty = try ProfileCasePictureSubset(source: source.casePics, retainedIndices: [])
        var draft = source.draft; draft.casePictureSubset = empty
        let payload = try ProfileEditPayload(draft: draft, preserving: source)
        XCTAssertEqual(payload.casePics, ""); XCTAssertTrue(payload.changesCasePictures)
        let blank = try ProfileCasePictureSubset(source: "; ;", retainedIndices: [])
        XCTAssertFalse(blank.hasChanges); XCTAssertEqual(blank.wireValue, "; ;")
    }
    func testOrderDuplicateIndexOutOfRangeAndOversizedSourceAreRejected() throws {
        for indices in [[1,0], [0,0], [-1], [4], [0,3,2]] {
            XCTAssertThrowsError(try ProfileCasePictureSubset(source: "a;b;c;d", retainedIndices: indices))
        }
        XCTAssertThrowsError(try ProfileCasePictureSubset(source: String(repeating: "a", count: 65537), retainedIndices: []))
        XCTAssertThrowsError(try ProfileCasePictureSubset(source: Array(repeating: "a", count: 101).joined(separator: ";"), retainedIndices: []))
    }
    func testOnlyOriginalSourceMatchesAndNormalizationCannotSubstituteIt() throws {
        let subset = try ProfileCasePictureSubset(source: "é;two", retainedIndices: [1])
        XCTAssertFalse(subset.matches(source: "e\u{301};two"))
        XCTAssertNotEqual(subset, try ProfileCasePictureSubset(source: "e\u{301};two", retainedIndices: [1]))
        var draft = try snapshot("é;two").draft; draft.casePictureSubset = subset
        XCTAssertThrowsError(try ProfileEditPayload(draft: draft, preserving: snapshot("e\u{301};two")))
    }
    func testPayloadUsesOnlyExistingWireKeyAndPreservesOtherFields() throws {
        let source = try snapshot(); var draft = source.draft
        draft.casePictureSubset = try .init(source: source.casePics, retainedIndices: [1,3])
        let payload = try ProfileEditPayload(draft: draft, preserving: source)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["name","introduction","avatar","wechat","casePics","tagIds"]))
        XCTAssertEqual(payload.casePics, " duplicate ;last")
        XCTAssertEqual(payload.avatar, source.avatar); XCTAssertEqual(payload.wechat, source.wechat); XCTAssertEqual(payload.tagIds, source.tagIds)
        XCTAssertNil(object["casePictureSubset"])
    }
    func testConflictingClearAllAndSubsetIntentIsRejected() throws {
        let source = try snapshot(); var draft = source.draft
        draft.casePictureSubset = try .init(source: source.casePics, retainedIndices: [0]); draft.removesCasePictures = true
        XCTAssertFalse(draft.isValid); XCTAssertThrowsError(try ProfileEditPayload(draft: draft, preserving: source))
    }
    func testSubsetSurvivesNormalizationAndExactAvatarFingerprint() throws {
        let source = try snapshot(); var draft = source.draft; let prior = ProfileAvatarExact.draft(draft)
        draft.casePictureSubset = try .init(source: source.casePics, retainedIndices: [0,2])
        XCTAssertEqual(draft.normalized.casePictureSubset, draft.casePictureSubset)
        XCTAssertNotEqual(ProfileAvatarExact.draft(draft), prior)
        let first = ProfileAvatarExact.draft(draft)
        draft.casePictureSubset = try .init(source: source.casePics, retainedIndices: [0,1])
        XCTAssertNotEqual(ProfileAvatarExact.draft(draft), first)
    }
    func testReviewShowsTrueRetainedCountAndReadbackRequiresExactBytes() throws {
        let source = try snapshot("one;é;three"); var draft = source.draft
        draft.casePictureSubset = try .init(source: source.casePics, retainedIndices: [1,2])
        let payload = try ProfileEditPayload(draft: draft, preserving: source)
        let change = try XCTUnwrap(ProfileEditReviewSummary(snapshot: source, payload: payload).changes.first)
        XCTAssertEqual(change.field, .casePictures); XCTAssertEqual(change.before, .imageCount(3)); XCTAssertEqual(change.after, .imageCount(2))
        XCTAssertTrue(payload.matches(try snapshot("é;three")))
        XCTAssertFalse(payload.matches(try snapshot("e\u{301};three")))
        XCTAssertFalse(payload.matches(try snapshot("é;three;")))
    }
}
