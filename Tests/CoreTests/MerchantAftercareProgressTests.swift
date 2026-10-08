import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class MerchantAftercareProgressTests: XCTestCase {
    private func fields() throws -> MerchantBusinessObject {
        try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund).object)
    }
    private func response(_ id: Int, time: String? = nil, decision: String = "EVIDENCE") -> MerchantBusinessValue {
        .object(["id": .int(id), "refundId": .int(62001), "decision": .string(decision),
                 "actorRoleCode": .string("MERCHANT_MANAGER"), "content": .string("Recorded facts"),
                 "createTime": .optional(time), "evidenceStatus": .string("NONE")])
    }
    func testSevenPlatformStatesKeepEveryMerchantOpinionIndependent() throws {
        for state in MerchantAftercareProgress.Processing.allCases {
            for opinion in MerchantAftercareProgress.Opinion.allCases {
                var fields = try fields(); fields["processing"] = .string(state.rawValue); fields["merchantOpinion"] = .string(opinion.rawValue)
                let value = try MerchantAftercareProgress(refundID: 62001, fields: fields)
                XCTAssertEqual(value.processing, state); XCTAssertEqual(value.opinion, opinion)
                XCTAssertEqual(value.funds, state == .refunded ? .confirmed : .unconfirmed)
            }
        }
    }
    func testUnknownPlatformOrOpinionRejectsInsteadOfShowingSuccess() throws {
        for key in ["processing", "merchantOpinion"] {
            var fields = try fields(); fields[key] = .string("UNRECOGNIZED")
            XCTAssertThrowsError(try MerchantAftercareProgress(refundID: 62001, fields: fields))
        }
    }
    func testOptionalRefundedBitCannotContradictProcessing() throws {
        for bit in [MerchantBusinessValue.bool(true), .string("false"), .int(0)] {
            var fields = try fields(); fields["refunded"] = bit
            XCTAssertThrowsError(try MerchantAftercareProgress(refundID: 62001, fields: fields))
        }
    }
    func testMissingAmountRemainsUnknownAndNegativeAmountIsRejected() throws {
        var fields = try fields(); fields.removeValue(forKey: "refundAmount")
        XCTAssertNil(try MerchantAftercareProgress(refundID: 62001, fields: fields).amount.raw)
        fields["refundAmount"] = .null
        XCTAssertNil(try MerchantAftercareProgress(refundID: 62001, fields: fields).amount.raw)
        fields["refundAmount"] = .string("0.00")
        XCTAssertEqual(try MerchantAftercareProgress(refundID: 62001, fields: fields).amount.display, "CNY 0.00")
        fields["refundAmount"] = .string("-1.00")
        XCTAssertThrowsError(try MerchantAftercareProgress(refundID: 62001, fields: fields))
    }
    func testTakeoverIsRecordedOnlyAndInsertsBetweenKnownResponses() throws {
        var fields = try fields()
        fields["createTime"] = .string("2026-10-01 08:00:00")
        fields["responses"] = .array([response(1, time: "2026-10-01 09:00:00"), response(2, time: "2026-10-02 09:00:00")])
        XCTAssertEqual(try MerchantAftercareProgress(refundID: 62001, fields: fields).events.map(\.id), ["request", "response:1", "response:2"])
        fields["platformTakeoverAt"] = .string("2026-10-02 08:00:00")
        let result = try MerchantAftercareProgress(refundID: 62001, fields: fields)
        XCTAssertEqual(result.events.map(\.id), ["request", "response:1", "takeover", "response:2"])
        XCTAssertEqual(result.events[2].occurredAt, try MerchantAftercareTime.parse("2026-10-02 08:00:00"))
        XCTAssertEqual(result.funds, .unconfirmed)
    }
    func testTakeoverWithoutResponseAndUnknownTimesRemainVisible() throws {
        var fields = try fields(); fields["platformTakeoverAt"] = .string("2026-10-02 08:00:00")
        XCTAssertEqual(try MerchantAftercareProgress(refundID: 62001, fields: fields).events.map(\.id), ["request", "takeover"])
        fields["responses"] = .array([response(1)])
        let result = try MerchantAftercareProgress(refundID: 62001, fields: fields)
        XCTAssertEqual(result.events.map(\.id), ["request", "response:1", "takeover"])
        XCTAssertNil(result.events[1].occurredAt)
    }
    func testDuplicateOrCrossRefundResponseIsRejectedByRealDocumentBoundary() throws {
        for responses in [[response(1), response(1)], [.object(["id": .int(1), "refundId": .int(62002), "decision": .string("AGREE")])]] {
            var fields = try fields(); fields["responses"] = .array(responses)
            XCTAssertThrowsError(try MerchantBusinessDocument(query: .refund(.init(62001)), payload: .object(fields)))
        }
    }
    func testWrongRefundDetailCannotProduceProgress() throws {
        XCTAssertThrowsError(try MerchantAftercareProgress(refundID: 62002, fields: fields()))
        let query = MerchantBusinessQuery.aftercare(.pending, page: 1)
        let document = try MerchantBusinessDocument(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query))
        XCTAssertNil(document.aftercareProgress)
    }
    func testMalformedDatesAndFieldTypesFailClosed() throws {
        for key in ["createTime", "platformTakeoverAt", "refundDeadline"] {
            for bad in [MerchantBusinessValue.string("2026-02-30 12:00:00"), .string("tomorrow"), .int(0)] {
                var fields = try fields(); fields[key] = bad
                XCTAssertThrowsError(try MerchantBusinessDocument(query: .refund(.init(62001)), payload: .object(fields)))
            }
        }
        for key in ["activityTitle", "customerNickname", "reason", "refundPolicyCode"] {
            var fields = try fields(); fields[key] = .bool(true)
            XCTAssertThrowsError(try MerchantAftercareProgress(refundID: 62001, fields: fields))
        }
    }
    func testUnknownPolicyRemainsRawWithoutInventedEligibility() throws {
        var fields = try fields(); fields["refundPolicyCode"] = .string("FUTURE_POLICY"); fields["refundPolicyVersion"] = .int(12)
        let value = try MerchantAftercareProgress(refundID: 62001, fields: fields)
        XCTAssertEqual(value.policyCode, "FUTURE_POLICY"); XCTAssertEqual(value.policyVersion, 12)
        fields["refundPolicyVersion"] = .int(0)
        XCTAssertThrowsError(try MerchantAftercareProgress(refundID: 62001, fields: fields))
    }
    func testEvidencePresenceNeverRetainsSignedURLOrActorIdentity() throws {
        var fields = try fields()
        for (status, expected) in [("NONE", MerchantAftercareProgress.Evidence.none), ("AVAILABLE", .recorded), ("UNAVAILABLE", .unavailable), ("FUTURE", .unavailable)] {
            fields["responses"] = .array([.object(["id": .int(1), "refundId": .int(62001), "decision": .string("EVIDENCE"),
                "evidenceStatus": .string(status), "evidenceUrl": .string("https://example.invalid/signed-private"),
                "actorRoleCode": .string("UNKNOWN_ROLE"), "actorMemberId": .int(991), "requestId": .string("private-request")])])
            let result = try MerchantAftercareProgress(refundID: 62001, fields: fields)
            XCTAssertEqual(result.responses.first?.evidence, expected)
            XCTAssertEqual(result.responses.first?.actorKey, "merchant.aftercareProgress.actor.unknown")
            XCTAssertFalse(String(reflecting: result).contains("signed-private")); XCTAssertFalse(String(reflecting: result).contains("private-request"))
        }
    }
    func testPhoneTimeZoneCrossesCalendarDayWhileDeadlineStaysBeijing() throws {
        let instant = try MerchantAftercareTime.parse("2026-10-08 01:15:00")
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(MerchantAftercareTime.event(instant, phoneTimeZone: losAngeles), "2026-10-07 10:15:00 -07:00")
        XCTAssertEqual(MerchantAftercareTime.event(instant, phoneTimeZone: utc), "2026-10-07 17:15:00 Z")
        XCTAssertEqual(MerchantAftercareTime.deadline(instant), "2026-10-08 01:15:00")
        // Same loaded instant, new phone zone: no refetch or cached display string.
        XCTAssertEqual(MerchantAftercareTime.event(instant, phoneTimeZone: MerchantAftercareTime.beijing), "2026-10-08 01:15:00 +08:00")
    }
    func testPhoneDSTSpringGapAndAutumnRepeatedHourKeepDistinctOffsets() throws {
        let phone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let springBefore = try MerchantAftercareTime.parse("2026-03-08 17:30:00")
        let springAfter = try MerchantAftercareTime.parse("2026-03-08 18:30:00")
        XCTAssertEqual(MerchantAftercareTime.event(springBefore, phoneTimeZone: phone), "2026-03-08 01:30:00 -08:00")
        XCTAssertEqual(MerchantAftercareTime.event(springAfter, phoneTimeZone: phone), "2026-03-08 03:30:00 -07:00")
        let autumnBefore = try MerchantAftercareTime.parse("2026-11-01 16:30:00")
        let autumnAfter = try MerchantAftercareTime.parse("2026-11-01 17:30:00")
        XCTAssertEqual(MerchantAftercareTime.event(autumnBefore, phoneTimeZone: phone), "2026-11-01 01:30:00 -07:00")
        XCTAssertEqual(MerchantAftercareTime.event(autumnAfter, phoneTimeZone: phone), "2026-11-01 01:30:00 -08:00")
        XCTAssertEqual(autumnAfter.timeIntervalSince(autumnBefore), 3_600)
    }
    func testReadTransportPreservesTakeoverAndResponseFacts() async throws {
        var fields = try fields(); fields["platformTakeoverAt"] = .string("2026-10-02 08:00:00")
        fields["responses"] = .array([response(1, time: "2026-10-02 09:00:00", decision: "AGREE")])
        let transport = AftercareProgressTransport(data: try JSONEncoder().encode(MerchantBusinessValue.object(["code": .int(200), "data": .object(fields)])))
        let service = try MerchantBusinessService(configuration: .init(baseURL: URL(string: "https://example.invalid")!), readTransport: transport)
        let access = try MerchantBusinessAccess(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        let result = try await service.document(.refund(.init(62001)), access: access, token: "synthetic-token")
        XCTAssertEqual(result.aftercareProgress?.events.map(\.id), ["request", "takeover", "response:1"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].url?.path, "/api/merchant/aftercare/detail")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "refundId", value: "62001")])
        XCTAssertFalse(service.canExecuteSyntheticMutation)
    }
}

