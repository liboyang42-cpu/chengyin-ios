import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class IdentityJournal: OperationPendingJournal {
    var value: OperationPendingRecord?
    var unreadable = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if unreadable { throw PublishModesError.storage }
        return value.flatMap { $0.ownerKey == ownerKey && $0.targetKey == targetKey ? $0 : nil }
    }
    func write(_ record: OperationPendingRecord) throws {
        guard value == nil || value == record else { throw PublishModesError.uncertain }; value = record
    }
    func clear(_ record: OperationPendingRecord) throws { guard value == record else { throw PublishModesError.storage }; value = nil }
}
@MainActor private final class IdentityTransport: HTTPTransport {
    var paths: [String] = []
    var registered = false
    var loseWrite = false
    var failRead = false
    var badACK = false
    var code = 200
    var registeredValue: ProjectEditJSON?
    var onRead: (() async -> Void)?
    var onWrite: (() -> Void)?
    var bodyCheck: (([String: ProjectEditJSON]) throws -> Void)?
    var writes: Int { paths.filter { $0 == "/api/publisher/identity" }.count }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""; paths.append(path)
        if path.hasSuffix("/status") {
            if let onRead { await onRead() }
            if failRead { throw URLError(.networkConnectionLost) }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(["registered": registeredValue ?? .bool(registered)])]), 200)
        }
        try bodyCheck?(JSONDecoder().decode([String: ProjectEditJSON].self, from: request.httpBody ?? Data()))
        onWrite?()
        if loseWrite { throw URLError(.networkConnectionLost) }
        if code == 200 && !badACK { registered = true }
        return (try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(code)), "data": .object(["registered": badACK ? .string("true") : .bool(true)])]), 200)
    }
}
@MainActor private final class IdentityHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://identity.example.test")!)
    let session: PublishingSession
    var credentials: PublishingCredentials?
    let transport = IdentityTransport()
    let journal = IdentityJournal()
    var grants = PublisherIdentityRegistrationGrants()
    init(approved: Bool = true, role: String = "club", region: PublishingRegion = .china) throws {
        session = PublishingSession(namespace: "identity-tests", accountID: 7, epoch: UUID(), role: role, region: region)
        credentials = try PublishingCredentials(session: session, token: "synthetic-identity-token")
        if approved {
            grants = try PublisherIdentityRegistrationGrants(
                read: OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [PublisherIdentityRegistrationWire.statusPath]),
                register: OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [PublisherIdentityRegistrationWire.registerPath]))
        }
    }
    func service() -> PublisherIdentityRegistrationService {
        PublisherIdentityRegistrationService(configuration: configuration, transport: transport, grants: grants,
            journal: journal, session: session, credentials: { [weak self] in self?.credentials })
    }
    // Deliberately nonexistent region prefix; generated checksum fixture, not a person's identifier.
    var syntheticID: String {
        let digits = Array("00000020000101000"), weights = [7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2]
        let sum = (0..<17).reduce(0) { $0 + digits[$1].wholeNumberValue! * weights[$1] }
        return String(digits) + String(Array("10X98765432")[sum % 11])
    }
    func prepare(_ service: PublisherIdentityRegistrationService, consent: Bool = true) throws -> PublishingAuxiliaryReview {
        try service.prepare(name: "演示", idCard: syntheticID, consent: consent, currentYear: 2026)
    }
}

