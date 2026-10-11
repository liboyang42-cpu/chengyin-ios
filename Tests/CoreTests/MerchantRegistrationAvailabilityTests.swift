import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func availability(_ start: String = "2028-02-29", _ end: String = "2028-03-02", _ from: Int = 547, _ to: Int = 1083) -> MerchantRegistrationAvailability {
    .init(startDay: start, endDay: end, startMinutes: from, endMinutes: to)
}
private func availabilityValue(_ text: String) throws -> MerchantContentValue { try MerchantContentFixtureData.value(text) }
private let availabilityOriginal = #"{"id":22,"topicId":70,"status":0,"auditStatus":0,"addressName":"Atelier","address":"Street","activityDesc":"Activity","limitNum":4,"startDate":"2028-02-29 00:00:00","endDate":"2028-03-02 23:59:59","cooperateDate":"09:07-18:03"}"#
private func availabilityDraft() throws -> MerchantRegistrationContentDraft { .init(detail: try availabilityValue(availabilityOriginal)) }
private func availabilityFields(_ command: MerchantContentCommand) throws -> [String: MerchantContentValue] {
    guard case .json(let fields) = try command.request().body else { throw MerchantContentFailure.invalid }; return fields
}

final class MerchantRegistrationAvailabilityContractTests: XCTestCase {
    func testInclusiveDateRangeAndDailyTimeWireMatchesMiniExactly() throws {
        XCTAssertEqual(try availability().fields(), ["startDate": .string("2028-02-29 00:00:00"), "endDate": .string("2028-03-02 23:59:59"), "cooperateDate": .string("09:07-18:03")])
        XCTAssertTrue(availability("2028-02-29", "2028-02-29", 0, 1439).isValid)
    }
    func testInvalidGregorianDatesAndInvertedRangesAreRejected() {
        for (start, end) in [("2026-02-29", "2026-03-01"), ("2028-04-31", "2028-05-01"), ("0000-01-01", "2028-01-01"),
                             ("2028-03-02", "2028-03-01"), ("2028-2-9", "2028-03-01"), ("2028-03-01Z", "2028-03-02")] {
            XCTAssertFalse(availability(start, end).isValid); XCTAssertThrowsError(try availability(start, end).fields())
        }
    }
    func testDailyHoursCannotCrossMidnightOrBeEmpty() {
        for (start, end) in [(600, 600), (1080, 540), (-1, 600), (0, 1440), (1440, 1441)] {
            XCTAssertFalse(availability("2028-02-29", "2028-03-02", start, end).isValid)
        }
    }
    func testRecognizedSourcePreservesOffStepMinutes() throws {
        let source = MerchantRegistrationAvailabilitySource(try availabilityValue(availabilityOriginal))
        XCTAssertEqual(MerchantRegistrationAvailability(source: source), availability())
        XCTAssertTrue(MerchantStationServiceWindow.minuteChoices(preserving: 7).contains(7))
        XCTAssertTrue(MerchantStationServiceWindow.minuteChoices(preserving: 3).contains(3))
    }
    func testDateOnlySourceIsRecognizedWithoutChangingItsRawBytes() throws {
        let original = availabilityOriginal.replacingOccurrences(of: " 00:00:00", with: "").replacingOccurrences(of: " 23:59:59", with: "")
        let source = MerchantRegistrationAvailabilitySource(try availabilityValue(original))
        XCTAssertEqual(MerchantRegistrationAvailability(source: source), availability()); XCTAssertEqual(source.start.text, "2028-02-29")
    }
    func testUnknownSourceIsNeverParsedAsAnInstantOrNormalized() throws {
        for raw in ["source civil time", "2028-02-29T00:00:00Z", "2028-02-29 12:00:00"] {
            let source = MerchantRegistrationAvailabilitySource(.object(["startDate": .string(raw), "endDate": .string("2028-03-02 23:59:59"), "cooperateDate": .string("09:00-18:00")]))
            XCTAssertNil(MerchantRegistrationAvailability(source: source)); XCTAssertEqual(source.start.text, raw)
        }
    }
    func testMissingOrWrongTypedSourceDoesNotManufactureAvailability() {
        XCTAssertTrue(MerchantRegistrationAvailabilitySource(.object([:])).isEmpty)
        let source = MerchantRegistrationAvailabilitySource(.object(["startDate": .integer(20280229)]))
        XCTAssertFalse(source.isEmpty); XCTAssertNil(MerchantRegistrationAvailability(source: source))
    }
    func testPickerCalendarIsOnlyFixedZoneDateCarrier() throws {
        var value = availability(); let start = try XCTUnwrap(value.pickerDate(start: true))
        let parts = MerchantStationServiceWindow.pickerCalendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(parts.year, 2028); XCTAssertEqual(parts.month, 2); XCTAssertEqual(parts.day, 29)
        value.selectDay(start, start: false); XCTAssertEqual(value.endDay, value.startDay)
        XCTAssertEqual(MerchantStationServiceWindow.pickerCalendar.timeZone.secondsFromGMT(), 0)
    }
    func testUntouchedDraftAndRestoreOmitAllThreeFields() throws {
        var draft = try availabilityDraft(); XCTAssertNil(draft.availabilityReplacement)
        for field in ["startDate", "endDate", "cooperateDate"] { XCTAssertNil(try draft.fieldsIncludingAvailability()[field]) }
        draft.availabilityReplacement = availability(); XCTAssertNotNil(try draft.fieldsIncludingAvailability()["startDate"])
        draft.availabilityReplacement = nil
        for field in ["startDate", "endDate", "cooperateDate"] { XCTAssertNil(try draft.fieldsIncludingAvailability()[field]) }
    }
    func testEditedGroupAddsOnlyTheThreeExistingUpdateFields() throws {
        var draft = try availabilityDraft(); let old = try draft.fields(); draft.availabilityReplacement = availability()
        let fields = try availabilityFields(.updateRegistration(id: 22, topicID: 70, draft: draft))
        XCTAssertEqual(Set(fields.keys), Set(old.keys).union(["id", "topicId", "startDate", "endDate", "cooperateDate"]))
        for (key, value) in old { XCTAssertEqual(fields[key], value) }
        XCTAssertEqual(fields["id"], .integer(22)); XCTAssertEqual(fields["cooperateDate"], .string("09:07-18:03"))
        for key in ["status", "auditStatus", "merchantId", "couponId", "templateId", "sharingAmount"] { XCTAssertNil(fields[key]) }
    }
    func testCreationContractDoesNotAcquireAvailabilityReplacement() throws {
        var draft = try availabilityDraft(); draft.availabilityReplacement = availability()
        let command = MerchantContentCommand.register(topicID: 70, nodeID: 7, draft: draft, cooperateDate: "10:00-11:00")
        let fields = try availabilityFields(command); XCTAssertNil(fields["startDate"]); XCTAssertNil(fields["endDate"])
        XCTAssertEqual(fields["cooperateDate"], .string("10:00-11:00")); XCTAssertNil(command.registrationAvailability)
    }
    func testInvalidReplacementBlocksUpdateRequest() throws {
        var draft = try availabilityDraft(); draft.availabilityReplacement = availability("2028-03-02", "2028-03-01")
        XCTAssertThrowsError(try MerchantContentCommand.updateRegistration(id: 22, topicID: 70, draft: draft).request())
    }
    func testCodableOldDraftWithoutOptionalReplacementRemainsReadable() throws {
        let data = try JSONEncoder().encode(availabilityDraft()); let decoded = try JSONDecoder().decode(MerchantRegistrationContentDraft.self, from: data)
        XCTAssertNil(decoded.availabilityReplacement); XCTAssertNil(try decoded.fieldsIncludingAvailability()["startDate"])
    }
}

