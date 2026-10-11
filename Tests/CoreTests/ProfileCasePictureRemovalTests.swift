import XCTest
@testable import QuestifyCore

final class ProfileCasePictureRemovalTests: XCTestCase {
    private func snapshot(pictures: String = " one ;two; one ") throws -> ProfileEditSnapshot {
        let fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
            "avatar": " avatar ", "wechat": " QR ", "casePics": pictures, "caseIntroducton": " Original case ", "tagIds": "7,4"]
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testNoProposalPreservesEveryOriginalDelimiterAndImageByte() throws {
        let original = try snapshot(pictures: "one;;two;"), payload = try ProfileEditPayload(draft: original.draft, preserving: original)
        XCTAssertEqual(Array(payload.casePics.utf8), Array(original.casePics.utf8)); XCTAssertFalse(payload.removesCasePictures)
    }
    func testExplicitRemovalWritesOnlyExistingEmptyCasePicsKey() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesCasePictures = true
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertEqual(payload.casePics, ""); XCTAssertTrue(payload.removesCasePictures)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(object["casePics"] as? String, ""); XCTAssertNil(object["removesCasePictures"])
        XCTAssertEqual(Set(object.keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds"]))
    }
    func testClearPreservesDescriptionQRAvatarAndPreferences() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesCasePictures = true; draft.caseIntroduction = " New case "
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertEqual(payload.caseIntroduction, " New case "); XCTAssertEqual(payload.wechat, original.wechat)
        XCTAssertEqual(payload.avatar, original.avatar); XCTAssertEqual(payload.tagIds, original.tagIds)
        XCTAssertEqual(payload.name, original.nickname); XCTAssertEqual(payload.introduction, original.introduction)
    }
    func testKeepOriginalRemovesOnlyClearIntentAndRestoresExactWireValue() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesCasePictures = true
        XCTAssertTrue(draft.hasChanges(comparedTo: original)); draft.removesCasePictures = false
        XCTAssertFalse(draft.hasChanges(comparedTo: original))
        XCTAssertEqual(Array(try ProfileEditPayload(draft: draft, preserving: original).casePics.utf8), Array(original.casePics.utf8))
    }
    func testBlankAndDelimiterOnlySourcesAreNotEffectiveRemovalProposals() throws {
        for raw in ["", ";;", " ; \n ;"] {
            let original = try snapshot(pictures: raw); var draft = original.draft; draft.removesCasePictures = true
            XCTAssertFalse(draft.hasChanges(comparedTo: original)); let payload = try ProfileEditPayload(draft: draft, preserving: original)
            XCTAssertFalse(payload.removesCasePictures); XCTAssertEqual(Array(payload.casePics.utf8), Array(raw.utf8))
        }
    }
    func testCountIncludesDuplicatesAndImagesBeyondPreviewCap() throws {
        let raw = (0..<125).map { "image-\($0)" }.joined(separator: ";")
        let images = ProfileCasePortfolio(casePics: raw)
        XCTAssertEqual(images.images.count, 100); XCTAssertEqual(images.omittedImageCount, 25); XCTAssertEqual(images.imageCount, 125)
        XCTAssertEqual(ProfileCasePortfolio(casePics: "one;;one; ").imageCount, 2)
        let original = try snapshot(pictures: raw); var draft = original.draft; draft.removesCasePictures = true
        XCTAssertEqual(try ProfileEditPayload(draft: draft, preserving: original).casePics, "")
    }
    func testNormalizationAndAvatarFingerprintRetainAllImageRemovalIntent() throws {
        var draft = try snapshot().draft; let before = ProfileAvatarExact.draft(draft)
        draft.removesCasePictures = true; XCTAssertTrue(draft.normalized.removesCasePictures)
        XCTAssertNotEqual(ProfileAvatarExact.draft(draft), before)
        draft.removesCasePictures = false; XCTAssertEqual(ProfileAvatarExact.draft(draft), before)
    }
    func testReadbackMustContainExactlyEmptyCasePicsAfterClear() throws {
        let original = try snapshot(); var draft = original.draft; draft.removesCasePictures = true
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertTrue(payload.matches(try snapshot(pictures: ""))); XCTAssertFalse(payload.matches(original))
        XCTAssertFalse(payload.matches(try snapshot(pictures: ";"))); XCTAssertFalse(payload.matches(try snapshot(pictures: "one")))
    }
    func testConcurrentTextQRCodeAndPictureChangesHaveIndependentIntent() throws {
        let original = try snapshot(); var draft = original.draft
        draft.removesCasePictures = true; draft.removesContactQR = true; draft.caseIntroduction = "Revised"; draft.routePreferenceIDs = [4]
        let payload = try ProfileEditPayload(draft: draft, preserving: original)
        XCTAssertEqual(payload.casePics, ""); XCTAssertEqual(payload.wechat, ""); XCTAssertEqual(payload.caseIntroduction, "Revised")
        XCTAssertEqual(payload.tagIds, "4"); XCTAssertTrue(payload.removesCasePictures); XCTAssertTrue(payload.removesContactQR)
    }
}
