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
    func testReviewFiltersUseCapabilitiesRatingBoundaryAndPhotos() throws {
        let pending = try MerchantBusinessRecord(kind: .review, fields: object(MerchantBusinessSyntheticFixtures.review))
        var fields = pending.fields
        fields["id"] = .int(63002); fields["rating"] = .int(3)
        fields["canReply"] = .bool(false); fields["merchantReply"] = .string("Synthetic reply")
        let repliedLow = try MerchantBusinessRecord(kind: .review, fields: fields)
        fields["id"] = .int(63003); fields["rating"] = .int(5)
        fields["imageUrls"] = .array([.string("https://example.com/synthetic-review.png")])
        let photo = try MerchantBusinessRecord(kind: .review, fields: fields)
        fields["id"] = .int(63004); fields["status"] = .string("HIDDEN")
        fields["canReport"] = .bool(false); fields["merchantReply"] = .null; fields["imageUrls"] = .array([])
        let hiddenUnreplied = try MerchantBusinessRecord(kind: .review, fields: fields)
        let rows = [pending, repliedLow, photo, hiddenUnreplied]
        XCTAssertEqual(rows.filter(MerchantReviewFilter.all.matches).map(\.id), ["63001", "63002", "63003", "63004"])
        XCTAssertEqual(rows.filter(MerchantReviewFilter.pending.matches).map(\.id), ["63001"])
        XCTAssertEqual(rows.filter(MerchantReviewFilter.low.matches).map(\.id), ["63002"])
        XCTAssertEqual(rows.filter(MerchantReviewFilter.photos.matches).map(\.id), ["63003"])
        XCTAssertFalse(MerchantReviewFilter.all.matches(try document(.refund(.init(62001))).rows[0]))
    }
    func testAftercareSearchMatchesOnlySourceFieldsAndTrimsCaseInsensitively() throws {
        var fields = try object(MerchantBusinessSyntheticFixtures.refund)
        fields["refundNo"] = .string("EXAMPLE-RF-42")
        fields["customerNickname"] = .string("Synthetic Alice")
        fields["activityTitle"] = .string("示例城市漫步")
        fields["reason"] = .string("Weather delay")
        fields["privateNote"] = .string("Do not search this field")
        let row = try MerchantBusinessRecord(kind: .refund, fields: fields)
        let section = try MerchantBusinessSection("aftercare", rows: [row])
        var filters = MerchantBusinessListFilters()
        for term in ["example-rf", "  ALICE  ", "城市漫步", "WEATHER", "\n  "] {
            filters.aftercareKeyword = term
            XCTAssertEqual(filters.rows(in: section, query: .aftercare(.pending, page: 1)), [row], term)
        }
        for term in ["no-match", "Do not search this field", "62001"] {
            filters.aftercareKeyword = term
            XCTAssertTrue(filters.rows(in: section, query: .aftercare(.pending, page: 1)).isEmpty, term)
        }
    }
    func testAftercareSearchHandlesAbsentFieldsWithoutInventingText() throws {
        var fields = try object(MerchantBusinessSyntheticFixtures.refund)
        for key in MerchantBusinessListFilters.aftercareSearchKeys { fields.removeValue(forKey: key) }
        let section = try MerchantBusinessSection("aftercare", rows: [.init(kind: .refund, fields: fields)])
        var filters = MerchantBusinessListFilters(); filters.aftercareKeyword = "null"
        XCTAssertTrue(filters.rows(in: section, query: .aftercare(.pending, page: 1)).isEmpty)
        filters.aftercareKeyword = "   "
        XCTAssertEqual(filters.rows(in: section, query: .aftercare(.pending, page: 1)).count, 1)
        XCTAssertFalse(filters.isActive(for: .aftercare(.pending, page: 1)))
    }
    func testListFiltersNeverChangeDetailRowsQueriesOrServerPagination() throws {
        var filters = MerchantBusinessListFilters(); filters.review = .photos; filters.aftercareKeyword = "missing"
        let reviews = try document(.reviews(page: 1)), refunds = try document(.aftercare(.pending, page: 1))
        let reviewBefore = reviews, refundBefore = refunds
        XCTAssertTrue(filters.rows(in: reviews.sections[0], query: reviews.query).isEmpty)
        XCTAssertTrue(filters.rows(in: refunds.sections[0], query: refunds.query).isEmpty)
        XCTAssertEqual(reviews, reviewBefore); XCTAssertEqual(refunds, refundBefore)
        XCTAssertEqual(try reviews.query.request().query, ["pageNum": "1", "pageSize": "20"])
        XCTAssertEqual(try refunds.query.request().query, ["bucket": "PENDING", "pageNum": "1", "pageSize": "20"])
        let detail = try document(.refund(.init(62001)))
        XCTAssertEqual(filters.rows(in: detail.sections[0], query: detail.query), detail.sections[0].rows)
        XCTAssertFalse(filters.isActive(for: detail.query))
        filters = .init()
        XCTAssertEqual(filters.rows(in: reviews.sections[0], query: reviews.query), reviews.rows)
        XCTAssertEqual(filters.rows(in: refunds.sections[0], query: refunds.query), refunds.rows)
    }
    func testLocalSearchReevaluatesReplacementPageWithoutAccumulation() throws {
        var filters = MerchantBusinessListFilters(); filters.aftercareKeyword = "First page"
        var first = try object(MerchantBusinessSyntheticFixtures.refund), second = first
        first["reason"] = .string("First page request")
        second["refundId"] = .int(62021); second["reason"] = .string("Second page request")
        let firstSection = try MerchantBusinessSection("aftercare", rows: [.init(kind: .refund, fields: first)])
        let secondSection = try MerchantBusinessSection("aftercare", rows: [.init(kind: .refund, fields: second)])
        XCTAssertEqual(filters.rows(in: firstSection, query: .aftercare(.pending, page: 1)).count, 1)
        XCTAssertTrue(filters.rows(in: secondSection, query: .aftercare(.pending, page: 2)).isEmpty)
        XCTAssertEqual(filters.aftercareKeyword, "First page")
        filters.aftercareKeyword = ""
        XCTAssertEqual(filters.rows(in: secondSection, query: .aftercare(.pending, page: 2)).map(\.id), ["62021"])
    }

    func testServerReviewMetricsRemainIndependentOfFilteredPage() throws {
        let document = try MerchantBusinessDocument(query: .reviews(page: 1), payload: MerchantBusinessSyntheticFixtures.listToolsPayload(.reviews(page: 1)))
        var filters = MerchantBusinessListFilters(); filters.review = .pending
        XCTAssertEqual(filters.rows(in: document.sections[0], query: document.query).count, 1)
        XCTAssertEqual(document.summary["pendingReplyCount"], .int(7))
        XCTAssertEqual(document.summary["monthNewCount"], .int(12))
        XCTAssertEqual(document.summary["replyRatePct"], .int(65))
        XCTAssertEqual(document.total, 21); XCTAssertTrue(document.hasMore)
        filters.review = .photos
        XCTAssertEqual(filters.rows(in: document.sections[0], query: document.query).count, 1)
        XCTAssertEqual(document.summary["pendingReplyCount"], .int(7))
        XCTAssertEqual(document.rows.count, 20)
    }
    func testAbsentReviewMetricsStayUnknownInsteadOfZero() throws {
        let missing = try document(.reviews(page: 1))
        for key in MerchantBusinessDocument.reviewMetricKeys { XCTAssertEqual(missing.summary[key], .null, key) }
        var raw = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object)
        for key in MerchantBusinessDocument.reviewMetricKeys { raw[key] = .null }
        let nulls = try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(raw))
        for key in MerchantBusinessDocument.reviewMetricKeys { XCTAssertEqual(nulls.summary[key], .null, key) }
    }
    func testReviewMetricsAcceptRealZeroAndPercentBoundaries() throws {
        var raw = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object)
        raw["pendingReplyCount"] = .int(0); raw["monthNewCount"] = .int(0)
        for rate in [0, 100] {
            raw["replyRatePct"] = .int(rate)
            let document = try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(raw))
            XCTAssertEqual(document.summary["pendingReplyCount"], .int(0))
            XCTAssertEqual(document.summary["monthNewCount"], .int(0))
            XCTAssertEqual(document.summary["replyRatePct"], .int(rate))
        }
    }
    func testMalformedServerMetricsAreRejectedWithoutClamping() throws {
        let bad: [MerchantBusinessValue] = [.int(-1), .number(Decimal(string: "1.5")!), .string("7"), .bool(true), .object([:])]
        for key in MerchantBusinessDocument.reviewMetricKeys {
            for value in bad {
                var raw = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object); raw[key] = value
                XCTAssertThrowsError(try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(raw)), "\(key): \(value)")
            }
        }
        var raw = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object); raw["replyRatePct"] = .int(101)
        XCTAssertThrowsError(try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(raw)))
    }
    func testAftercareSearchDoesNotJoinUnrelatedFieldsIntoOneMatch() throws {
        var fields = try object(MerchantBusinessSyntheticFixtures.refund)
        fields["customerNickname"] = .string("Synthetic Alice"); fields["activityTitle"] = .string("River walk")
        let section = try MerchantBusinessSection("aftercare", rows: [.init(kind: .refund, fields: fields)])
        var filters = MerchantBusinessListFilters(); filters.aftercareKeyword = "Alice River"
        XCTAssertTrue(filters.rows(in: section, query: .aftercare(.pending, page: 1)).isEmpty)
    }
    func testAftercareSearchUsesDisplayedRefundIDFallbackOnlyWithoutNumber() throws {
        let numbers: [MerchantBusinessValue?] = [nil, .null, .string(""), .string("   ")]
        for number in numbers {
            var fields = try object(MerchantBusinessSyntheticFixtures.refund); fields["refundNo"] = number
            let row = try MerchantBusinessRecord(kind: .refund, fields: fields)
            XCTAssertEqual(row.title, "#62001")
            let section = try MerchantBusinessSection("aftercare", rows: [row])
            var filters = MerchantBusinessListFilters(); filters.aftercareKeyword = "#62001"
            XCTAssertEqual(filters.rows(in: section, query: .aftercare(.pending, page: 1)).count, 1)
        }
        var fields = try object(MerchantBusinessSyntheticFixtures.refund); fields["refundNo"] = .string("  EXAMPLE-42  ")
        XCTAssertEqual(try MerchantBusinessRecord(kind: .refund, fields: fields).title, "EXAMPLE-42")
    }
    func testAftercareDisplaySearchFieldsRejectInvalidTypes() throws {
        for key in ["customerNickname", "activityTitle"] {
            var fields = try object(MerchantBusinessSyntheticFixtures.refund); fields[key] = .int(7)
            XCTAssertThrowsError(try MerchantBusinessRecord(kind: .refund, fields: fields))
            fields[key] = .null; XCTAssertNoThrow(try MerchantBusinessRecord(kind: .refund, fields: fields))
        }
    }

}

