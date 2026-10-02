import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private final class NearbyWriteHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var response = "{\"code\":200}"
    var status = 200
    var lost = false
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?(); if lost { throw URLError(.networkConnectionLost) }
        return (Data(response.utf8), status)
    }
}
@MainActor private final class NearbyWriteMemoryJournal: NearbyTeamDispatchJournal {
    var records: [String: NearbyTeamDispatchRecord] = [:]
    var failWrite = false
    var failRead = false
    var failAcknowledgment = false
    func read(owner: String, target: String) throws -> NearbyTeamDispatchRecord? { if failRead { throw NearbyTeamFailure.contract }; return records[owner + "|" + target] }
    func write(_ record: NearbyTeamDispatchRecord) throws {
        if failWrite || (failAcknowledgment && record.phase == .acknowledged) { throw NearbyTeamFailure.contract }
        if let previous = records[record.ownerKey + "|" + record.targetKey], previous.operationID != record.operationID { throw NearbyTeamFailure.stale }
        records[record.ownerKey + "|" + record.targetKey] = record
    }
    func remove(_ record: NearbyTeamDispatchRecord) throws { records.removeValue(forKey: record.ownerKey + "|" + record.targetKey) }
}
@MainActor private final class NearbyWriteReadFake: NearbyTeamReadTransport {
    func sendRead(_ request: NearbyTeamRequest, session: NearbyTeamSession) async throws -> NearbyTeamResponse {
        NearbyTeamSyntheticFixtures.response(request.path == "/api/team/applications" ? NearbyTeamSyntheticFixtures.applicants : NearbyTeamSyntheticFixtures.teams)
    }
}
@MainActor final class NearbyTeamHTTPWriteTests: XCTestCase {
    private let session = NearbyTeamSyntheticFixtures.session
    private func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com")!) }
    private func evidence(_ review: NearbyTeamReview) -> NearbyTeamWriteEvidence { .init(session: review.session, team: review.team, applicant: review.applicant, application: review.application) }
    private func review(_ action: NearbyTeamAction = .apply(.init(501))) async throws -> NearbyTeamReview {
        let model = NearbyTeamSyntheticFixtures.coordinator(); await model.loadNearby(NearbyTeamSyntheticFixtures.context)
        if case .handle = action { await model.loadApplicants(teamID: action.teamID) }
        model.prepare(action); return try XCTUnwrap(model.review)
    }
    private func adapter(_ transport: NearbyWriteHTTPFake, journal: NearbyWriteMemoryJournal? = nil, paths: Set<String>? = ["api/team/apply", "api/team/withdraw", "api/team/handle"], accountID: Int? = nil, namespace: String? = nil,
                         current: (() -> NearbyTeamSession?)? = nil, token: String? = "synthetic-token",
                         fresh: ((NearbyTeamReview) async throws -> NearbyTeamWriteEvidence)? = nil) throws -> NearbyTeamHTTPWriteAdapter {
        let config = try configuration()
        let approval = try paths.map { try OperationEndpointApproval(baseURL: config.baseURL, namespace: namespace ?? session.namespace, accountID: accountID ?? session.accountID, paths: $0) }
        return .init(configuration: config, transport: transport, approval: approval, journal: journal ?? NearbyWriteMemoryJournal(), currentSession: current ?? { self.session }, token: { _ in token }, freshEvidence: fresh ?? { self.evidence($0) })
    }
    func testDefaultNilGrantNeverSends() async throws {
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport, paths: nil)
        let result = await adapter.submit(try await review()); XCTAssertEqual(result, .notSent); XCTAssertFalse(adapter.configured); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testApplyExactJSONAndServerAcknowledgmentExpiry() async throws {
        let transport = NearbyWriteHTTPFake(); transport.response = "{\"code\":200,\"data\":{\"applyExpireTime\":1700003600000}}"
        let adapter = try adapter(transport); let outcome = await adapter.submit(try await review())
        XCTAssertEqual(outcome, .acknowledged(expiry: .number(1700003600000)))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/team/apply"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{\"teamId\":501}")
    }
    func testWithdrawExactJSONIgnoresData() async throws {
        let transport = NearbyWriteHTTPFake(); transport.response = "{\"code\":200,\"data\":true}"
        let adapter = try adapter(transport); let outcome = await adapter.submit(try await review(.withdraw(.init(502))))
        XCTAssertEqual(outcome, .acknowledged(expiry: nil)); XCTAssertEqual(transport.requests.first?.url?.path, "/api/team/withdraw")
        XCTAssertEqual(String(data: try XCTUnwrap(transport.requests.first?.httpBody), encoding: .utf8), "{\"teamId\":502}")
    }
    func testHandleExactDistinctTeamAndApplicantAndBoolean() async throws {
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport)
        let outcome = await adapter.submit(try await review(.handle(team: .init(503), applicant: .init(6001), approved: false)))
        XCTAssertEqual(outcome, .acknowledged(expiry: nil))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.first?.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["teamId", "memberId", "approved"])
        XCTAssertEqual(body["teamId"] as? Int, 503); XCTAssertEqual(body["memberId"] as? Int, 6001); XCTAssertEqual(body["approved"] as? Bool, false)
    }
    func testWrongAccountNamespaceAndEndpointGrantsNeverSend() async throws {
        let review = try await review()
        for variant in 0..<3 {
            let transport = NearbyWriteHTTPFake()
            let adapter = try adapter(transport, paths: variant == 2 ? ["api/team/withdraw"] : ["api/team/apply"], accountID: variant == 0 ? 8 : nil, namespace: variant == 1 ? "other" : nil)
            let outcome = await adapter.submit(review); XCTAssertEqual(outcome, .notSent); XCTAssertTrue(transport.requests.isEmpty)
        }
    }
    func testFreshEvidenceChangePreventsDispatch() async throws {
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport, fresh: { review in .init(session: review.session, team: nil) })
        let outcome = await adapter.submit(try await review()); XCTAssertEqual(outcome, .notSent); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testLeaderAndApplicantFactsAreNotRouteGrants() async throws {
        let original = try await review()
        let forged = NearbyTeamReview(id: UUID(), action: .handle(team: .init(501), applicant: .init(6001), approved: true), session: session, revision: 1, team: original.team, applicant: nil, application: nil)
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport)
        let outcome = await adapter.submit(forged); XCTAssertEqual(outcome, .notSent); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testExpiredApplicantBlocksAtDispatch() async throws {
        let review = try await review(.handle(team: .init(503), applicant: .init(6001), approved: true))
        let config = try configuration(); let transport = NearbyWriteHTTPFake()
        let grant = try OperationEndpointApproval(baseURL: config.baseURL, namespace: session.namespace, accountID: session.accountID, paths: ["api/team/handle"])
        let adapter = NearbyTeamHTTPWriteAdapter(configuration: config, transport: transport, approval: grant, journal: NearbyWriteMemoryJournal(), currentSession: { self.session }, token: { _ in "synthetic-token" }, freshEvidence: { self.evidence($0) }, now: { Date(timeIntervalSince1970: 5_000_000_000) })
        let outcome = await adapter.submit(review); XCTAssertEqual(outcome, .notSent); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testMissingTokenAndStaleEpochBeforeSendBlock() async throws {
        let review = try await review()
        for variant in 0..<2 {
            let transport = NearbyWriteHTTPFake()
            let adapter = try adapter(transport, current: variant == 0 ? { nil } : nil, token: variant == 1 ? nil : "token")
            let outcome = await adapter.submit(review); XCTAssertEqual(outcome, .notSent); XCTAssertTrue(transport.requests.isEmpty)
        }
    }
    func testJournalIsDispatchedBeforeTransport() async throws {
        let journal = NearbyWriteMemoryJournal(); let transport = NearbyWriteHTTPFake()
        transport.onSend = { XCTAssertEqual(journal.records.values.first?.phase, .dispatched) }
        let adapter = try adapter(transport, journal: journal); _ = await adapter.submit(try await review())
        XCTAssertEqual(journal.records.values.first?.phase, .acknowledged)
    }
    func testLostResponseLocksAcrossAdapterRecreationAndEpoch() async throws {
        let journal = NearbyWriteMemoryJournal(); let transport = NearbyWriteHTTPFake(); transport.lost = true
        let first = try await review(); let adapter = try adapter(transport, journal: journal)
        let result = await adapter.submit(first); XCTAssertEqual(result, .unknown)
        let nextSession = NearbyTeamSession(accountID: session.accountID, epoch: 2, region: session.region, namespace: session.namespace, role: session.role)
        let next = NearbyTeamReview(id: UUID(), action: first.action, session: nextSession, revision: 1, team: first.team, applicant: nil, application: nil)
        let second = try self.adapter(transport, journal: journal, current: { nextSession })
        let retry = await second.submit(next); XCTAssertEqual(retry, .unknown); XCTAssertEqual(transport.requests.count, 1)
    }
    func testAcknowledgmentDoesNotReplayOrBecomeSimulation() async throws {
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport); let review = try await review()
        let first = await adapter.submit(review); let second = await adapter.submit(review)
        XCTAssertEqual(first, .acknowledged(expiry: nil)); XCTAssertEqual(second, .unknown); XCTAssertEqual(transport.requests.count, 1)
    }
    func testOppositeApplicantDecisionSharesReplayLock() async throws {
        let journal = NearbyWriteMemoryJournal(); let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport, journal: journal)
        let first = try await review(.handle(team: .init(503), applicant: .init(6001), approved: true))
        _ = await adapter.submit(first)
        let opposite = NearbyTeamReview(id: UUID(), action: .handle(team: .init(503), applicant: .init(6001), approved: false), session: first.session, revision: first.revision, team: first.team, applicant: first.applicant, application: nil)
        let result = await adapter.submit(opposite); XCTAssertEqual(result, .unknown); XCTAssertEqual(transport.requests.count, 1)
    }
    func testBusinessRejectionPreservesErrorCodeAndClearsJournal() async throws {
        let journal = NearbyWriteMemoryJournal(); let transport = NearbyWriteHTTPFake(); transport.response = "{\"code\":409,\"errorCode\":\"TEAM_FULL\",\"msg\":\"Full\"}"
        let adapter = try adapter(transport, journal: journal); let result = await adapter.submit(try await review())
        XCTAssertEqual(result, .rejected(errorCode: "TEAM_FULL", message: "Full")); XCTAssertTrue(journal.records.isEmpty)
    }
    func testMalformedHTTPFailureAndUnauthorizedRemainUnknown() async throws {
        for (status, json) in [(200, "{}"), (502, "{\"code\":200}"), (401, "{\"code\":401}")] {
            let journal = NearbyWriteMemoryJournal(); let transport = NearbyWriteHTTPFake(); transport.status = status; transport.response = json
            let adapter = try adapter(transport, journal: journal); let result = await adapter.submit(try await review())
            XCTAssertEqual(result, .unknown); XCTAssertEqual(journal.records.values.first?.phase, .dispatched)
        }
    }
    func testEpochChangeAfterSendCannotClearUnknownLock() async throws {
        var current: NearbyTeamSession? = session
        let journal = NearbyWriteMemoryJournal(); let transport = NearbyWriteHTTPFake(); transport.onSend = { current = nil }
        let adapter = try adapter(transport, journal: journal, current: { current }); let outcome = await adapter.submit(try await review())
        XCTAssertEqual(outcome, .unknown); XCTAssertEqual(journal.records.values.first?.phase, .dispatched)
    }
    func testJournalFailureBlocksNetworkAndKeepsUnknown() async throws {
        let journal = NearbyWriteMemoryJournal(); journal.failWrite = true
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport, journal: journal)
        let result = await adapter.submit(try await review()); XCTAssertEqual(result, .unknown); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testAcknowledgmentPersistenceFailureStaysUnknown() async throws {
        let journal = NearbyWriteMemoryJournal(); journal.failAcknowledgment = true
        let transport = NearbyWriteHTTPFake(); let adapter = try adapter(transport, journal: journal)
        let result = await adapter.submit(try await review()); XCTAssertEqual(result, .unknown); XCTAssertEqual(journal.records.values.first?.phase, .dispatched)
    }
    func testDefaultsJournalSurvivesRecreationWithoutSecrets() throws {
        let name = "nearby-write-" + UUID().uuidString; let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        let record = NearbyTeamDispatchRecord(operationID: UUID(), ownerKey: "deployment-account", targetKey: "handle:503:6001", phase: .dispatched)
        try NearbyTeamDefaultsDispatchJournal(defaults: defaults).write(record)
        XCTAssertEqual(try NearbyTeamDefaultsDispatchJournal(defaults: defaults).read(owner: record.ownerKey, target: record.targetKey), record)
        let serialized = String(data: try JSONEncoder().encode(record), encoding: .utf8)!
        for secret in ["token", "coordinate", "memberName", "applyMessage"] { XCTAssertFalse(serialized.contains(secret)) }
    }
    func testCoordinatorReportsAcknowledgmentAndServerExpiry() async throws {
        let transport = NearbyWriteHTTPFake(); transport.response = "{\"code\":200,\"data\":{\"applyExpireTime\":1700003600000}}"
        let adapter = try adapter(transport)
        let service = NearbyTeamService(readTransport: NearbyWriteReadFake(), liveReadGrant: true, writeAdapter: adapter)
        let model = NearbyTeamCoordinator(service: service, session: session, locks: .init())
        await model.loadNearby(NearbyTeamSyntheticFixtures.context); model.prepare(.apply(.init(501)))
        await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(model.messageKey, "nearby.acknowledged"); XCTAssertFalse(model.synthetic); XCTAssertFalse(model.uncertain)
        XCTAssertEqual(model.teams[0].viewerStatus, .pending); XCTAssertEqual(model.teams[0].applyExpireTime, .number(1700003600000))
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testServiceRequiresMatchingImmutableReviewForHTTPWrite() async throws {
        let transport = NearbyWriteHTTPFake(); let service = NearbyTeamService(writeAdapter: try adapter(transport))
        let absent = await service.submit(.apply(.init(501)), session: session); XCTAssertEqual(absent, .notSent)
        let mismatched = await service.submit(.apply(.init(999)), session: session, review: try await review()); XCTAssertEqual(mismatched, .notSent)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testConcurrentAdapterInstancesCannotReplaySameReview() async throws {
        let transport = NearbyWriteHTTPFake(); let journal = NearbyWriteMemoryJournal(); let review = try await review()
        let fresh: (NearbyTeamReview) async throws -> NearbyTeamWriteEvidence = { snapshot in await Task.yield(); return self.evidence(snapshot) }
        let first = try adapter(transport, journal: journal, fresh: fresh)
        let second = try adapter(transport, journal: journal, fresh: fresh)
        async let a = first.submit(review)
        async let b = second.submit(review)
        let results = await [a, b]
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(results.contains(.acknowledged(expiry: nil))); XCTAssertTrue(results.contains(.unknown))
    }

}