private final class AvailabilityTransport: MerchantContentOfflineTransport {
    var replies: [(String, Int)] = []
    var requests: [URLRequest] = []
    var failAt: Int?
    var callback: ((Int) -> Void)?
    func append(_ data: String) { replies.append(("{\"code\":200,\"data\":" + data + "}", 200)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); callback?(requests.count)
        if requests.count == failAt { throw URLError(.timedOut) }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let value = replies.removeFirst(); return (Data(value.0.utf8), value.1)
    }
}
@MainActor final class MerchantRegistrationAvailabilityServiceTests: XCTestCase {
    private final class SessionBox {
        var current: MerchantContentSession? = try? .init(accountID: 1, epoch: 1, storageScope: "availability-test", token: "fixture-token")
    }
    private func service(_ transport: AvailabilityTransport, _ box: SessionBox, journal: MerchantContentMemoryPendingStorage, enabled: Bool = true) throws -> MerchantContentService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport,
              currentSession: { box.current }, journal: journal, execution: enabled ? .injectedOfflineHarness : .disabled)
    }
    private func source(_ transport: AvailabilityTransport, _ raw: String = availabilityOriginal) {
        transport.append(MerchantContentFixtureData.access); transport.append(raw)
    }
    private func prepare(_ coordinator: MerchantContentCoordinator) throws -> MerchantContentReview {
        var draft = MerchantRegistrationContentDraft(detail: try XCTUnwrap(coordinator.snapshot).value)
        draft.availabilityReplacement = availability("2028-03-01", "2028-03-03", 600, 1080)
        coordinator.prepare(.updateRegistration(id: 22, topicID: 70, draft: draft)); return try XCTUnwrap(coordinator.review)
    }
    func testSaveUsesExistingUpdateThenAuthoritativeSameIDReadback() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t); t.append("{}"); source(t, availabilityOriginal.replacingOccurrences(of: "09:07-18:03", with: "11:00-17:00"))
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        let review = try prepare(c); await c.confirm(review)
        XCTAssertEqual(c.snapshot?.value["cooperateDate"].text, "11:00-17:00"); XCTAssertEqual(c.issue, "merchant.registrationAvailability.readback")
        XCTAssertNotNil(c.receipt); XCTAssertTrue(try journal.records().isEmpty)
        let writes = t.requests.filter { $0.url?.path == "/api/registration/merchant/update" }; XCTAssertEqual(writes.count, 1)
        let sent = try JSONDecoder().decode(MerchantContentValue.self, from: XCTUnwrap(writes.first?.httpBody))
        XCTAssertEqual(sent["cooperateDate"].text, "10:00-18:00"); XCTAssertEqual(sent["startDate"].text, "2028-03-01 00:00:00")
        XCTAssertEqual(t.requests.last?.url?.query, "id=22"); XCTAssertEqual(t.requests.last?.httpMethod, "POST")
        await c.confirm(review); XCTAssertEqual(t.requests.count, 7)
    }
    func testReadbackFailureRetainsReceiptAndReadOnlyRecoveryNeverReplays() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t); t.append("{}"); t.failAt = 6
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        let review = try prepare(c); await c.confirm(review)
        XCTAssertNil(c.snapshot); XCTAssertNotNil(c.receipt); XCTAssertEqual(c.issue, "merchant.registrationAvailability.readbackFailed")
        XCTAssertFalse(c.locked); await c.confirm(review); XCTAssertEqual(t.requests.count, 6)
        t.failAt = nil; source(t); await c.load(); XCTAssertNotNil(c.snapshot)
        XCTAssertEqual(t.requests.filter { $0.url?.path == "/api/registration/merchant/update" }.count, 1)
    }
    func testWrongIDReadbackIsFailureWithoutInventingSavedDraft() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t); t.append("{}"); source(t, availabilityOriginal.replacingOccurrences(of: "\"id\":22", with: "\"id\":23"))
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        await c.confirm(try prepare(c)); XCTAssertNil(c.snapshot); XCTAssertNotNil(c.receipt)
        XCTAssertEqual(c.issue, "merchant.registrationAvailability.readbackFailed")
    }
    func testFreshSourceConflictStopsBeforeSave() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t, availabilityOriginal.replacingOccurrences(of: "09:07-18:03", with: "10:00-18:00"))
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        await c.confirm(try prepare(c)); XCTAssertEqual(c.issue, MerchantContentFailure.conflict.key)
        XCTAssertEqual(t.requests.count, 4); XCTAssertNil(c.receipt)
    }
    func testRevokedProjectGrantStopsFreshValidationBeforeWrite() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); t.append(MerchantContentFixtureData.access.replacingOccurrences(of: "merchant:project:manage", with: "merchant:basic:read"))
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        await c.confirm(try prepare(c)); XCTAssertEqual(c.issue, MerchantContentFailure.denied.key)
        XCTAssertEqual(t.requests.count, 3); XCTAssertTrue(try journal.records().isEmpty)
    }
    func testDisabledProductionGateDoesNotDispatchAnUpdateOrReadback() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage(); source(t)
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal, enabled: false), query: .registration(id: 22)); await c.load()
        await c.confirm(try prepare(c)); XCTAssertEqual(c.issue, MerchantContentFailure.disabled.key); XCTAssertEqual(t.requests.count, 2)
    }
    func testUnrelatedRegistrationEditDoesNotGainAutomaticReadback() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t); t.append("{}")
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        var draft = try availabilityDraft(); draft.activityDesc = "Changed"
        c.prepare(.updateRegistration(id: 22, topicID: 70, draft: draft)); await c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(t.requests.count, 5); XCTAssertEqual(c.issue, "merchant.content.acknowledged")
    }
    func testAmbiguousUpdateStaysLockedAndNeverStartsReadback() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t); t.failAt = 5
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        await c.confirm(try prepare(c)); XCTAssertTrue(c.locked); XCTAssertNil(c.receipt); XCTAssertEqual(t.requests.count, 5)
    }
    func testSessionChangeDuringReadbackCannotPublishOldSource() async throws {
        let t = AvailabilityTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        source(t); source(t); t.append("{}"); source(t)
        t.callback = { if $0 == 7 { box.current = nil } }
        let c = MerchantContentCoordinator(service: try service(t, box, journal: journal), query: .registration(id: 22)); await c.load()
        await c.confirm(try prepare(c)); XCTAssertFalse(c.isCurrent); XCTAssertNil(c.snapshot)
    }
}