private actor AftercareProgressTransport: HTTPTransport {
    let data: Data
    var requests: [URLRequest] = []
    init(data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, 200) }
}

@MainActor final class MerchantAftercareProgressLifetimeTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://aftercare", accountID: 99001, epoch: 1)
        let isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
        var pending: [CheckedContinuation<MerchantBusinessSnapshot, Error>] = []
        var calls = 0
        func access() async throws -> MerchantBusinessAccess {
            try .init(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            calls += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("Read-only progress must not submit"); throw MerchantBusinessFailure.disabled
        }
        func result(_ state: String = "WAITING_PLATFORM_REVIEW") throws -> MerchantBusinessSnapshot {
            var fields = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund).object)
            fields["processing"] = .string(state)
            let access = try MerchantBusinessAccess(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
            return try .init(access: access, document: .init(query: .refund(.init(62001)), payload: .object(fields)))
        }
    }
    private func wait(_ reader: Reader, count: Int) async throws {
        for _ in 0..<1_000 where reader.pending.count < count { await Task.yield() }
        guard reader.pending.count == count else { throw MerchantBusinessFailure.stale }
    }
    func testDismissedDetailCannotBeRestoredByLateResponse() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let coordinator = MerchantBusinessCoordinator(reader: reader, journal: journal)
        let load = Task { await coordinator.load(.refund(try! .init(62001))) }
        try await wait(reader, count: 1); coordinator.invalidate()
        reader.pending[0].resume(returning: try reader.result()); await load.value
        XCTAssertNil(coordinator.snapshot); XCTAssertFalse(coordinator.isCurrent); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testRepeatedRefreshKeepsNewerResultWhenOldResponseArrivesLast() async throws {
        let reader = Reader()
        // Use one retained reader for both requests.
        let tracked = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        let older = Task { await tracked.load(.refund(try! .init(62001))) }; try await wait(reader, count: 1)
        let newer = Task { await tracked.load(.refund(try! .init(62001))) }; try await wait(reader, count: 2)
        reader.pending[1].resume(returning: try reader.result("REFUNDED")); await newer.value
        reader.pending[0].resume(returning: try reader.result()); await older.value
        XCTAssertEqual(tracked.snapshot?.document.aftercareProgress?.funds, .confirmed)
        XCTAssertEqual(tracked.snapshot?.document.aftercareProgress?.processing, .refunded)
    }
    func testAccountChangeOrCancellationCannotDisplayOldProgress() async throws {
        for cancellation in [false, true] {
            let reader = Reader()
            let tracked = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
            let load = Task { await tracked.load(.refund(try! .init(62001))) }; try await wait(reader, count: 1)
            if cancellation { load.cancel() } else { reader.scope = .init(realm: "synthetic://aftercare", accountID: 99002, epoch: 2) }
            reader.pending[0].resume(returning: try reader.result("REFUNDED")); await load.value
            XCTAssertNil(tracked.snapshot); XCTAssertFalse(tracked.isCurrent)
        }
    }
}
