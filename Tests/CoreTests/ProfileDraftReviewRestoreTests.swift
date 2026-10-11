import XCTest
@testable import QuestifyCore

final class ProfileDraftReviewRestoreTests: XCTestCase {
    private func snapshot(_ changes: [String: Any] = [:]) throws -> ProfileEditSnapshot {
        var fields: [String: Any] = ["id": 901, "nickname": "Name", "introduction": "Bio", "caseIntroducton": "Case",
            "avatar": "SECRET_AVATAR_REF", "wechat": "SECRET_QR_REF", "casePics": "SECRET_IMAGE_ONE;SECRET_IMAGE_TWO", "tagIds": "4,7"]
        fields.merge(changes) { _, new in new }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func summary(_ draft: ProfileEditDraft, _ original: ProfileEditSnapshot) throws -> ProfileEditReviewSummary {
        .init(snapshot: original, payload: try ProfileEditPayload(draft: draft, preserving: original))
    }
    func testUnchangedDraftHasNoChanges() throws {
        let original = try snapshot(); XCTAssertTrue(try summary(original.draft, original).changes.isEmpty)
    }
    func testTextPreferencesAndRemovalChangesAppearOnceInStableOrder() throws {
        let original = try snapshot(); var draft = original.draft
        draft.name = "New"; draft.introduction = "New bio"; draft.caseIntroduction = "New case"
        draft.routePreferenceIDs = [7]; draft.removesContactQR = true; draft.removesCasePictures = true
        let changes = try summary(draft, original).changes
        XCTAssertEqual(changes.map(\.field), [.name, .introduction, .caseIntroduction, .preferences, .contactQR, .casePictures])
        XCTAssertEqual(Set(changes.map(\.id)).count, changes.count)
        XCTAssertEqual(changes[0].before, .text("Name")); XCTAssertEqual(changes[0].after, .text("New"))
        XCTAssertEqual(changes[3].before, .selection("4,7")); XCTAssertEqual(changes[3].after, .selection("7"))
        XCTAssertEqual(changes[4].after, .present(false)); XCTAssertEqual(changes[5].after, .imageCount(0))
    }
    func testCanonicalUnicodeChangesAreNotHiddenBySwiftStringEquality() throws {
        let original = try snapshot(["caseIntroducton": "é"]); var draft = original.draft; draft.caseIntroduction = "e\u{301}"
        let changes = try summary(draft, original).changes; XCTAssertEqual(changes.count, 1)
        XCTAssertNotEqual(changes[0].before, changes[0].after)
        XCTAssertEqual(changes[0].after, .text("e\u{301}"))
    }
    func testReviewUsesActualNormalizedPayloadNotUnsubmittedScratchBytes() throws {
        let original = try snapshot(); var draft = original.draft; draft.name = " New \n"; draft.introduction = "  "
        let changes = try summary(draft, original).changes
        XCTAssertEqual(changes[0].after, .text("New")); XCTAssertEqual(changes[1].after, .text(""))
    }
    func testExplicitEmptyAndWhitespaceCaseDescriptionsRemainDistinct() throws {
        let original = try snapshot(); var empty = original.draft; empty.caseIntroduction = ""
        var spaces = original.draft; spaces.caseIntroduction = " \n"
        XCTAssertEqual(try summary(empty, original).changes[0].after, .text(""))
        XCTAssertEqual(try summary(spaces, original).changes[0].after, .text(" \n"))
        XCTAssertNotEqual(try summary(empty, original), try summary(spaces, original))
    }
    func testRawImageReferencesNeverAppearInComparisonPresentation() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesContactQR = true; draft.removesCasePictures = true
        let comparison = try summary(draft, original)
        XCTAssertEqual(comparison.changes[0].before, .present(true)); XCTAssertEqual(comparison.changes[1].before, .imageCount(2))
        XCTAssertFalse(String(reflecting: comparison).contains("SECRET_"))
    }
    func testImageCountIncludesAllReferencesBeyondPreviewCap() throws {
        let original = try snapshot(["casePics": Array(repeating: "image", count: 129).joined(separator: ";")]); var draft = original.draft
        draft.removesCasePictures = true
        XCTAssertEqual(try summary(draft, original).changes[0].before, .imageCount(129))
    }
    func testClearPreferenceReviewIncludesExactOldWireAndEmptyResult() throws {
        let original = try snapshot(["tagIds": " 4,7 "]); var draft = original.draft; draft.routePreferenceIDs = []
        let change = try XCTUnwrap(summary(draft, original).changes.first)
        XCTAssertEqual(change.before, .selection(" 4,7 ")); XCTAssertEqual(change.after, .selection(""))
    }
    func testIneffectiveImageClearDoesNotInventAChange() throws {
        let original = try snapshot(["wechat": "", "casePics": "; ;"]); var draft = original.draft
        draft.removesContactQR = true; draft.removesCasePictures = true
        XCTAssertTrue(try summary(draft, original).changes.isEmpty)
    }
}
