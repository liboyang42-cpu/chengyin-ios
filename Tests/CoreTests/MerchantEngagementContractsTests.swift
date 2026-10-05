import XCTest
@testable import QuestifyCore

final class MerchantEngagementContractsTests: XCTestCase {
    private func object(_ raw: String) throws -> MerchantBusinessObject { try XCTUnwrap(MerchantEngagementSyntheticFixtures.decode(raw).object) }
    func testSegmentFilterHasExactFiveFieldsAndAllIsNull() throws {
        let fields = MerchantCRMFilter().segmentFields
        XCTAssertEqual(Set(fields.keys), Set(["segment","tagId","sourceType","sourceStart","sourceEnd"]))
        XCTAssertEqual(fields["segment"], .null); XCTAssertNil(fields["keyword"])
    }
    func testExportPreservesAllFiltersAndResetsPage() throws {
        var query = MerchantCustomerQuery(); query.page = 5; query.keyword = "example"; query.segment = "repeat"; query.tagID = 9; query.sourceType = 1; query.sourceStart = "2026-09-01"; query.sourceEnd = "2026-10-01"
        let fields = MerchantCRMFilter(customerQuery: query).exportFields
        XCTAssertEqual(fields.count, 8); XCTAssertEqual(fields["pageNum"], .int(1)); XCTAssertEqual(fields["pageSize"], .int(20))
        XCTAssertEqual(fields["sourceStart"], .string("2026-09-01")); XCTAssertEqual(fields["tagId"], .int(9)); XCTAssertEqual(fields["keyword"], .string("example"))
    }
    func testEmptyExportKeywordIsNullNotListEmptyString() { XCTAssertEqual(MerchantCRMFilter().exportFields["keyword"], .null) }
    func testApplySavedSegmentKeepsCurrentKeyword() throws {
        let filter = try MerchantCRMFilter(savedFields: ["segment":.string("repeat"),"tagId":.null], preservingKeyword: "query")
        XCTAssertEqual(filter.customerQuery.keyword, "query"); XCTAssertEqual(filter.customerQuery.segment, "repeat")
    }
    func testMalformedSavedFilterCannotSilentlyWidenAudience() {
        XCTAssertThrowsError(try MerchantCRMFilter(savedFields: ["tagId": .string("invalid")]))
        XCTAssertThrowsError(try MerchantCRMFilter(savedFields: ["sourceStart": .int(99)]))
        XCTAssertThrowsError(try MerchantCRMFilter(savedFields: ["sourceType": .int(3)]))
    }
    func testSavedSegmentUTF16Limit() throws {
        XCTAssertThrowsError(try MerchantEngagementCommand.saveSegment(name: String(repeating: "😀", count: 16), filter: .init()).request(requestID: "example-request"))
    }
    func testCampaignPreviewNeverCarriesClientIDsOrCouponID() throws {
        let draft = try MerchantCampaignDraft(segmentID: 1, channel: .coupon, couponID: 2, title: "Title", content: "Content")
        XCTAssertEqual(Set(draft.previewFields.keys), Set(["segmentId","channel"]))
        XCTAssertNil(draft.previewFields["merchantId"]); XCTAssertNil(draft.previewFields["customerMemberIds"])
    }
    func testInAppCampaignNormalizesCouponToNull() throws {
        let draft = try MerchantCampaignDraft(segmentID: 1, channel: .inApp, couponID: 2, title: " T ", content: " C ")
        XCTAssertNil(draft.couponID); XCTAssertEqual(draft.fields(requestID: "example")["couponId"], .null); XCTAssertEqual(draft.title, "T")
    }
    func testCouponCampaignRequiresPositiveCouponID() { XCTAssertThrowsError(try MerchantCampaignDraft(segmentID: 1, channel: .coupon, couponID: nil, title: "T", content: "C")) }
    func testCampaignTitleAndContentLengths() {
        XCTAssertThrowsError(try MerchantCampaignDraft(segmentID: 1, channel: .inApp, couponID: nil, title: String(repeating: "a", count: 61), content: "C"))
        XCTAssertThrowsError(try MerchantCampaignDraft(segmentID: 1, channel: .inApp, couponID: nil, title: "T", content: String(repeating: "😀", count: 251)))
    }
    func testCampaignPreviewMissingCountRemainsUnknown() throws {
        let preview = try MerchantAudiencePreview(kind: .campaign, fields: ["deliverableCount":.int(4)])
        XCTAssertNil(preview.counts["consentedCount"]); XCTAssertFalse(preview.isComplete); XCTAssertFalse(preview.canSend)
    }
    func testBroadcastRequiresNineCounts() throws { XCTAssertThrowsError(try MerchantAudiencePreview(kind: .broadcast, fields: ["deliverableCount":.int(4)])) }
    func testBroadcastFilterTotalFallbackIsAudienceNotZero() throws {
        var fields = try object(MerchantEngagementSyntheticFixtures.broadcast); fields.removeValue(forKey: "filterTotalCount")
        XCTAssertEqual(try MerchantAudiencePreview(kind: .broadcast, fields: fields).counts["filterTotalCount"], 7)
    }
    func testBroadcastDailyExhaustionBlocksReview() throws {
        var fields = try object(MerchantEngagementSyntheticFixtures.broadcast); fields["merchantDailyRemaining"] = .int(0)
        XCTAssertFalse(try MerchantAudiencePreview(kind: .broadcast, fields: fields).canSend)
    }
    func testBroadcastAllSerializesEmptyGroupsEvenWhenProvided() throws {
        let audience = try MerchantBroadcastAudience(filter: .init(), scope: .all, groups: ["ignored"])
        XCTAssertEqual(audience.fields["groups"], .array([])); XCTAssertEqual(audience.fields["segment"], .string("all"))
    }
    func testBroadcastTeamRequiresUniqueNonemptyNames() {
        XCTAssertThrowsError(try MerchantBroadcastAudience(filter: .init(), scope: .team, groups: []))
        XCTAssertThrowsError(try MerchantBroadcastAudience(filter: .init(), scope: .team, groups: ["A","A"]))
    }
    func testBroadcastDoesNotTransmitLocalCustomerRoster() throws {
        let audience = try MerchantBroadcastAudience(filter: .init(), scope: .role, groups: [" Guide "])
        let command = MerchantEngagementCommand.broadcast(try .init(audience: audience, content: "Hello"))
        let fields = try XCTUnwrap(command.request(requestID: "example-request").fields)
        XCTAssertEqual(fields["groups"], .array([.string("Guide")])); XCTAssertNil(fields["customerMemberIds"]); XCTAssertNil(fields["merchantId"])
    }
    func testBroadcastUTF16Max120() throws {
        let audience = try MerchantBroadcastAudience(filter: .init(), scope: .all, groups: [])
        XCTAssertThrowsError(try MerchantBroadcastDraft(audience: audience, content: String(repeating: "😀", count: 61)))
    }
    func testDispatchAndRetryHaveEmptyJSONNoInventedIdempotencyField() throws {
        XCTAssertEqual(try MerchantEngagementCommand.dispatchCampaign(1).request(requestID: "example-request").fields, [:])
        XCTAssertEqual(try MerchantEngagementCommand.retryCampaign(1).request(requestID: "example-request").fields, [:])
    }
    func testCampaignTaskWrongIDFailsClosed() throws { XCTAssertThrowsError(try MerchantCampaignTask(object(MerchantEngagementSyntheticFixtures.campaign), expectedID: 99)) }
    func testUnknownCampaignStatusNotSuccessOrActionable() throws {
        var fields = try object(MerchantEngagementSyntheticFixtures.campaign); fields["status"] = .string("FUTURE_STATUS")
        let task = try MerchantCampaignTask(fields); XCTAssertEqual(task.status, "FUTURE_STATUS"); XCTAssertFalse(task.canDispatch); XCTAssertFalse(task.canRetry)
    }
    func testPartialCampaignRequiresRetryableRecipients() throws {
        var fields = try object(MerchantEngagementSyntheticFixtures.campaign); fields["status"] = .string("PARTIAL_FAILED"); fields["retryableCount"] = .int(0)
        XCTAssertFalse(try MerchantCampaignTask(fields).canRetry); fields["retryableCount"] = .int(1); XCTAssertTrue(try MerchantCampaignTask(fields).canRetry)
    }
    func testExportSuccessRequiresNonnegativeRowCount() {
        XCTAssertThrowsError(try MerchantExportTask(["id":.int(1),"status":.string("SUCCESS")]))
        XCTAssertThrowsError(try MerchantExportTask(["id":.int(1),"status":.string("SUCCESS"),"rowCount":.int(-1)]))
    }
    func testUnknownExportStatusRejected() { XCTAssertThrowsError(try MerchantExportTask(["id":.int(1),"status":.string("READY")])) }
    func testExportTokenSurvivesStatusWithoutToken() throws {
        let ticket = try MerchantExportTicket(creation: ["id":.int(1),"status":.string("PENDING"),"downloadToken":.string("synthetic-token")])
        let updated = try ticket.updating(.init(["id":.int(1),"status":.string("SUCCESS"),"rowCount":.int(0)]))
        XCTAssertEqual(updated.downloadToken, "synthetic-token"); XCTAssertTrue(updated.canDownload)
    }
    func testExportTicketRejectsCrossTaskUpdate() throws {
        let ticket = try MerchantExportTicket(creation: ["id":.int(1),"status":.string("PENDING")])
        XCTAssertThrowsError(try ticket.updating(.init(["id":.int(2),"status":.string("FAILED")])))
    }
    func testMissingCreationTokenDoesNotInventDownloadCredential() throws {
        let ticket = try MerchantExportTicket(creation: ["id":.int(1),"status":.string("SUCCESS"),"rowCount":.int(0)])
        XCTAssertFalse(ticket.canDownload)
    }
    func testContactBodyOnlyPurposeNotRequestOrMemberID() throws {
        let command = MerchantEngagementCommand.contact(try .init(61001), .copy)
        let request = try command.request(requestID: "example-request")
        XCTAssertEqual(request.path, "api/merchant/crm/customers/61001/contact"); XCTAssertEqual(request.fields, ["purpose":.string("copy")])
    }
    func testMaskedContactCannotBeUsedAsRealNumber() throws {
        XCTAssertThrowsError(try MerchantContactReceipt(customerID: .init(61001), purpose: .call, fields: ["phone":.string("138****0000")]))
    }
    func testOperatorAcceptanceUsesTokenAndRequestIDWithoutGuessedStore() throws {
        let command = MerchantEngagementCommand.acceptInvitation(try .init(token: "synthetic-invitation-token"))
        let fields = try XCTUnwrap(command.request(requestID: "example-request").fields)
        XCTAssertEqual(Set(fields.keys), Set(["token","requestId"])); XCTAssertFalse(command.lockTarget.contains("synthetic-invitation-token"))
    }
    func testInactiveAccessIsValidOnlyForInvitationContext() throws {
        let access = try MerchantEngagementAccess(["active":.bool(false),"permissions":.array([])])
        XCTAssertNil(access.merchantID); XCTAssertThrowsError(try access.require(["merchant:crm:read"]))
    }
    func testInviteRoutePreservesTokenButRejectsDuplicateQuery() throws {
        let route = try MerchantOperatorInviteRoute(path: "/merchant/team", queryItems: [.init(name: "invite", value: "synthetic-invitation-token")])
        XCTAssertEqual(route.invitation.token, "synthetic-invitation-token")
        XCTAssertThrowsError(try MerchantOperatorInviteRoute(path: "/merchant/team", queryItems: [.init(name:"invite",value:"synthetic-invitation-token"),.init(name:"invite",value:"another-invitation-token")]))
    }
    func testEvidenceSelectionUsesContentSignatureNotClaimedExtension() {
        XCTAssertThrowsError(try MerchantEvidenceSelection(bytes: Data("<script>".utf8), filename: "example.png", mimeType: "image/png"))
        XCTAssertThrowsError(try MerchantEvidenceSelection(bytes: Data([0xff,0xd8,0xff]), filename: "example.png", mimeType: "image/jpeg"))
    }
    func testEvidenceSelectionDoesNotKeepOriginalDevicePath() throws {
        let selected = try MerchantEvidenceSelection.importing(Data([137,80,78,71,13,10,26,10,0]))
        XCTAssertEqual(selected.filename, "evidence.png"); XCTAssertFalse(selected.filename.contains("/"))
    }
}

final class MerchantMutationFailureDispositionTests: XCTestCase {
    func testNoHTTPOrBusinessStatusAloneProvesRollback() {
        for code in [400,401,403,404,408,409,422,429,500,502,503] {
            XCTAssertFalse(MerchantMutationFailureDisposition.provesNoDispatch(MerchantBusinessFailure.rejected(code,"Response")))
            XCTAssertFalse(MerchantMutationFailureDisposition.provesNoDispatch(APIError.httpStatus(code)))
        }
        XCTAssertFalse(MerchantMutationFailureDisposition.provesNoDispatch(APIError.unauthorized))
        XCTAssertFalse(MerchantMutationFailureDisposition.provesNoDispatch(MerchantBusinessFailure.denied))
    }
    func testOnlyTypedLocalDisabledGateProvesNoTransport() {
        XCTAssertTrue(MerchantMutationFailureDisposition.provesNoDispatch(MerchantBusinessFailure.disabled))
        XCTAssertFalse(MerchantMutationFailureDisposition.provesNoDispatch(URLError(.timedOut)))
        XCTAssertFalse(MerchantMutationFailureDisposition.provesNoDispatch(CancellationError()))
    }
}
