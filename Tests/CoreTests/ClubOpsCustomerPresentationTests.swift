import XCTest
@testable import QuestifyCore

final class ClubOpsCustomerPresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, memberID: 704)
    private func item(_ id: Int, extra: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var fields: [String: ClubGovernanceValue] = ["memberId": .integer(id), "verifiedCount": .integer(3), "pendingCount": .integer(0)]
        fields.merge(extra) { _, new in new }; return .object(fields)
    }
    private func list(_ items: [ClubGovernanceValue]) -> ClubGovernanceValue {
        .object(["total": .integer(items.count), "monthNew": .integer(1), "items": .array(items)])
    }
    private func detail(records: [ClubGovernanceValue] = [], summary: [String: ClubGovernanceValue] = [:], extra: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var head: [String: ClubGovernanceValue] = ["memberId": .integer(704), "arrivedCount": .integer(2), "pendingCount": .integer(1), "refundedCount": .integer(0), "paidAmount": .null]
        head.merge(summary) { _, new in new }
        var value: [String: ClubGovernanceValue] = ["summary": .object(head), "records": .array(records), "tags": .array([]), "canEdit": .bool(true)]
        value.merge(extra) { _, new in new }; return .object(value)
    }
    private func record(_ status: String, key: String = "reg-1", occurredAt: String = "2026-09-05") -> ClubGovernanceValue {
        .object(["key": .string(key), "topicId": .integer(91), "title": .string(" Night run "), "occurredAt": .string(occurredAt), "statusCode": .string(status)])
    }

    func testListMetaFollowsMiniProgramPendingFirstRule() throws {
        let presentation = try ClubOpsCustomerListPresentation(value: list([
            item(1, extra: ["pendingCount": .integer(2), "lastTopicName": .string(" City walk "), "lastVisitDate": .string("2026-09-05")]),
            item(2, extra: ["pendingCount": .integer(1)]),
            item(3, extra: ["lastVisitDate": .string("2026-09-05T10:00:00")]),
            item(4, extra: ["lastVisitDate": .string("bad")]),
        ]))
        XCTAssertEqual(presentation.total, 4); XCTAssertEqual(presentation.monthNew, 1)
        XCTAssertEqual(presentation.rows.map(\.meta), [.pending(count: 2, topic: "City walk"), .pending(count: 1, topic: nil),
                                                       .verified(count: 3, monthDay: "09-05"), .verified(count: 3, monthDay: nil)])
    }

    func testListNameRemarkAndPhoneFallbacks() throws {
        let rows = try ClubOpsCustomerListPresentation(value: list([
            item(1, extra: ["displayName": .string("  "), "remark": .string(" VIP "), "phoneText": .string("138****0000")]),
            item(2, extra: ["displayName": .string("Ann"), "phoneText": .string("138****0001"), "phone": .string("13800000001")]),
        ])).rows
        XCTAssertNil(rows[0].displayName); XCTAssertTrue(rows[0].hasRemark); XCTAssertEqual(rows[0].subText, "VIP")
        XCTAssertEqual(rows[1].displayName, "Ann"); XCTAssertFalse(rows[1].hasRemark); XCTAssertEqual(rows[1].subText, "138****0001")
    }

    func testMalformedListFailsClosed() {
        for bad in [list([item(0)]), list([item(1), item(1)]), list([item(1, extra: ["pendingCount": .integer(-1)])]),
                    .object(["total": .integer(1), "items": .array([])]), .object(["total": .integer(1), "monthNew": .integer(0)])] {
            XCTAssertThrowsError(try ClubOpsCustomerListPresentation(value: bad))
        }
    }

    func testValidationAcceptsCancelledRecordsEmittedByBackend() throws {
        let value = detail(records: [record("CANCELLED"), record("REGISTERED", key: "reg-2"), record("CONTACTED", key: "reg-3")])
        XCTAssertNoThrow(try ClubGovernanceValidation.validate(value, operation: .customer, scope: scope))
        let presentation = try ClubOpsCustomerDetailPresentation(value: value, memberID: 704)
        XCTAssertEqual(presentation.records.map(\.status), [.cancelled, .registered, .contacted])
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(detail(records: [record("LOST")]), operation: .customer, scope: scope))
        XCTAssertThrowsError(try ClubOpsCustomerDetailPresentation(value: detail(records: [record("LOST")]), memberID: 704))
    }

    func testDetailRecordDateTitleAndStatusMapping() throws {
        let presentation = try ClubOpsCustomerDetailPresentation(value: detail(records: [record("VERIFIED")]), memberID: 704)
        let row = try XCTUnwrap(presentation.records.first)
        XCTAssertEqual(row.id, "reg-1"); XCTAssertEqual(row.topicID, 91); XCTAssertEqual(row.title, "Night run")
        XCTAssertEqual(row.day, 5); XCTAssertEqual(row.month, 9)
        XCTAssertEqual(row.status.localizationKey, "clubOps.customer.status.VERIFIED")
        XCTAssertEqual(ClubOpsCustomerRecordStatus.allCases.count, 6)
    }

    func testPaidAmountIsHiddenNotZeroAndUsesTrimMoney() throws {
        XCTAssertNil(try ClubOpsCustomerDetailPresentation(value: detail(), memberID: 704).paidAmountText)
        XCTAssertNil(try ClubOpsCustomerDetailPresentation(value: detail(summary: ["paidAmount": .string("")]), memberID: 704).paidAmountText)
        XCTAssertEqual(try ClubOpsCustomerDetailPresentation(value: detail(summary: ["paidAmount": .integer(120)]), memberID: 704).paidAmountText, "¥120")
        XCTAssertEqual(try ClubOpsCustomerDetailPresentation(value: detail(summary: ["paidAmount": .decimal(88.5)]), memberID: 704).paidAmountText, "¥88.50")
        XCTAssertEqual(try ClubOpsCustomerDetailPresentation(value: detail(summary: ["paidAmount": .integer(0)]), memberID: 704).paidAmountText, "¥0")
        XCTAssertThrowsError(try ClubOpsCustomerDetailPresentation(value: detail(summary: ["paidAmount": .decimal(-1)]), memberID: 704))
    }

    func testInteractionRemarkTagsAndMemberMismatch() throws {
        let presentation = try ClubOpsCustomerDetailPresentation(value: detail(summary: ["lastInteractionTime": .string("2026-03-07 09:00:00")],
            extra: ["remark": .string(" likes tea "), "tags": .array([.string("Regular"), .object(["name": .string("VIP")])])]), memberID: 704)
        XCTAssertEqual(presentation.lastInteraction?.month, 3); XCTAssertEqual(presentation.lastInteraction?.day, 7)
        XCTAssertEqual(presentation.remark, "likes tea"); XCTAssertEqual(presentation.tags, ["Regular", "VIP"]); XCTAssertTrue(presentation.canEdit)
        XCTAssertNil(try ClubOpsCustomerDetailPresentation(value: detail(), memberID: 704).lastInteraction)
        XCTAssertThrowsError(try ClubOpsCustomerDetailPresentation(value: detail(), memberID: 705))
        XCTAssertThrowsError(try ClubOpsCustomerDetailPresentation(value: detail(), memberID: nil))
        XCTAssertThrowsError(try ClubOpsCustomerDetailPresentation(value: detail(extra: ["tags": .array([.string(" ")])]), memberID: 704))
    }

    func testTagDraftMirrorsMiniProgramLimitsAndDedupes() {
        var draft = ClubOpsCustomerTagRemarkDraft(tagsText: "A, B,A,,")
        XCTAssertEqual(draft.tags, ["A", "B"]); XCTAssertEqual(draft.tagsText, "A,B")
        XCTAssertNil(draft.add(" B ")); XCTAssertEqual(draft.tags, ["A", "B"])
        XCTAssertNil(draft.add("C,D")); XCTAssertEqual(draft.tags, ["A", "B", "C", "D"])
        XCTAssertEqual(draft.add(String(repeating: "x", count: 13)), .tagTooLong); XCTAssertEqual(draft.tags.count, 4)
        XCTAssertNil(draft.add("E,F,G,H")); XCTAssertEqual(draft.add("I"), .tooManyTags); XCTAssertEqual(draft.tags.count, 8)
        draft.remove(at: 0); draft.remove(at: 99); XCTAssertEqual(draft.tags.first, "B")
        XCTAssertEqual(ClubOpsCustomerTagRemarkDraft.issue(tagsText: "", remark: String(repeating: "备", count: 201)), .remarkTooLong)
        XCTAssertNil(ClubOpsCustomerTagRemarkDraft.issue(tagsText: "", remark: String(repeating: "备", count: 200)))
        XCTAssertEqual(ClubOpsCustomerTagRemarkDraft.Issue.tooManyTags.localizationKey, "clubOps.customer.issue.tooManyTags")
    }

    func testDraftTextStillProducesTheSameCommandFields() throws {
        var form = ClubGovernanceFormDraft(operation: .saveCustomer, scope: scope, seed: ["tags": .array([.string("A")]), "remark": .string("n")])
        var tags = ClubOpsCustomerTagRemarkDraft(tagsText: form.text["tags"] ?? "")
        XCTAssertNil(tags.add("B")); form.text["tags"] = tags.tagsText
        let command = try form.command()
        XCTAssertEqual(command.fields["tags"], .array([.string("A"), .string("B")]))
        XCTAssertEqual(command.fields["remark"], .string("n"))
        XCTAssertEqual(command.fields["requestId"], .string(form.requestID))
    }

    func testCustomerWriteUsesDirectoryGovernanceRuleAndFailsClosed() throws {
        XCTAssertEqual(ClubGovernanceMutation.saveCustomer.permission, "CUSTOMER_DIRECTORY")
        let command = try ClubGovernanceCommand(operation: .saveCustomer, scope: scope,
            values: ["tags": .array([]), "remark": .string("n"), "requestId": .string("test-operation")])
        func review(roles: [String], permissions: [String]) throws -> ClubGovernanceSnapshot {
            let access = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array(roles.map(ClubGovernanceValue.string)), "permissions": .array(permissions.map(ClubGovernanceValue.string)),
                "canManageRoles": .bool(false)]), scope: scope)
            return .init(operation: .customer, scope: scope, permissions: access, value: detail())
        }
        XCTAssertThrowsError(try command.validateReview(review(roles: ["CLUB_OPERATOR"], permissions: ["club:member:list:read"]), accountID: 701))
        XCTAssertNoThrow(try command.validateReview(review(roles: ["CLUB_OPERATOR"], permissions: ["club:member:manage"]), accountID: 701))
        XCTAssertNoThrow(try command.validateReview(review(roles: ["CLUB_OWNER"], permissions: []), accountID: 701))
    }

    func testPageFailureCopyIsScopedToCustomerAndSettlementReads() {
        XCTAssertEqual(ClubOpsFailureCopy(operation: .customers, failure: .forbidden)?.titleKey, "clubOps.customers.forbidden")
        XCTAssertNil(ClubOpsFailureCopy(operation: .customers, failure: .forbidden)?.retryKey)
        XCTAssertEqual(ClubOpsFailureCopy(operation: .customers, failure: .malformed)?.retryKey, "clubOps.customers.retry")
        XCTAssertEqual(ClubOpsFailureCopy(operation: .customer, failure: .unknown(message: nil))?.titleKey, "clubOps.customer.failed")
        XCTAssertEqual(ClubOpsFailureCopy(operation: .settlement, failure: .malformed)?.titleKey, "clubOps.settlement.failed")
        XCTAssertNil(ClubOpsFailureCopy(operation: .settlement, failure: .forbidden))
        XCTAssertNil(ClubOpsFailureCopy(operation: .customers, failure: .signedOut))
        XCTAssertNil(ClubOpsFailureCopy(operation: .roles, failure: .malformed))
    }
}
