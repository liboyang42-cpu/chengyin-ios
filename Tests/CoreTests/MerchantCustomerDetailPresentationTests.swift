import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class MerchantCustomerDetailPresentationTests: XCTestCase {
    private func event(_ key: String, _ type: String, _ time: String?, _ description: String = "Synthetic event") -> MerchantBusinessValue {
        .object(["key": .string(key), "type": .string(type), "title": .string("Synthetic event"),
                 "description": .string(description), "occurredAt": .optional(time)])
    }
    private func payload(_ events: [MerchantBusinessValue]) throws -> MerchantBusinessValue {
        var object = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer).object)
        object["timeline"] = .array(events)
        return .object(object)
    }
    private func projection(_ events: [MerchantBusinessValue]) throws -> MerchantCustomerDetailPresentation {
        try .init(customerID: .init(61001), payload: payload(events))
    }
    func testOnlyRegistrationKeysGroupAndUseAbsoluteInstants() throws {
        let detail = try projection([
            event("registration-41", "REGISTERED", "2026-10-08T10:00:00+08:00"),
            event("registration-41", "ARRIVED", "2026-10-08T03:00:00Z", "「Synthetic activity」")])
        XCTAssertEqual(detail.participation.count, 1)
        XCTAssertEqual(detail.participation[0].events.count, 2)
        XCTAssertEqual(detail.participation[0].latest?.kind, .arrived)
        XCTAssertEqual(detail.participation[0].title, "Synthetic activity")
    }
    func testNonRegistrationParticipationKeysNeverMerge() throws {
        let detail = try projection([
            event("other-41", "REGISTERED", "2026-10-08T02:00:00Z"),
            event("other-41", "ARRIVED", "2026-10-08T03:00:00Z")])
        XCTAssertEqual(detail.participation.count, 2)
        XCTAssertEqual(Set(detail.participation.map(\.id)).count, 2)
    }
    func testNotesCorrectionsAndCampaignsRemainIndependent() throws {
        let detail = try projection([
            event("registration-41", "ARRIVED", "2026-10-08T02:00:00Z"),
            event("note-11", "NOTE", "2026-10-08T03:00:00Z", "Synthetic first note"),
            event("note-12", "NOTE_CORRECTION", "2026-10-08T04:00:00Z", "Synthetic correction"),
            event("campaign-11", "CAMPAIGN", "2026-10-08T05:00:00Z", "Synthetic outreach")])
        XCTAssertEqual(detail.participation.count, 1)
        XCTAssertEqual(detail.history.map(\.kind), [.campaign, .correction, .note])
        XCTAssertEqual(detail.latestNote?.description, "Synthetic correction")
        XCTAssertEqual(detail.history.count + detail.participation.flatMap(\.events).count, 4)
    }
    func testInvalidOrMissingTimeNeverProducesLatestClaim() throws {
        for time in [nil, "bad-time", "2026-02-30T00:00:00Z"] as [String?] {
            let detail = try projection([
                event("registration-41", "ARRIVED", "2026-10-08T03:00:00Z"),
                event("registration-41", "REFUNDED", time),
                event("note-11", "NOTE", "2026-10-08T04:00:00Z"),
                event("note-12", "NOTE_CORRECTION", time)])
            XCTAssertNil(detail.participation[0].latest)
            XCTAssertNil(detail.latestNote)
            XCTAssertTrue(detail.hasNotes)
            XCTAssertEqual(detail.participation[0].events.count, 2)
            XCTAssertEqual(detail.history.count, 2)
        }
    }
    func testTiedInstantKeepsStableFactsWithoutChoosingLatest() throws {
        let detail = try projection([
            event("registration-41", "REGISTERED", "2026-10-08T10:00:00+08:00"),
            event("registration-41", "ARRIVED", "2026-10-08T02:00:00Z"),
            event("note-11", "NOTE", "2026-10-08T02:00:00Z"),
            event("note-12", "NOTE_CORRECTION", "2026-10-08T10:00:00+08:00")])
        XCTAssertNil(detail.participation[0].latest)
        XCTAssertNil(detail.latestNote)
        XCTAssertEqual(detail.participation[0].events.map(\.kind), [.registered, .arrived])
        XCTAssertEqual(detail.history.map(\.record.id), ["note-11", "note-12"])
    }
    func testKnownDatesSortBeforeUnknownAndEqualGroupsKeepSourceOrder() throws {
        let detail = try projection([
            event("registration-1", "REGISTERED", nil),
            event("registration-2", "ARRIVED", "2026-10-08T02:00:00Z"),
            event("registration-3", "REFUNDED", "2026-10-08T02:00:00Z")])
        XCTAssertEqual(detail.participation.map { $0.events[0].record.id }, ["registration-2", "registration-3", "registration-1"])
    }
    func testDuplicateHistoryIDsAndUnknownKindsFailClosed() throws {
        let repeated = event("note-11", "NOTE", "2026-10-08T02:00:00Z")
        XCTAssertThrowsError(try projection([repeated, repeated]))
        XCTAssertThrowsError(try projection([event("campaign-1", "REFUND_PROCESSING", nil)]))
        XCTAssertThrowsError(try projection([event("campaign-1", "REFUND_REQUESTED", nil)]))
    }
    func testRegistrationRefundIsReturnedFactAndNotInferredFromNotes() throws {
        let detail = try projection([
            event("registration-41", "REFUNDED", "2026-10-08T02:00:00Z"),
            event("note-11", "NOTE", "2026-10-08T03:00:00Z", "Synthetic refund requested")])
        XCTAssertEqual(detail.participation[0].latest?.kind, .refunded)
        XCTAssertEqual(detail.history[0].kind, .note)
        XCTAssertEqual(detail.participation[0].latest?.kind.titleKey, "merchant.customerDetail.event.REFUNDED")
    }
    func testEmptySectionsDoNotInventEventsOrNotes() throws {
        let detail = try projection([])
        XCTAssertTrue(detail.participation.isEmpty)
        XCTAssertTrue(detail.history.isEmpty)
        XCTAssertNil(detail.latestNote)
        XCTAssertFalse(detail.hasNotes)
    }
    func testWrongCustomerCannotBuildProjection() throws {
        XCTAssertThrowsError(try MerchantCustomerDetailPresentation(customerID: .init(61002), payload: payload([])))
        var value = try XCTUnwrap(payload([]).object)
        var summary = try XCTUnwrap(value["summary"]?.object)
        summary["memberId"] = .int(61002); summary["name"] = .string("Synthetic alternate member")
        summary["lastAction"] = .string("Synthetic visit"); summary["tier"] = .string("new"); summary["sourceType"] = .string("TOPIC")
        value["summary"] = .object(summary)
        XCTAssertThrowsError(try MerchantCustomerDetailPresentation(customerID: .init(61001), payload: .object(value)))
    }
    func testDocumentRetainsExactRawPayloadAndActionHistory() throws {
        var note = try XCTUnwrap(event("note-11", "NOTE", "2026-10-08T03:00:00Z").object)
        note["noteId"] = .int(11); note["noteVersion"] = .int(2)
        let raw = try payload([
            event("registration-41", "REGISTERED", "2026-10-08T02:00:00Z"),
            event("registration-41", "ARRIVED", "2026-10-08T03:00:00Z"), .object(note)])
        let document = try MerchantBusinessDocument(query: .customer(.init(61001)), payload: raw)
        XCTAssertEqual(document.payload, raw)
        XCTAssertEqual(document.customerDetail?.participation.first?.events.count, 2)
        XCTAssertEqual(document.sections.first { $0.id == "timeline" }?.rows.map(\.id), ["note-11"])
        XCTAssertEqual(document.rows.first { $0.kind == .timeline }?.fields["noteVersion"], .int(2))
        let grant = try MerchantBusinessAccess(XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object))
        XCTAssertNoThrow(try MerchantBusinessMutation.hideNote(customer: .init(61001), noteID: 11, expectedVersion: 2).validate(in: document, access: grant))
    }
    func testBareShanghaiAndISORepresentSameInstant() throws {
        XCTAssertEqual(MerchantCustomerDetailTime.date("2026-10-08 10:00:00"), MerchantCustomerDetailTime.date("2026-10-08T02:00:00Z"))
        XCTAssertNotNil(MerchantCustomerDetailTime.date("2026-10-08T02:00:00.123Z"))
        for raw in ["2026-02-30 10:00:00", "2026-10-08T10:00:00", "2026-10-08T25:00:00Z", "unknown"] {
            XCTAssertNil(MerchantCustomerDetailTime.date(raw))
        }
    }
    func testPhoneZoneCrossDayAndDSTDoNotChangeEventInstant() throws {
        let instant = try XCTUnwrap(MerchantCustomerDetailTime.date("2026-10-08 00:30:00"))
        XCTAssertEqual(MerchantCustomerDetailTime.display(instant, phoneTimeZone: TimeZone(secondsFromGMT: 0)!), "2026-10-07 16:30:00 Z")
        XCTAssertEqual(MerchantCustomerDetailTime.display(instant, phoneTimeZone: TimeZone(identifier: "Asia/Shanghai")!), "2026-10-08 00:30:00 +08:00")
        let repeatedA = try XCTUnwrap(MerchantCustomerDetailTime.date("2026-11-01T01:30:00-04:00"))
        let repeatedB = try XCTUnwrap(MerchantCustomerDetailTime.date("2026-11-01T01:30:00-05:00"))
        XCTAssertEqual(repeatedB.timeIntervalSince(repeatedA), 3600)
        XCTAssertNotEqual(MerchantCustomerDetailTime.display(repeatedA, phoneTimeZone: TimeZone(identifier: "America/New_York")!), MerchantCustomerDetailTime.display(repeatedB, phoneTimeZone: TimeZone(identifier: "America/New_York")!))
    }
    func testExistingPOSTDetailRequestAddsNoOwnerOrMerchantOverride() throws {
        let descriptor = try MerchantBusinessQuery.customer(.init(61001)).request()
        XCTAssertEqual(descriptor.path, "api/merchant/crm/customers/61001/detail")
        XCTAssertEqual(descriptor.body, .none)
        XCTAssertTrue(descriptor.query.isEmpty)
        XCTAssertEqual(MerchantBusinessQuery.customer(try .init(61001)).permissions, ["merchant:crm:read"])
    }
}