@MainActor final class PublisherIdentityRegistrationTests: XCTestCase {
    func testDefaultNilDoesNotReadOrWrite() async throws {
        let h = try IdentityHarness(approved: false), s = h.service(); s.activate()
        XCTAssertFalse(s.configured); do { _ = try await s.status(); XCTFail() } catch {}
        XCTAssertThrowsError(try h.prepare(s)); XCTAssertTrue(h.transport.paths.isEmpty)
    }
    func testActivityApprovalCannotEnableIdentity() throws {
        let h = try IdentityHarness(approved: false)
        let other = try OperationEndpointApproval(baseURL: h.configuration.baseURL, namespace: h.session.namespace, accountID: 7, paths: ["api/activity/publish", "api/activity/update"])
        h.grants = .init(read: other, register: other); let s = h.service(); s.activate()
        XCTAssertFalse(s.configured); XCTAssertThrowsError(try h.prepare(s)); XCTAssertTrue(h.transport.paths.isEmpty)
    }
    func testConsentAndExistingValidationAreMandatory() throws {
        let h = try IdentityHarness(), s = h.service(); s.activate()
        XCTAssertThrowsError(try h.prepare(s, consent: false))
        XCTAssertThrowsError(try s.prepare(name: "x", idCard: h.syntheticID, consent: true, currentYear: 2026))
        XCTAssertThrowsError(try s.prepare(name: "演示", idCard: "invalid", consent: true, currentYear: 2026))
        XCTAssertNil(h.journal.value); XCTAssertTrue(h.transport.paths.isEmpty)
    }
    func testExactExplicitJSONHasNoRequestIdentifierOrPersonalDataInURL() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate()
        h.transport.bodyCheck = { body in
            XCTAssertEqual(Set(body.keys), Set(["realName", "idCard", "consent", "source"]))
            XCTAssertEqual(body["source"], .string("topic_publish")); XCTAssertEqual(body["consent"], .bool(true))
        }
        let r = try h.prepare(s); let result = await s.submit(r)
        guard case .acknowledged = result else { return XCTFail() }
        XCTAssertEqual(h.transport.paths, ["/api/publisher/identity/status", "/api/publisher/identity"])
        XCTAssertEqual(h.transport.writes, 1); XCTAssertNil(h.journal.value)
    }
    func testAlreadyRegisteredPreflightDoesNotWriteOrChangeIdentity() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); h.transport.registered = true
        let result = await s.submit(try h.prepare(s)); XCTAssertEqual(result, .notSent); XCTAssertEqual(h.transport.writes, 0)
    }
    func testDuplicateConfirmationUsesOneRequest() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); let r = try h.prepare(s)
        _ = await s.submit(r); let again = await s.submit(r)
        XCTAssertEqual(again, .notSent); XCTAssertEqual(h.transport.writes, 1)
    }
    func testCancelledReviewDoesNotSend() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); let r = try h.prepare(s); s.cancel(r)
        let result = await s.submit(r); XCTAssertEqual(result, .notSent); XCTAssertTrue(h.transport.paths.isEmpty)
    }
    func testUnknownReconstructionCannotResendAndMarkerHasOnlyOpaqueFields() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); h.transport.loseWrite = true
        let r = try h.prepare(s); let outcome = await s.submit(r); XCTAssertEqual(outcome, .unknown)
        let saved = try XCTUnwrap(h.journal.value); XCTAssertEqual(saved.operationID, r.id)
        let bytes = try JSONEncoder().encode(saved); let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("演示")); XCTAssertFalse(text.contains(h.syntheticID)); XCTAssertFalse(text.contains("realName"))
        s.retire(); let next = h.service(); next.activate(); XCTAssertThrowsError(try h.prepare(next))
        let status = try await next.status(); XCTAssertFalse(status); XCTAssertEqual(try next.pending(), saved); XCTAssertEqual(h.transport.writes, 1)
    }
    func testMalformedSuccessKeepsUnknownMarker() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); h.transport.badACK = true
        let outcome = await s.submit(try h.prepare(s)); XCTAssertEqual(outcome, .unknown); XCTAssertNotNil(h.journal.value)
    }
    func testStrictStatusRejectsNumericAndStringBooleans() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate()
        for value in [ProjectEditJSON.number(1), .string("true"), .null] {
            h.transport.registeredValue = value; do { _ = try await s.status(); XCTFail() } catch {}
        }
        XCTAssertEqual(h.transport.writes, 0)
    }
    func testExplicitRejectionPreservesNoSensitivePersistentPayload() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); h.transport.code = 500
        let result = await s.submit(try h.prepare(s)); guard case .rejected = result else { return XCTFail() }
        XCTAssertNil(h.journal.value); XCTAssertEqual(h.transport.writes, 1)
    }
    func testRetireDuringPreflightCannotSendAfterReactivation() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); let r = try h.prepare(s)
        h.transport.onRead = { s.retire(); s.activate() }
        let result = await s.submit(r); XCTAssertEqual(result, .notSent); XCTAssertEqual(h.transport.writes, 0)
    }
    func testRetireDuringDispatchKeepsUnknownInsteadOfLateAcknowledgment() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate()
        h.transport.onWrite = { s.retire(); s.activate() }
        let result = await s.submit(try h.prepare(s)); XCTAssertEqual(result, .unknown); XCTAssertNotNil(h.journal.value)
    }
    func testAccountChangeBeforeResponseRejectsLateResult() async throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); h.transport.onRead = { h.credentials = nil }
        do { _ = try await s.status(); XCTFail() } catch {}
        XCTAssertNil(s.currentSession); XCTAssertEqual(h.transport.writes, 0)
    }
    func testNonClubOrNonChinaCannotDispatch() async throws {
        for h in [try IdentityHarness(role: "merchant"), try IdentityHarness(role: "player"), try IdentityHarness(region: .unitedStates)] {
            let s = h.service(); s.activate(); XCTAssertFalse(s.configured)
            do { _ = try await s.status(); XCTFail() } catch {}; XCTAssertTrue(h.transport.paths.isEmpty)
        }
    }
    func testUnreadableJournalPreventsPreparingAnotherRequest() throws {
        let h = try IdentityHarness(), s = h.service(); s.activate(); h.journal.unreadable = true
        XCTAssertThrowsError(try h.prepare(s)); XCTAssertTrue(h.transport.paths.isEmpty)
    }
    func testOldReviewCannotMoveToAnotherServiceOwner() async throws {
        let h = try IdentityHarness(), first = h.service(), second = h.service(); first.activate(); second.activate()
        let r = try h.prepare(first); let result = await second.submit(r)
        XCTAssertEqual(result, .notSent); XCTAssertTrue(h.transport.paths.isEmpty)
    }
    func testTypedWireRejectsWrongSourceExtraFieldsAndQuery() throws {
        let h = try IdentityHarness(); var body = try PublishingIdentity.registration(name: "演示", idCard: h.syntheticID, consent: true, source: "topic_publish", region: .china, registered: false, currentYear: 2026).fields
        func request() throws -> URLRequest { try OperationAdapterHTTP.json(configuration: h.configuration, path: PublisherIdentityRegistrationWire.registerPath, body: JSONEncoder().encode(body), token: "synthetic-identity-token") }
        XCTAssertNotNil(PublisherIdentityRegistrationWire.path(try request(), configuration: h.configuration))
        body["source"] = .string("merchant_apply"); XCTAssertNil(PublisherIdentityRegistrationWire.path(try request(), configuration: h.configuration))
        body["source"] = .string("topic_publish"); body["requestID"] = .string("not-on-wire"); XCTAssertNil(PublisherIdentityRegistrationWire.path(try request(), configuration: h.configuration))
        body["requestID"] = nil; var r = try request(); r.url = URL(string: "https://identity.example.test/api/publisher/identity?name=example")
        XCTAssertNil(PublisherIdentityRegistrationWire.path(r, configuration: h.configuration))
    }
}
