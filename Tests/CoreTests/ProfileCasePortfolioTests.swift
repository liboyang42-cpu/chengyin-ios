import XCTest
@testable import QuestifyCore

final class ProfileCasePortfolioTests: XCTestCase {
    private func snapshot(_ fields: [String: Any] = [:], includeCase: Bool = true) throws -> ProfileEditSnapshot {
        var data: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
            "avatar": " old-avatar ", "wechat": " old-wechat ", "casePics": " first ;second;first ", "tagIds": "7,4"]
        if includeCase { data["caseIntroducton"] = " Original e\u{301}\n" }
        data.merge(fields) { _, new in new }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
    }
    private func object(_ payload: ProfileEditPayload) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
    }
    func testMissingFieldIsUnavailableButExistingProfileStillDecodes() throws {
        XCTAssertNil(try snapshot(includeCase: false).caseIntroduction)
    }
    func testExplicitNullIsEmptyAndWrongTypeFailsClosed() throws {
        XCTAssertEqual(try snapshot(["caseIntroducton": NSNull()]).caseIntroduction, "")
        XCTAssertThrowsError(try snapshot(["caseIntroducton": 17]))
        XCTAssertThrowsError(try snapshot(["caseIntroducton": ["private"]]))
    }
    func testCorrectedSpellingIsNotAcceptedAsTheWireField() throws {
        XCTAssertNil(try snapshot(["caseIntroduction": "wrong field"], includeCase: false).caseIntroduction)
    }
    func testUntouchedCaseFieldIsOmittedAndImagesRemainExact() throws {
        let original = try snapshot(); var draft = original.draft; draft.name = "Updated"
        let payload = try ProfileEditPayload(draft: draft, preserving: original), json = try object(payload)
        XCTAssertNil(json["caseIntroducton"]); XCTAssertNil(json["caseIntroduction"])
        XCTAssertEqual(Array(payload.casePics.utf8), Array(original.casePics.utf8))
        XCTAssertEqual(payload.wechat, original.wechat); XCTAssertEqual(payload.avatar, original.avatar)
        XCTAssertEqual(payload.tagIds, original.tagIds)
    }
    func testExplicitEditEncodesOnlyExactMisspelledBackendKeyAndBytes() throws {
        let original = try snapshot(), text = " \te\u{301}\n新的作品 "
        var draft = original.draft; draft.caseIntroduction = text
        let payload = try ProfileEditPayload(draft: draft, preserving: original), json = try object(payload)
        XCTAssertNil(json["caseIntroduction"])
        XCTAssertEqual(Array(try XCTUnwrap(json["caseIntroducton"] as? String).utf8), Array(text.utf8))
        XCTAssertEqual(Set(json.keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds", "caseIntroducton"]))
    }
    func testExplicitEmptyClearsAndMissingSnapshotCannotBeOverwritten() throws {
        let original = try snapshot(); var draft = original.draft; draft.caseIntroduction = ""
        XCTAssertEqual(try object(ProfileEditPayload(draft: draft, preserving: original))["caseIntroducton"] as? String, "")
        XCTAssertThrowsError(try ProfileEditPayload(draft: draft, preserving: snapshot(includeCase: false)))
    }
    func testNormalizationLeavesCaseTextBytesUntouched() throws {
        let text = " \te\u{301}\n作品 "
        let draft = ProfileEditDraft(name: " Name ", introduction: " Bio ", caseIntroduction: text)
        XCTAssertEqual(draft.normalized.name, "Name"); XCTAssertEqual(draft.normalized.introduction, "Bio")
        XCTAssertEqual(Array(try XCTUnwrap(draft.normalized.caseIntroduction).utf8), Array(text.utf8))
    }
    func testDirtyCheckIsExactForCaseBytesAndNoOpIsNotDirty() throws {
        let original = try snapshot(["caseIntroducton": "é"]); var draft = original.draft
        XCTAssertFalse(draft.hasChanges(comparedTo: original))
        draft.caseIntroduction = "é"; XCTAssertFalse(draft.hasChanges(comparedTo: original))
        draft.caseIntroduction = "e\u{301}"; XCTAssertTrue(draft.hasChanges(comparedTo: original))
        draft.caseIntroduction = ""; XCTAssertTrue(draft.hasChanges(comparedTo: original))
    }
    func testReadbackMustContainExactChangedCaseText() throws {
        let original = try snapshot(); var draft = original.draft; draft.caseIntroduction = "e\u{301}"
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertTrue(payload.matches(try snapshot(["caseIntroducton": "e\u{301}"])))
        XCTAssertFalse(payload.matches(try snapshot(["caseIntroducton": "é"])))
        XCTAssertFalse(payload.matches(try snapshot(includeCase: false)))
        XCTAssertFalse(payload.matches(try snapshot(["caseIntroducton": ""])))
    }
    func testUntouchedCaseDoesNotClaimAuthorityOverConcurrentText() throws {
        let original = try snapshot(), payload = try ProfileEditPayload(draft: original.draft, preserving: original)
        XCTAssertTrue(payload.matches(try snapshot(["caseIntroducton": "another server value"])))
    }
    func testExactOptionalTextDistinguishesMissingEmptyAndUnicode() {
        XCTAssertTrue(ProfileCasePortfolio.sameText(nil, nil)); XCTAssertFalse(ProfileCasePortfolio.sameText(nil, ""))
        XCTAssertTrue(ProfileCasePortfolio.sameText("", "")); XCTAssertFalse(ProfileCasePortfolio.sameText("é", "e\u{301}"))
    }
    func testImageProjectionPreservesOrderDuplicatesAndNonblankBytes() {
        let portfolio = ProfileCasePortfolio(casePics: " ; first ;second;; first ;\n")
        XCTAssertEqual(portfolio.images, [" first ", "second", " first "]); XCTAssertEqual(portfolio.omittedImageCount, 0)
    }
    func testEmptyAndOversizedImageProjectionIsExplicitlyBounded() {
        XCTAssertTrue(ProfileCasePortfolio(casePics: " ;\n; ").images.isEmpty)
        let portfolio = ProfileCasePortfolio(casePics: Array(repeating: "x", count: 103).joined(separator: ";"))
        XCTAssertEqual(portfolio.images.count, 100); XCTAssertEqual(portfolio.omittedImageCount, 3)
    }
    func testAvatarFingerprintsCoverCaseTextPresenceAndExactBytes() throws {
        let missing = try snapshot(includeCase: false), empty = try snapshot(["caseIntroducton": ""])
        XCTAssertNotEqual(ProfileAvatarExact.snapshot(missing), ProfileAvatarExact.snapshot(empty))
        XCTAssertNotEqual(ProfileAvatarExact.snapshot(try snapshot(["caseIntroducton": "é"])),
                          ProfileAvatarExact.snapshot(try snapshot(["caseIntroducton": "e\u{301}"])))
        var first = missing.draft, other = first; first.caseIntroduction = "é"; other.caseIntroduction = "e\u{301}"
        XCTAssertNotEqual(ProfileAvatarExact.draft(first), ProfileAvatarExact.draft(other))
        XCTAssertNotEqual(ProfileAvatarExact.draft(missing.draft), ProfileAvatarExact.draft(first))
    }
}
