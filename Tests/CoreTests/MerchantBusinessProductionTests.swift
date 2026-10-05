import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class MerchantBusinessProductionTests: XCTestCase {
    private let url = URL(string: "https://example.com")!
    private func context(epoch: UInt64 = 1, role: String = "merchant", namespace: String = "merchant-cn") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: url, role: role, session: try .init(accountID: 21, epoch: epoch, namespace: namespace, token: "test-token"))
    }
    private func mutation(_ decision: MerchantAftercareDecision = .agree) throws -> MerchantBusinessMutation {
        .aftercare(refund: try .init(31), decision: decision, content: "Reviewed opinion", evidenceKey: nil)
    }
    private func approval(_ mutation: MerchantBusinessMutation) throws -> MerchantBusinessProductionApproval {
        try .init(market: .china, endpoints: .init(baseURL: url, namespace: "merchant-cn", accountID: 21, paths: [mutation.request(requestID: "grant-validation").path]),
            grants: [.init(merchantID: 11, mutation: mutation)], reviewedPolicyVersion: "policy-1")
    }
    private func reader(_ wire: Wire, grantMutation: MerchantBusinessMutation? = nil, beforeForward: (@MainActor () async -> Void)? = nil, current: @escaping () -> RuntimeDependencyContext?) throws -> MerchantBusinessSessionReader {
        let api = try APIConfiguration(baseURL: url), approval = try self.approval(grantMutation ?? mutation())
        return MerchantBusinessSessionReader(service: .init(configuration: api, readTransport: wire), currentSession: {
            guard let c = current() else { return nil }; return try? .init(accountID: c.session.accountID, epoch: c.session.epoch, token: c.session.token)
        }, productionService: { mutation, merchantID in
            var factory = MerchantBusinessProductionFactory(api: api, approval: approval, transport: wire, current: current)
            if let beforeForward { factory = factory.withDispatchBarrier(beforeForward) }
            return factory.service(for: mutation, merchantID: merchantID)
        }, runtimeContext: current)
    }
    private func journalURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("intents.json") }
    private func review(_ coordinator: MerchantBusinessCoordinator) async throws -> MerchantBusinessConfirmation {
        await coordinator.load(.refund(try .init(31))); coordinator.prepare(try mutation()); return try XCTUnwrap(coordinator.confirmation)
    }
    func testNoApprovalCannotConstructProductionService() throws {
        let c = try context(), wire = Wire()
        let factory = MerchantBusinessProductionFactory(api: try .init(baseURL: url), transport: wire, current: { c })
        XCTAssertNil(factory.service(for: try mutation(), merchantID: 11)); XCTAssertEqual(wire.writes, 0)
    }
    func testDirectServiceCallCannotBypassFreshReviewedCoordinator() async throws {
        let c = try context(), wire = Wire(), mutation = try self.mutation()
        let factory = MerchantBusinessProductionFactory(api: try .init(baseURL: url), approval: try self.approval(mutation), transport: wire, current: { c })
        let service = try XCTUnwrap(factory.service(for: mutation, merchantID: 11))
        do { _ = try await service.execute(mutation, requestID: "test-direct", token: c.session.token); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactOpinionAndMerchantGrantCannotExpandAuthority() throws {
        let m = try mutation(), approval = try self.approval(m), c = try context()
        XCTAssertTrue(approval.permits(m, merchantID: 11, context: c))
        XCTAssertFalse(approval.permits(try mutation(.reject), merchantID: 11, context: c))
        XCTAssertFalse(approval.permits(m, merchantID: 12, context: c))
        XCTAssertFalse(approval.permits(m, merchantID: 11, context: try context(namespace: "other")))
        XCTAssertFalse(approval.permits(.aftercare(refund: try .init(32), decision: .agree, content: "", evidenceKey: nil), merchantID: 11, context: c))
    }
    func testGrantCannotExpandNestedTargetOrDestinationRole() throws {
        let c = try context()
        let invite = MerchantBusinessMutation.inviteOperator(role: "MERCHANT_CHECKIN")
        XCTAssertFalse(try self.approval(invite).permits(.inviteOperator(role: "MERCHANT_MANAGER"), merchantID: 11, context: c))
        let note = MerchantBusinessMutation.hideNote(customer: try .init(51), noteID: 61, expectedVersion: 1)
        XCTAssertFalse(try self.approval(note).permits(.hideNote(customer: .init(51), noteID: 62, expectedVersion: 1), merchantID: 11, context: c))
        let tag = MerchantBusinessMutation.removeTag(customer: try .init(51), tagID: 61)
        XCTAssertFalse(try self.approval(tag).permits(.removeTag(customer: .init(51), tagID: 62), merchantID: 11, context: c))
    }
    func testPreparedReviewCannotBypassReaderReservation() async throws {
        let c = try context(), wire = Wire()
        let actual = try self.reader(wire, current: { c })
        let coordinator = MerchantBusinessCoordinator(reader: actual, journal: MerchantBusinessMemoryIntentStore())
        let pending = try await review(coordinator)
        do { _ = try await actual.execute(pending, check: {}); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testMixedSyntheticBaseNeverSelectsProductionTransport() async throws {
        let c = try context(), live = Wire(), test = TestingWire(), api = try APIConfiguration(baseURL: url), approval = try self.approval(mutation())
        let reader = MerchantBusinessSessionReader(service: .init(configuration: api, readTransport: test, testingMutationTransport: test),
            currentSession: { try? .init(accountID: 21, epoch: 1, token: "test-token") },
            productionService: { mutation, merchantID in MerchantBusinessProductionFactory(api: api, approval: approval, transport: live, current: { c }).service(for: mutation, merchantID: merchantID) }, runtimeContext: { c })
        let coordinator = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        let pending = try await review(coordinator); await coordinator.confirm(pending)
        XCTAssertNotNil(coordinator.receipt); XCTAssertEqual(test.wire.writes, 1); XCTAssertTrue(live.requests.isEmpty)
    }
    func testFinanceRoleCannotBecomeDecisionMakerFromBroadRespondBit() throws {
        let raw = #"{"active":true,"merchant":{"id":11},"roleCode":"MERCHANT_FINANCE","permissions":["merchant:aftercare:read","merchant:aftercare:respond","merchant:aftercare:evidence","merchant:aftercare:decide"]}"#
        let access = try MerchantBusinessAccess(JSONDecoder().decode(MerchantBusinessValue.self, from: Data(raw.utf8)).object!)
        let payload = #"{"refundId":31,"processing":"WAITING_PLATFORM_REVIEW","merchantOpinion":"PENDING","canRespond":true,"allowedDecisions":["AGREE","EVIDENCE"],"responses":[]}"#
        let document = try MerchantBusinessDocument(query: .refund(.init(31)), payload: JSONDecoder().decode(MerchantBusinessValue.self, from: Data(payload.utf8)))
        XCTAssertThrowsError(try mutation().validate(in: document, access: access))
        let evidence = MerchantBusinessMutation.aftercare(refund: try .init(31), decision: .evidence, content: "Evidence", evidenceKey: "upload/merchant-aftercare-evidence/" + String(repeating: "a", count: 32) + ".png")
        XCTAssertNoThrow(try evidence.validate(in: document, access: access))
    }
    func testProductionHTTPOpinionIsNotRefundExecution() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let reader = try self.reader(wire, current: { c }), coordinator = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessFileIntentStore(url: path))
        let pending = try await review(coordinator); await coordinator.confirm(pending)
        XCTAssertFalse(reader.canExecuteSyntheticMutation); XCTAssertEqual(wire.writes, 1)
        XCTAssertEqual(coordinator.receipt?.refundActuallyConfirmed, false)
        XCTAssertEqual(try MerchantBusinessFileIntentStore(url: path).intents().count, 0)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/merchant/access/me" }.count, 3)
        let request = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(request.url?.query, "refundId=31"); XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(request.httpBody)).object
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertEqual(body, ["decision": .string("AGREE"), "content": .string("Reviewed opinion"), "requestId": .string(pending.requestID)])
    }
    func testProductionCRUDUsesExactCustomerPath() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let mutation = MerchantBusinessMutation.addNote(customer: try .init(51), content: "Reviewed note", correctsNoteID: nil)
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, grantMutation: mutation, current: { c }), journal: MerchantBusinessFileIntentStore(url: path))
        await coordinator.load(.customer(try .init(51))); coordinator.prepare(mutation)
        let review = try XCTUnwrap(coordinator.confirmation); await coordinator.confirm(review)
        XCTAssertNotNil(coordinator.receipt); XCTAssertEqual(wire.requests.last?.url?.path, "/api/merchant/crm/customers/51/notes")
        let request = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
        let object = try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(request.httpBody)).object
        XCTAssertEqual(object, ["content": .string("Reviewed note"), "correctsNoteId": .null, "requestId": .string(review.requestID)])
        XCTAssertEqual(wire.writes, 1)
    }
    func testProductionOperatorInviteUsesFreshAssignableRole() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        wire.operatorAccess = true
        let mutation = MerchantBusinessMutation.inviteOperator(role: "MERCHANT_CHECKIN")
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, grantMutation: mutation, current: { c }), journal: MerchantBusinessFileIntentStore(url: path))
        await coordinator.load(.operators); coordinator.prepare(mutation)
        let review = try XCTUnwrap(coordinator.confirmation); await coordinator.confirm(review)
        XCTAssertNotNil(coordinator.receipt); XCTAssertEqual(wire.writes, 1)
        let request = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(request.url?.path, "/api/merchant/operators/invite"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
        let object = try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(request.httpBody)).object
        XCTAssertEqual(object, ["roleCode": .string("MERCHANT_CHECKIN"), "requestId": .string(review.requestID)])
        XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/merchant/operators/roles" }.count, 3)
    }
    func testOperatorRoleRevocationCannotBeBypassedByGrant() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        wire.operatorAccess = true
        let mutation = MerchantBusinessMutation.inviteOperator(role: "MERCHANT_CHECKIN")
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, grantMutation: mutation, current: { c }), journal: MerchantBusinessFileIntentStore(url: path))
        await coordinator.load(.operators); coordinator.prepare(mutation)
        let review = try XCTUnwrap(coordinator.confirmation); wire.assignableRole = false; await coordinator.confirm(review)
        XCTAssertNil(coordinator.receipt); XCTAssertEqual(wire.writes, 0)
    }
    func testProductionRejectsMemoryOnlyJournal() async throws {
        let c = try context(), wire = Wire()
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, current: { c }), journal: MerchantBusinessMemoryIntentStore())
        let pending = try await review(coordinator); await coordinator.confirm(pending)
        XCTAssertEqual(coordinator.failure, .disabled); XCTAssertEqual(wire.writes, 0)
    }
    func testFreshAllowedDecisionsRevocationStopsBeforeWrite() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, current: { c }), journal: MerchantBusinessFileIntentStore(url: path))
        let pending = try await review(coordinator); wire.canRespond = false; await coordinator.confirm(pending)
        XCTAssertEqual(wire.writes, 0); XCTAssertNil(coordinator.receipt)
    }
    func testSameEpochRoleChangeInvalidatesApprovalReview() async throws {
        var c = try context(); let wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, current: { c }), journal: MerchantBusinessFileIntentStore(url: path))
        let pending = try await review(coordinator); c = try context(role: "player"); await coordinator.confirm(pending)
        XCTAssertEqual(wire.writes, 0); XCTAssertNil(coordinator.receipt)
    }
    func testPostReservationDismissalCannotDispatch() async throws {
        let c = try context(), wire = Wire(), journal = ReentrantJournal()
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, current: { c }), journal: journal)
        let pending = try await review(coordinator); journal.onReserve = { coordinator.cancelConfirmation() }; await coordinator.confirm(pending)
        XCTAssertEqual(wire.writes, 0); XCTAssertEqual(try journal.intents().count, 1)
    }
    func testPostJournalFreshReadStillChecksCancellation() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let coordinator = MerchantBusinessCoordinator(reader: try self.reader(wire, current: { c }), journal: MerchantBusinessFileIntentStore(url: path))
        let pending = try await review(coordinator); wire.onThirdAccess = { coordinator.cancelConfirmation() }; await coordinator.confirm(pending)
        XCTAssertEqual(wire.writes, 0); XCTAssertEqual(try MerchantBusinessFileIntentStore(url: path).intents().count, 1)
    }
    func testCancellationAtFinalHTTPForwardingBarrierPreventsPOST() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        var onForward: (() -> Void)?
        let reader = try self.reader(wire, beforeForward: { onForward?(); await Task.yield() }, current: { c })
        let coordinator = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessFileIntentStore(url: path))
        onForward = { coordinator.cancelConfirmation() }
        let pending = try await review(coordinator); await coordinator.confirm(pending)
        XCTAssertEqual(wire.writes, 0); XCTAssertEqual(try MerchantBusinessFileIntentStore(url: path).intents().count, 1)
    }
    func testUnknownPersistsAndReopenedCoordinatorNeverRetries() async throws {
        let c = try context(), wire = Wire(), path = journalURL()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        wire.failWrite = true
        let reader = try self.reader(wire, current: { c }), coordinator = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessFileIntentStore(url: path))
        let pending = try await review(coordinator); await coordinator.confirm(pending)
        let reopened = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessFileIntentStore(url: path))
        await reopened.load(.refund(try .init(31))); reopened.prepare(try mutation())
        XCTAssertNil(reopened.confirmation); XCTAssertEqual(reopened.failure, .pending); XCTAssertEqual(wire.writes, 1)
    }
    @MainActor private final class ReentrantJournal: MerchantBusinessIntentStore {
        let isDurable = true; var rows: [MerchantBusinessIntent] = []; var onReserve: (() -> Void)?
        func intents() throws -> [MerchantBusinessIntent] { rows }
        func reserve(_ intent: MerchantBusinessIntent) throws { rows.append(intent); onReserve?() }
        func complete(_ intent: MerchantBusinessIntent) throws { rows.removeAll { $0 == intent } }
    }
    @MainActor private final class TestingWire: MerchantBusinessTestTransport {
        let wire = Wire()
        func send(_ request: URLRequest) async throws -> (Data, Int) { try await wire.send(request) }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []; var operatorAccess = false; var assignableRole = true; var canRespond = true; var failWrite = false; var accessCount = 0; var onThirdAccess: (() -> Void)?
        var writes: Int { requests.filter { ["/api/merchant/aftercare/respond", "/api/merchant/crm/customers/51/notes", "/api/merchant/operators/invite"].contains($0.url?.path ?? "") }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let payload: String
            switch request.url?.path {
            case "/api/merchant/access/me":
                accessCount += 1; if accessCount == 3 { onThirdAccess?() }
                if operatorAccess { payload = #"{"active":true,"merchant":{"id":11},"roleCode":"MERCHANT_OWNER","canManageOperators":true,"permissions":["merchant:operator:manage"]}"# }
                else { payload = #"{"active":true,"merchant":{"id":11},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:crm:read","merchant:crm:segment","merchant:aftercare:read","merchant:aftercare:respond","merchant:aftercare:decide"]}"# }
            case "/api/merchant/operators/list": payload = #"{"operators":[],"invites":[]}"#
            case "/api/merchant/operators/roles": payload = assignableRole ? #"[{"roleCode":"MERCHANT_CHECKIN","permissions":[]}]"# : "[]"
            case "/api/merchant/operators/invite": payload = #"{"invite":{"id":71,"version":0,"roleCode":"MERCHANT_CHECKIN","status":"PENDING","expiresAt":"2026-10-10"},"token":"test-invite-placeholder"}"#
            case "/api/merchant/crm/customers/51/detail": payload = #"{"summary":{"customerMemberId":51,"arrivedCount":0,"pendingCount":0,"refundedCount":0},"systemTags":[],"merchantTags":[],"timeline":[]}"#
            case "/api/merchant/crm/customers/51/notes": payload = #"{"id":61}"#
            case "/api/merchant/aftercare/detail":
                payload = "{\"refundId\":31,\"processing\":\"WAITING_PLATFORM_REVIEW\",\"merchantOpinion\":\"PENDING\",\"canRespond\":\(canRespond),\"allowedDecisions\":\(canRespond ? "[\"AGREE\",\"REJECT\"]" : "[]"),\"responses\":[],\"refunded\":false}"
            case "/api/merchant/aftercare/respond":
                if failWrite { throw URLError(.timedOut) }
                payload = #"{"id":41,"refundId":31,"decision":"AGREE","processing":"WAITING_PLATFORM_REVIEW","merchantOpinion":"AGREE","refunded":false}"#
            default: throw URLError(.unsupportedURL)
            }
            return (Data("{\"code\":200,\"data\":\(payload)}".utf8), 200)
        }
    }
}
