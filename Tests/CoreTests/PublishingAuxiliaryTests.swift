import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PublishingAuxFakeTransport: HTTPTransport {
    var replies: [String?]
    var requests: [URLRequest] = []
    var onSend: (() -> Void)?
    init(_ replies: [String?] = []) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        guard !replies.isEmpty, let value = replies.removeFirst() else { throw URLError(.networkConnectionLost) }
        return (Data(value.utf8), 200)
    }
}
@MainActor private final class PublishingAuxJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = record }
    func clear(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = nil }
}
@MainActor final class PublishingAuxiliaryTests: XCTestCase {
    private func session(region: PublishingRegion = .china, role: String = "club") -> PublishingSession { .init(namespace: "synthetic", accountID: 901, epoch: UUID(), role: role, region: region) }
    // Reserved .test endpoint; all requests are captured by PublishingAuxFakeTransport.
    private func config() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.test")!) }
    private func client(_ transport: PublishingAuxFakeTransport, session: PublishingSession, journal: PublishingAuxJournal? = nil, approved: Bool = true) throws -> PublishingAuxiliaryService {
        let credential = try PublishingCredentials(session: session, token: "synthetic")
        let approval = try OperationEndpointApproval(baseURL: config().baseURL, namespace: session.namespace, accountID: session.accountID,
            paths: ["api/ai/theme/draft", "api/ai/template/fill", "api/ai/club/design", "api/ai/safety/precheck", "api/publisher/identity"])
        return try PublishingAuxiliaryService(configuration: config(), transport: transport, approval: approved ? approval : nil,
                                              journal: journal ?? PublishingAuxJournal(), credentials: { credential })
    }
    /// Unissued all-zero address prefix; intentionally synthetic, never a real person's ID.
    private func syntheticID() -> String {
        let prefix = "00000020000101001", weights = [7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2]
        let sum = zip(prefix, weights).reduce(0) { $0 + ($1.0.wholeNumberValue ?? 0) * $1.1 }
        return prefix + String(Array("10X98765432")[sum % 11])
    }
    func testAIExactExecutableRequestsAndPayloads() async throws {
        let s = session(), t = PublishingAuxFakeTransport(Array(repeating: #"{"code":200,"data":{"fixture":true}}"#, count: 4)), api = try client(t, session: s)
        let operations: [PublishingAssistance] = [.theme(idea: " idea "), .template(shopName: "shop", extraNote: "note", category: "", reward: "", playStyle: "", validationMethod: 2), .club(idea: " idea ", style: nil, minutes: 30), .safety(["text": .string("synthetic")])]
        for op in operations { let review = try api.prepare(op, session: s); let result = await api.confirm(review); XCTAssertEqual(result, .acknowledged(.object(["fixture": .bool(true)]))) }
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/ai/theme/draft", "/api/ai/template/fill", "/api/ai/club/design", "/api/ai/safety/precheck"])
        let bodies = try t.requests.map { try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(bodies[0], ["idea": .string("idea")]); XCTAssertEqual(bodies[1]["category"], .string("")); XCTAssertEqual(bodies[1]["validationMethod"], .number(2)); XCTAssertNil(bodies[2]["clubStyle"]); XCTAssertEqual(bodies[2]["targetDurationMin"], .number(30))
        for request in t.requests { XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json"); XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key")) }
    }
    func testDefaultAuxiliaryMakesZeroRequests() async throws {
        let s = session(), t = PublishingAuxFakeTransport(), api = try client(t, session: s, approved: false)
        let review = try api.prepare(.theme(idea: "synthetic"), session: s); let result = await api.confirm(review)
        XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
    }
    func testUSProviderGateCannotBeEnabledByGenericApproval() async throws {
        let s = session(region: .unitedStates), t = PublishingAuxFakeTransport(), api = try client(t, session: s)
        let review = try api.prepare(.theme(idea: "synthetic"), session: s); let result = await api.confirm(review)
        XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
    }
    func testPlayerThemePlanningStillCannotDispatchWithoutProviderGrant() async throws {
        // Current backend gateThemeDraftRole permits players for theme drafting only.
        let s = session(role: "player"), t = PublishingAuxFakeTransport(), api = try client(t, session: s, approved: false)
        let current = try api.prepare(.themeForProduct(idea: "synthetic", product: .freeExplore), session: s)
        XCTAssertEqual(current.request.path, "api/ai/theme/draft")
        XCTAssertEqual(current.request.fields, ["idea": .string("synthetic"), "productType": .number(2)])
        XCTAssertTrue(t.requests.isEmpty)
        let result = await api.confirm(current)
        XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
        // The retained descriptor has the same backend role gate, but no normal-host grant.
        let legacy = try api.prepare(.theme(idea: "synthetic"), session: s)
        api.cancel(legacy); XCTAssertTrue(t.requests.isEmpty)
    }
    func testPlayerCannotPrepareClubTemplateOrSafetyEvenWithGenericApproval() throws {
        let s = session(role: "player"), t = PublishingAuxFakeTransport(), api = try client(t, session: s)
        let restricted: [PublishingAssistance] = [
            .template(shopName: "Synthetic", extraNote: "Synthetic", category: "", reward: "", playStyle: "", validationMethod: nil),
            .club(idea: "Synthetic", style: nil, minutes: nil), .safety(["text": .string("Synthetic")])
        ]
        for operation in restricted { XCTAssertThrowsError(try api.prepare(operation, session: s)) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testPlayerThemeRequiresExactPathGrantAndDurableJournal() async throws {
        let s = session(role: "player"), t = PublishingAuxFakeTransport()
        let credential = try PublishingCredentials(session: s, token: "synthetic")
        let wrongPath = try OperationEndpointApproval(baseURL: config().baseURL, namespace: s.namespace, accountID: s.accountID, paths: ["api/ai/club/design"])
        let wrongPathClient = try PublishingAuxiliaryService(configuration: config(), transport: t, approval: wrongPath,
            journal: PublishingAuxJournal(), credentials: { credential })
        let first = try wrongPathClient.prepare(.themeForProduct(idea: "Synthetic", product: .city), session: s)
        let deniedPath = await wrongPathClient.confirm(first); XCTAssertEqual(deniedPath, .notSent)
        let themePath = try OperationEndpointApproval(baseURL: config().baseURL, namespace: s.namespace, accountID: s.accountID, paths: ["api/ai/theme/draft"])
        let noJournalClient = try PublishingAuxiliaryService(configuration: config(), transport: t, approval: themePath, credentials: { credential })
        let second = try noJournalClient.prepare(.themeForProduct(idea: "Synthetic", product: .city), session: s)
        let deniedJournal = await noJournalClient.confirm(second); XCTAssertEqual(deniedJournal, .notSent)
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testUnknownRoleCannotPrepareThemeAndUSPlayerCannotDispatch() async throws {
        let unknown = session(role: "unknown"), t = PublishingAuxFakeTransport(), unknownClient = try client(t, session: unknown)
        XCTAssertThrowsError(try unknownClient.prepare(.themeForProduct(idea: "Synthetic", product: .city), session: unknown))
        let us = session(region: .unitedStates, role: "player"), usClient = try client(t, session: us)
        let review = try usClient.prepare(.themeForProduct(idea: "Synthetic", product: .city), session: us)
        let result = await usClient.confirm(review); XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
    }
    func testChinaIdentityExecutesExactTransientBodyAfterStatusRead() async throws {
        let s = session(), j = PublishingAuxJournal(), t = PublishingAuxFakeTransport([#"{"code":200,"data":{"registered":false}}"#, #"{"code":200}"#]), api = try client(t, session: s, journal: j)
        let review = try api.prepareIdentity(name: " Synthetic ", idCard: syntheticID().lowercased(), consent: true, source: "topic_publish", registered: false, currentYear: 2030, session: s)
        t.onSend = { if t.requests.count == 2 { XCTAssertEqual(j.records.count, 1); let encoded = try? JSONEncoder().encode(Array(j.records.values)); XCTAssertFalse(String(data: encoded ?? Data(), encoding: .utf8)!.contains("idCard")) } }
        let result = await api.confirm(review); XCTAssertEqual(result, .acknowledged(.null))
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/publisher/identity/status", "/api/publisher/identity"])
        let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(t.requests.last?.httpBody))
        XCTAssertEqual(body, ["realName": .string("Synthetic"), "idCard": .string(syntheticID()), "consent": .bool(true), "source": .string("topic_publish")])
        XCTAssertTrue(j.records.isEmpty)
    }
    func testRegisteredIdentityIsNotRebound() async throws {
        let s = session(), t = PublishingAuxFakeTransport([#"{"code":200,"data":{"registered":true}}"#]), api = try client(t, session: s)
        let review = try api.prepareIdentity(name: "Synthetic", idCard: syntheticID(), consent: true, source: "topic_publish", registered: false, currentYear: 2030, session: s)
        let result = await api.confirm(review); XCTAssertEqual(result, .notSent); XCTAssertEqual(t.requests.count, 1)
    }
    func testIdentityConsentSourceAndUSRestrictionsBeforeAnyTransport() throws {
        let s = session(), t = PublishingAuxFakeTransport(), api = try client(t, session: s)
        XCTAssertThrowsError(try api.prepareIdentity(name: "Synthetic", idCard: syntheticID(), consent: false, source: "topic_publish", registered: false, currentYear: 2030, session: s))
        XCTAssertThrowsError(try api.prepareIdentity(name: "Synthetic", idCard: syntheticID(), consent: true, source: "invented", registered: false, currentYear: 2030, session: s))
        let us = session(region: .unitedStates), usAPI = try client(t, session: us)
        XCTAssertThrowsError(try usAPI.prepareIdentity(name: "Synthetic", idCard: syntheticID(), consent: true, source: "topic_publish", registered: false, currentYear: 2030, session: us)); XCTAssertTrue(t.requests.isEmpty)
    }
    func testLostAuxiliaryResponseBlocksRestartRetry() async throws {
        let s = session(), j = PublishingAuxJournal(), t = PublishingAuxFakeTransport([nil]), api = try client(t, session: s, journal: j)
        let first = try api.prepare(.theme(idea: "synthetic"), session: s); let outcome = await api.confirm(first); XCTAssertEqual(outcome, .unknown)
        let nextTransport = PublishingAuxFakeTransport(), next = try client(nextTransport, session: s, journal: j)
        let second = try next.prepare(.theme(idea: "changed"), session: s); let blocked = await next.confirm(second)
        XCTAssertEqual(blocked, .unknown); XCTAssertTrue(nextTransport.requests.isEmpty)
    }
    func testSafetySoftGateAndParseErrorAreNotContentBlocks() async throws {
        let s = session(), t = PublishingAuxFakeTransport([#"{"code":429,"msg":"Quota unavailable"}"#]), api = try client(t, session: s)
        let review = try api.prepare(.safety([:]), session: s); let result = await api.confirm(review); XCTAssertEqual(result, .unavailable("Quota unavailable"))
        let issues = try PublishingSafetyIssue.decode(.object(["issues": .array([.object(["level": .string("error"), "type": .string("parse_error"), "message": .string("synthetic")])])]))
        XCTAssertFalse(try XCTUnwrap(issues.first).blocksPublication)
    }
    func testCancellationAndStaleAccountDiscardAuxiliaryReview() async throws {
        let s = session(), t = PublishingAuxFakeTransport(), api = try client(t, session: s)
        let review = try api.prepare(.theme(idea: "synthetic"), session: s); api.cancel(review)
        let cancelled = await api.confirm(review); XCTAssertEqual(cancelled, .notSent); XCTAssertTrue(t.requests.isEmpty)
        var credential: PublishingCredentials? = try .init(session: s, token: "synthetic")
        let unapproved = try PublishingAuxiliaryService(configuration: config(), transport: t, credentials: { credential })
        let stale = try unapproved.prepare(.theme(idea: "synthetic"), session: s); credential = nil
        let changed = await unapproved.confirm(stale); XCTAssertEqual(changed, .notSent)
    }
    func testUnavailableSafetyStaysSoftGateButRetainsRetryLock() async throws {
        let s = session(), j = PublishingAuxJournal(), t = PublishingAuxFakeTransport([nil]), api = try client(t, session: s, journal: j)
        let review = try api.prepare(.safety([:]), session: s); let result = await api.confirm(review)
        XCTAssertEqual(result, .unavailable("")); XCTAssertEqual(j.records.count, 1)
        let repeatReview = try api.prepare(.safety([:]), session: s); let repeated = await api.confirm(repeatReview)
        XCTAssertEqual(repeated, .unavailable("")); XCTAssertEqual(t.requests.count, 1)
    }

}
