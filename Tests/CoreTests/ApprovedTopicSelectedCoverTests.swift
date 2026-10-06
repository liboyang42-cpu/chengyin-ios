import XCTest
@testable import QuestifyCore

@MainActor final class ApprovedTopicSelectedCoverTests: XCTestCase {
    private func fields(_ mutation: (inout [String: ProjectEditJSON]) -> Void = { _ in }) -> ProjectEditJSON {
        var root = ApprovedTopicReviewSynthetic.captureFields().object!, summary = root["summary"]!.object!, cover = ApprovedTopicReviewSynthetic.selectedCoverFields(owner: 7).object!
        mutation(&cover); summary["selectedCover"] = .object(cover); root["summary"] = .object(summary); return .object(root)
    }
    private func decode(_ value: ProjectEditJSON) throws -> ApprovedTopicReviewCapture { try .decode(value, topicID: 7901, observedAuditTaskID: 3301) }
    func testExactSelectionFieldsRoundTripWithoutClaimingPublicMedia() throws {
        let capture = try decode(fields()), cover = try XCTUnwrap(capture.selectedCover)
        XCTAssertEqual(cover.selectionVersion, 9); XCTAssertEqual(cover.contentSlotID, 51); XCTAssertEqual(cover.ownerMemberID, 7); XCTAssertEqual(cover.assetID, "11111111-1111-4111-8111-111111111111"); XCTAssertEqual(cover.contentHash, String(repeating: "a", count: 64)); XCTAssertEqual(cover.legacyImageReference, capture.coverReference)
        XCTAssertEqual(try decode(capture.serializedFields()), capture)
        XCTAssertNil(try decode(ApprovedTopicReviewSynthetic.captureFields()).selectedCover)
    }
    func testAlteredBindingsUnknownFieldsOrAnyApprovalPromotionFailClosed() {
        for (key,value) in [("kind",ProjectEditJSON.string("OTHER")),("schemaVersion",.number(2)),("topicId",.number(9)),("topicConfigVersion",.number(2)),("selectionVersion",.number(0)),("contentSlotId",.number(0)),("bindingState",.string("PUBLISHED")),("approvalProof",.bool(true)),("publicPlayerReadable",.bool(true)),("legacyImageBindingVerified",.bool(true)),("extra",.bool(false)),("legacyTopicImageReference",.string("other"))] {
            XCTAssertThrowsError(try decode(fields { $0[key] = value }),key)
        }
        XCTAssertThrowsError(try decode(fields { $0["selectionVersion"] = .number(Decimal(string:"18446744073709551616")!) }))
    }
    func testAssetNamespaceAliasesAndArbitraryOrBearerLocatorsAreRejected() {
        for (key,value) in [("ownerMemberId",ProjectEditJSON.number(8)),("assetId",.string("33333333-3333-4333-8333-333333333333")),("sourceVersion",.string("latest")),("contentHash",.string("url-hash")),("kind",.string("PUBLIC_TOPIC")),("policyVersion",.string("OTHER"))] {
            XCTAssertThrowsError(try decode(fields { var asset = $0["assetReference"]!.object!; asset[key] = value; $0["assetReference"] = .object(asset) }),key)
        }
        for (key,value) in [("audience",ProjectEditJSON.string("PUBLIC")),("contentHash",.string(String(repeating:"b",count:64))),("path",.string("https://untrusted.invalid/image")),("path",.string("/api/topic/cover/anything?token=secret"))] {
            XCTAssertThrowsError(try decode(fields { var display = $0["authorDisplayReference"]!.object!; display[key] = value; $0["authorDisplayReference"] = .object(display) }),key)
        }
    }
    func testLegacyReferenceByteMismatchIsNotHiddenByUnicodeEquivalence() throws {
        var root = fields().object!, summary = root["summary"]!.object!, cover = summary["selectedCover"]!.object!
        summary["coverReference"] = .string("é"); cover["legacyTopicImageReference"] = .string("e\u{301}"); summary["selectedCover"] = .object(cover); root["summary"] = .object(summary)
        XCTAssertThrowsError(try decode(.object(root)))
    }
}
