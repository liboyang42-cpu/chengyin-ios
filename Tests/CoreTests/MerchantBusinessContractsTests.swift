import XCTest
@testable import QuestifyCore

final class MerchantBusinessContractsTests: XCTestCase {
    private func object(_ raw: String) throws -> MerchantBusinessObject { try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(raw).object) }
    private func document(_ query: MerchantBusinessQuery) throws -> MerchantBusinessDocument { try .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)) }
    func testAllReadFixturesDecode() throws {
        let queries: [MerchantBusinessQuery] = [.customers(.init()), .customer(try .init(61001)), .aftercare(.pending, page: 1), .refund(try .init(62001)), .reviews(page: 1), .overview, .redemptions(filter: "all", page: 1), .entries(source: "all", page: 1), .batches(page: 1), .batch(try .init(66001)), .redemption(recordID: "64001"), .operators, .roles, .verificationRecords]
        for query in queries { XCTAssertEqual(try document(query).query, query) }
    }
    func testCustomerQueryPreservesNullsAndEmptyKeyword() throws {
        let fields = MerchantCustomerQuery().fields
        XCTAssertEqual(fields.count, 8); XCTAssertEqual(fields["keyword"], .string("")); XCTAssertEqual(fields["tagId"], .null)
        XCTAssertNil(fields["merchantId"]); XCTAssertEqual(fields["pageSize"], .int(20))
    }
    func testNegativeCustomerPageRejected() { var query = MerchantCustomerQuery(); query.page = 0; XCTAssertThrowsError(try query.validate()) }
    func testUnknownCustomerSegmentRejected() { var query = MerchantCustomerQuery(); query.segment = "everyone"; XCTAssertThrowsError(try query.validate()) }
    func testAftercareUsesQueryParametersNotBody() throws {
        let request = try MerchantBusinessQuery.aftercare(.processing, page: 2).request()
        XCTAssertEqual(request.query, ["bucket":"PROCESSING", "pageNum":"2", "pageSize":"20"]); XCTAssertEqual(request.body, .none)
    }
    func testCustomerDetailRejectsWrongMemberID() throws {
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .customer(.init(61002)), payload: MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer)))
    }
    func testAftercareRejectsWrongRefundID() throws {
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .refund(.init(62002)), payload: MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund)))
    }
    func testInvalidCustomerRowFailsWholePage() throws {
        var payload = try object(MerchantBusinessSyntheticFixtures.customers)
        var row = try XCTUnwrap(payload["rows"]?.array?.first?.object); row["memberId"] = .int(0)
        payload["rows"] = .array([.object(row)])
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .customers(.init()), payload: .object(payload)))
    }
    func testDuplicateCustomerRowsRejected() throws {
        var payload = try object(MerchantBusinessSyntheticFixtures.customers); let row = payload["rows"]!.array![0]
        payload["rows"] = .array([row, row]); payload["total"] = .int(2)
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .customers(.init()), payload: .object(payload)))
    }
    func testReviewsRejectPublicModeAndWrongPage() throws {
        var payload = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object)
        payload["mode"] = .string("public")
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(payload)))
        payload["mode"] = .string("manage"); payload["pageNum"] = .int(2)
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(payload)))
    }
    func testReviewReplyCapabilityCannotContradictExistingReply() throws {
        var row = try object(MerchantBusinessSyntheticFixtures.review); row["merchantReply"] = .string("Already replied")
        XCTAssertThrowsError(try MerchantBusinessRecord(kind: .review, fields: row))
    }
    func testReviewImageRequiresHTTPS() throws {
        var row = try object(MerchantBusinessSyntheticFixtures.review); row["imageUrls"] = .array([.string("http://example.com/image.png")])
        XCTAssertThrowsError(try MerchantBusinessRecord(kind: .review, fields: row))
    }
    func testAftercareCanRespondAndDecisionsMustAgree() throws {
        var row = try object(MerchantBusinessSyntheticFixtures.refund); row["allowedDecisions"] = .array([])
        XCTAssertThrowsError(try MerchantBusinessRecord(kind: .refund, fields: row))
    }
    func testOpinionReceiptDoesNotClaimRefund() throws {
        let mutation = MerchantBusinessMutation.aftercare(refund: try .init(62001), decision: .agree, content: "", evidenceKey: nil)
        let receipt = try MerchantBusinessReceipt(mutation: mutation, message: nil, data: .object(["id":.int(1),"refundId":.int(62001),"decision":.string("AGREE"),"processing":.string("WAITING_PLATFORM_REVIEW"),"merchantOpinion":.string("AGREE"),"refunded":.bool(false)]))
        XCTAssertFalse(receipt.refundActuallyConfirmed)
    }
    func testContradictoryRefundReceiptRejected() throws {
        let mutation = MerchantBusinessMutation.aftercare(refund: try .init(62001), decision: .agree, content: "", evidenceKey: nil)
        XCTAssertThrowsError(try MerchantBusinessReceipt(mutation: mutation, message: nil, data: .object(["id":.int(1),"refundId":.int(62001),"decision":.string("AGREE"),"processing":.string("WAITING_PLATFORM_REVIEW"),"merchantOpinion":.string("AGREE"),"refunded":.bool(true)])))
    }
    func testMissingMoneyZeroAndNegativeStayDifferent() throws {
        XCTAssertNil(try MerchantBusinessMoney(nil).raw)
        XCTAssertEqual(try MerchantBusinessMoney(.string("0.00")).raw, "0.00")
        XCTAssertEqual(try MerchantBusinessMoney(.string("-12.00")).display, "CNY -12.00")
    }
    func testFinanceRejectsNumericMoneyInsteadOfRounding() { XCTAssertThrowsError(try MerchantBusinessMoney(.number(Decimal(12)), strictString: true)) }
    func testNoCurrencyGuessFromLocale() throws { XCTAssertEqual(try MerchantBusinessMoney(.string("12.00")).currency, "CNY") }
    func testBatchDirectionRemainsUnknown() throws { XCTAssertEqual(try document(.batch(.init(66001))).sections[0].rows[0].fields["netDirection"], .null) }
    func testBatchKeepsAdjustmentsSeparate() throws { let doc = try document(.batch(.init(66001))); XCTAssertEqual(doc.sections.map(\.id), ["batch","earnings","adjustments"]); XCTAssertEqual(doc.sections[2].rows[0].fields["signedAmount"], .string("-12.00")) }
    func testBadRedemptionRecordKeyNeverMapsToOrderID() { XCTAssertNil(MerchantBusinessRecord.redemptionRecordID("order:64001")); XCTAssertNil(MerchantBusinessRecord.redemptionRecordID("redemption:")) }
    func testDetailUsesRecordTypeRedemption() throws { XCTAssertEqual(try MerchantBusinessQuery.redemption(recordID: "64001").request().body, .json(["recordType": .string("redemption"), "recordId": .string("64001")])) }
    func testCRMNoteUTF16LimitAndNullCorrection() throws {
        let id = try MerchantCustomerID(61001)
        XCTAssertThrowsError(try MerchantBusinessMutation.addNote(customer: id, content: String(repeating: "😀", count: 251), correctsNoteID: nil).request(requestID: "example-1"))
        guard case .json(let fields) = try MerchantBusinessMutation.addNote(customer: id, content: " note ", correctsNoteID: nil).request(requestID: "example-1").body else { return XCTFail() }
        XCTAssertEqual(fields["content"], .string("note")); XCTAssertEqual(fields["correctsNoteId"], .null)
    }
    func testTagBodyNormalizesColorAndDoesNotSendMerchantID() throws {
        let command = MerchantBusinessMutation.assignTag(customer: try .init(61001), name: " tag ", color: "#abcdef")
        guard case .json(let fields) = try command.request(requestID: "example-1").body else { return XCTFail() }
        XCTAssertEqual(fields["tagName"], .string("tag")); XCTAssertEqual(fields["tagColor"], .string("#ABCDEF")); XCTAssertNil(fields["merchantId"])
    }
    func testBatchTagLimitAndUniqueCustomerIDs() throws {
        let ids = try (1...101).map(MerchantCustomerID.init)
        XCTAssertThrowsError(try MerchantBusinessMutation.batchTag(customers: ids, name: "t", color: "#123456").request(requestID: "example-1"))
        XCTAssertThrowsError(try MerchantBusinessMutation.batchTag(customers: [ids[0], ids[0]], name: "t", color: "#123456").request(requestID: "example-1"))
    }
    func testEvidenceCannotBeURLOrArbitraryObjectKey() throws {
        XCTAssertThrowsError(try MerchantBusinessMutation.aftercare(refund: .init(62001), decision: .evidence, content: "", evidenceKey: "https://example.com/asset.png").request(requestID: "example-1"))
    }
    func testAftercareRespondBodyDoesNotContainRefundAmount() throws {
        let request = try MerchantBusinessMutation.aftercare(refund: .init(62001), decision: .reject, content: "Reason", evidenceKey: nil).request(requestID: "example-1")
        XCTAssertEqual(request.query, ["refundId":"62001"])
        guard case .json(let fields) = request.body else { return XCTFail() }; XCTAssertNil(fields["refundAmount"]); XCTAssertNil(fields["refundId"])
    }
    func testOwnerRoleAloneDoesNotGrantPermission() throws {
        var raw = try object(MerchantBusinessSyntheticFixtures.access); raw["permissions"] = .array([]); raw["canManageOperators"] = .bool(false)
        let access = try MerchantBusinessAccess(raw); XCTAssertThrowsError(try access.require(["merchant:crm:read"]))
    }
    func testOperatorFlagMustMatchPermission() throws {
        var raw = try object(MerchantBusinessSyntheticFixtures.access); raw["canManageOperators"] = .bool(false)
        XCTAssertThrowsError(try MerchantBusinessAccess(raw))
    }
    func testOwnerCannotBeAssignedAsEmployee() throws { XCTAssertThrowsError(try MerchantBusinessMutation.inviteOperator(role: "MERCHANT_OWNER").request(requestID: "example-1")) }
    func testOperatorMutationUsesOperatorIDAndVersion() throws {
        guard case .json(let fields) = try MerchantBusinessMutation.operatorRole(id: .init(67001), version: 2, role: "MERCHANT_FINANCE").request(requestID: "example-1").body else { return XCTFail() }
        XCTAssertEqual(fields["operatorId"], .int(67001)); XCTAssertEqual(fields["version"], .int(2)); XCTAssertNil(fields["memberId"])
    }
    func testExactOperatorReceiptChecksRoleAndVersion() throws {
        let mutation = MerchantBusinessMutation.operatorRole(id: try .init(67001), version: 2, role: "MERCHANT_FINANCE")
        let wrong = try MerchantBusinessSyntheticFixtures.decode(#"{"id":67001,"roleCode":"MERCHANT_CHECKIN","status":"ACTIVE","version":3,"acceptedAt":"2026-09-01","mutationState":"EXACT_RESULT"}"#)
        XCTAssertThrowsError(try MerchantBusinessReceipt(mutation: mutation, message: nil, data: wrong))
    }
    func testLaterAuthoritativeOperatorReceiptCanDifferFromRequestedRole() throws {
        let mutation = MerchantBusinessMutation.operatorRole(id: try .init(67001), version: 2, role: "MERCHANT_FINANCE")
        let later = try MerchantBusinessSyntheticFixtures.decode(#"{"id":67001,"roleCode":"MERCHANT_CHECKIN","status":"ACTIVE","version":4,"acceptedAt":"2026-09-01","mutationState":"LATER_AUTHORITATIVE"}"#)
        XCTAssertNoThrow(try MerchantBusinessReceipt(mutation: mutation, message: nil, data: later))
    }
    func testImmutableReviewRejectsChangedTargetVersion() throws {
        let access = try MerchantBusinessAccess(object(MerchantBusinessSyntheticFixtures.access)); let doc = try document(.reviews(page: 1))
        XCTAssertThrowsError(try MerchantBusinessMutation.review(id: .init(63001), version: 1, action: .reply, content: "Thank you").validate(in: doc, access: access))
    }
}