final class MerchantAftercareLoadedPagesTests: XCTestCase {
    private let scope = MerchantBusinessScope(realm: "synthetic://loaded-pages", accountID: 99001, epoch: 1)
    private func snapshot(_ query: MerchantBusinessQuery, merchantID: Int = 610, permissions: [MerchantBusinessValue]? = nil, rowOverride: MerchantBusinessObject? = nil) throws -> MerchantBusinessSnapshot {
        var access = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        access["merchant"] = .object(["id": .int(merchantID), "name": .string("Synthetic workshop")])
        if let permissions { access["permissions"] = .array(permissions); access["canManageOperators"] = .bool(false) }
        var payload = try MerchantBusinessSyntheticFixtures.listToolsPayload(query)
        if let rowOverride {
            var object = try XCTUnwrap(payload.object); object["items"] = .array([.object(rowOverride)]); payload = .object(object)
        }
        return try .init(access: .init(access), document: .init(query: query, payload: payload))
    }
    func testAccumulationSearchesBothPagesAndKeepsServerSnapshotsUntouched() throws {
        let first = try snapshot(.aftercare(.pending, page: 1)), second = try snapshot(.aftercare(.pending, page: 2))
        var pages = try MerchantAftercareLoadedPages(snapshot: first, scope: scope, authorizationGeneration: nil)
        try pages.append(second, scope: scope, authorizationGeneration: nil)
        XCTAssertEqual(pages.rows.map(\.id), (1...21).map { String(62000 + $0) })
        XCTAssertEqual(pages.page, 2); XCTAssertFalse(pages.hasMore)
        var filter = MerchantBusinessListFilters(); filter.aftercareKeyword = "  ALICE  "
        let section = try MerchantBusinessSection("aftercare", rows: pages.rows)
        XCTAssertEqual(filter.rows(in: section, query: second.document.query).map(\.id), ["62001"])
        filter.aftercareKeyword = "EXAMPLE-RF-21"
        XCTAssertEqual(filter.rows(in: section, query: second.document.query).map(\.id), ["62021"])
        XCTAssertEqual(first.document.rows.count, 20); XCTAssertEqual(second.document.rows.map(\.id), ["62021"])
        XCTAssertEqual(second.document.total, 21)
        XCTAssertEqual(try second.document.query.request().query, ["bucket": "PENDING", "pageNum": "2", "pageSize": "20"])
    }
    func testResetRequiresFirstAftercarePage() throws {
        XCTAssertThrowsError(try MerchantAftercareLoadedPages(snapshot: snapshot(.aftercare(.pending, page: 2)), scope: scope, authorizationGeneration: nil))
        XCTAssertThrowsError(try MerchantAftercareLoadedPages(snapshot: snapshot(.reviews(page: 1)), scope: scope, authorizationGeneration: nil))
    }
    func testAppendRejectsDifferentAccountEpochRealmOrAuthorizationWithoutChangingRows() throws {
        var pages = try MerchantAftercareLoadedPages(snapshot: snapshot(.aftercare(.pending, page: 1)), scope: scope, authorizationGeneration: nil)
        let before = pages, second = try snapshot(.aftercare(.pending, page: 2))
        let others: [MerchantBusinessScope] = [
            .init(realm: scope.realm, accountID: 99002, epoch: 1),
            .init(realm: scope.realm, accountID: scope.accountID, epoch: 2),
            .init(realm: "synthetic://different", accountID: scope.accountID, epoch: 1)
        ]
        for other in others {
            XCTAssertThrowsError(try pages.append(second, scope: other, authorizationGeneration: nil))
            XCTAssertEqual(pages, before)
        }
        XCTAssertThrowsError(try pages.append(second, scope: scope, authorizationGeneration: UUID()))
        XCTAssertEqual(pages, before)
    }
    func testAppendRejectsDifferentMerchantPermissionsBucketOrPageWithoutChangingRows() throws {
        var pages = try MerchantAftercareLoadedPages(snapshot: snapshot(.aftercare(.pending, page: 1)), scope: scope, authorizationGeneration: nil)
        let before = pages
        let invalid = [
            try snapshot(.aftercare(.pending, page: 2), merchantID: 611),
            try snapshot(.aftercare(.pending, page: 2), permissions: [.string("merchant:aftercare:read")]),
            try snapshot(.aftercare(.processing, page: 2)),
            try snapshot(.aftercare(.pending, page: 1)),
            try snapshot(.reviews(page: 2))
        ]
        for snapshot in invalid {
            XCTAssertThrowsError(try pages.append(snapshot, scope: scope, authorizationGeneration: nil))
            XCTAssertEqual(pages, before)
        }
    }
    func testDuplicateLoadedIdentityUsesLatestFieldsAndKeepsStableOrder() throws {
        let first = try snapshot(.aftercare(.pending, page: 1))
        var row = try XCTUnwrap(first.document.rows.first?.fields)
        row["reason"] = .string("Updated synthetic reason")
        let second = try snapshot(.aftercare(.pending, page: 2), rowOverride: row)
        var pages = try MerchantAftercareLoadedPages(snapshot: first, scope: scope, authorizationGeneration: nil)
        try pages.append(second, scope: scope, authorizationGeneration: nil)
        XCTAssertEqual(pages.rows.count, 20)
        XCTAssertEqual(pages.rows.first?.id, "62001")
        XCTAssertEqual(pages.rows.first?.fields.mbText("reason"), "Updated synthetic reason")
        XCTAssertEqual(first.document.rows.first?.fields.mbText("reason"), "Weather delay")
        XCTAssertNoThrow(try MerchantBusinessSection("aftercare", rows: pages.rows))
    }
    func testCompletedPageCannotBeAppendedAgain() throws {
        var pages = try MerchantAftercareLoadedPages(snapshot: snapshot(.aftercare(.pending, page: 1)), scope: scope, authorizationGeneration: nil)
        let second = try snapshot(.aftercare(.pending, page: 2))
        try pages.append(second, scope: scope, authorizationGeneration: nil)
        let before = pages
        XCTAssertThrowsError(try pages.append(second, scope: scope, authorizationGeneration: nil))
        XCTAssertEqual(pages, before)
    }
}
