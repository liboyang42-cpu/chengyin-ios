import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CooperationFlowContractTests: XCTestCase {
    func testDistinctWireIDsAndScope() throws {
        XCTAssertEqual(try CoopFlowMutation.withdraw(topicID: 9).body(), .object(["topicId": .id(9)]))
        XCTAssertEqual(try CoopFlowMutation.confirm(registrationID: 3).body(), .object(["registrationId": .id(3)]))
        XCTAssertEqual(try CoopFlowMutation.decline(applyID: 7, scope: "MERCHANT").body()["scope"], .string("MERCHANT"))
    }
    func testReasonFieldsAndReviewComment() throws {
        XCTAssertEqual(try CoopFlowMutation.handle(inviteID: 2, action: .cancel, reason: "why").body()["message"], .string("why"))
        XCTAssertEqual(try CoopFlowMutation.handle(inviteID: 2, action: .reject, reason: "why").body()["handleReason"], .string("why"))
        let review = try CoopFlowMutation.review(topicID: 1, memberID: 2, rating: 4, comment: "review").body()
        XCTAssertEqual(review["comment"], .string("review")); XCTAssertEqual(review["content"], .null)
    }
    func testInviteIdentityAndCompensationDomains() throws {
        XCTAssertThrowsError(try CoopFlowInvitation(kind: .merchant, recipient: CoopFlowIdentity(.merchant, 3), topicID: 8, message: ""))
        let form = try CoopFlowInvitation(kind: .club, recipient: CoopFlowIdentity(.club, 3), topicID: 8, message: "", compensation: .fixed(20), originApplyID: 4, scope: "MERCHANT")
        let body = try CoopFlowMutation.invite(form).body()
        XCTAssertEqual(body["shareMode"], .id(2)); XCTAssertEqual(body["toType"], .string("club"))
        XCTAssertEqual(body["originApplyId"], .id(4))
    }
    func testTemplateIsCreateOnlyAndDecimalValidation() throws {
        XCTAssertThrowsError(try CoopFlowPerkTemplate(name: "x", type: 0, retailValue: Decimal(string: "1.001")!, unitCost: nil, quota: 1, validEnd: nil))
        let f = try CoopFlowPerkTemplate(name: "x", type: 0, retailValue: 10, unitCost: nil, quota: 1, validEnd: nil)
        let body = try CoopFlowMutation.createTemplate(f).body()
        XCTAssertEqual(body["id"], .null); XCTAssertEqual(body["unitCost"], .null)
    }
    func testOfferSourceModesAndServerOwnedStrip() throws {
        let context = try CoopFlowOfferContext(chapterID: 5, termsMode: .perk)
        XCTAssertThrowsError(try CoopFlowOfferDraft(context: context))
        let draft = try CoopFlowOfferDraft(context: context, templateID: 2, quota: 4)
        XCTAssertEqual(try draft.mutation.body()["quotaTotal"], .id(4))
        let raw = try CoopFlowMutation.enrollOffer(fields: ["chapterId": .id(5), "termsMode": .string("TRAFFIC"), "topicId": .id(99), "status": .id(1), "merchantId": .id(7)]).body()
        XCTAssertEqual(raw["topicId"], .null); XCTAssertEqual(raw["status"], .null); XCTAssertEqual(raw["merchantId"], .null)
    }
    func testSettlementUnknownIsNotZeroOrCredited() {
        let row = CoopFlowSettlement(source: .finance, record: .object(["topicId": .id(1), "settled": .string("1"), "myIncome": .null]))
        XCTAssertNil(row.amount.amount); XCTAssertEqual(row.status, "unknown"); XCTAssertEqual(row.amount.currency, "CNY")
        let unknown = CoopFlowSettlement(source: .mybiz, record: .object(["id": .id(1), "status": .id(8)]))
        XCTAssertEqual(unknown.status, "unknown")
    }
    func testNearbyInvitationUsesMemberAndPhoneGate() {
        let row = CoopFlowNearbyPartner(source: .object(["id": .id(3), "memberId": .id(8), "canInvite": .bool(true), "canCall": .bool(false), "phone": .string("not-dialable")]))
        XCTAssertEqual(row.merchantID, 3); XCTAssertEqual(row.memberID, 8); XCTAssertTrue(row.canInvite); XCTAssertNil(row.dialablePhone)
    }
    func testLegacyFrozenUnknownHaveNoActions() {
        for row: CoopFlowJSON in [.object(["inviteType": .id(2), "status": .id(0)]), .object(["termsFrozen": .bool(true), "status": .id(1)]), .object(["status": .id(100)])] {
            XCTAssertTrue(CoopFlowContractState(invite: row).actions(isFrom: true, isTo: true).isEmpty)
        }
    }
    func testRefundReceiptRequiresAllSourceEvidence() throws {
        XCTAssertThrowsError(try CoopFlowFinancialContract.refundReceipt(.object(["code": .id(200), "msg": .string("ok")])))
        XCTAssertEqual(CoopFlowFinancialContract.paymentStatus(.object(["paymentStatus": .string("new") ])), "unknown")
        XCTAssertEqual(try CoopFlowFinancialContract.refundReceipt(.object(["code": .id(200), "msg": .string("source text"), "data": .object(["refundState": .string("PENDING")])])), "source text")
    }
}
private final class CoopFlowFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = Data("{\"code\":200,\"data\":[]}".utf8)
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (response, 200) }
}
@MainActor final class CooperationFlowServiceTests: XCTestCase {
    func testReadPathsShapesAndNearbyMultipart() async throws {
        let transport = CoopFlowFakeTransport()
        let service = CoopFlowService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
        let session = try CoopFlowSession(accountID: 2, epoch: 1, token: "fixture-token")
        _ = try await service.read(.nearby(longitude: 121, latitude: 31), session: session)
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        XCTAssertTrue(String(data: transport.requests[0].httpBody!, encoding: .utf8)!.contains("name=\"radius\""))
        transport.response = Data("{\"code\":200,\"data\":{\"rows\":[]}}".utf8)
        do { _ = try await service.read(.finance, session: session); XCTFail("Wrong wrapper accepted") } catch { XCTAssertEqual(error as? CoopFlowFailure, .malformed) }
    }
    func testDormantAdapterMakesNoRequests() async throws {
        let transport = CoopFlowFakeTransport()
        let service = CoopFlowService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
        let executor = CoopFlowDormantExecutor(service: service)
        XCTAssertFalse(executor.permitsDispatch(.apply(topicID: 1)))
        do { _ = try await executor.execute(.apply(topicID: 1), session: CoopFlowSession(accountID: 1, epoch: 0, token: "fixture")); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
@MainActor private final class CoopFlowFakeEvidence: CoopFlowEvidenceReading {
    var value = CoopFlowEvidence(baseline: .object(["state": .string("open")]), permitted: true)
    var hook: (() -> Void)?
    func freshEvidence(for operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowEvidence { hook?(); return value }
}
@MainActor private final class CoopFlowFakeExecutor: CoopFlowExecuting {
    var calls = 0
    var fail = false
    func permitsDispatch(_ operation: CoopFlowMutation) -> Bool { true }
    func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON {
        calls += 1; if fail { throw URLError(.timedOut) }; return .object([:])
    }
}
@MainActor final class CooperationFlowSafetyTests: XCTestCase {
    private func locks() -> CoopFlowFileLocks { CoopFlowFileLocks(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("locks.json")) }
    func testDisabledPermissionAndConflictPreventDispatch() async throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        let evidence = CoopFlowFakeEvidence(), executor = CoopFlowFakeExecutor()
        let disabled = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: locks())
        let review = try await disabled.prepare(.apply(topicID: 1))
        do { _ = try await disabled.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
        let enabled = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: locks(), enabled: true)
        let accepted = try await enabled.prepare(.apply(topicID: 1))
        evidence.value = CoopFlowEvidence(baseline: .object(["state": .string("taken")]), permitted: true)
        do { _ = try await enabled.confirm(accepted); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .conflict) }
        evidence.value = CoopFlowEvidence(baseline: .null, permitted: false)
        do { _ = try await enabled.prepare(.apply(topicID: 1)); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .permission) }
        XCTAssertEqual(executor.calls, 0)
    }
    func testAccountSwitchDropsEvidence() async throws {
        var session: CoopFlowSession? = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        let evidence = CoopFlowFakeEvidence(), executor = CoopFlowFakeExecutor()
        let c = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: locks(), enabled: true)
        evidence.hook = { session = nil }
        do { _ = try await c.prepare(.apply(topicID: 1)); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(executor.calls, 0)
    }
    func testAmbiguitySurvivesNewCoordinatorAndEpoch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("locks.json")
        var session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        let evidence = CoopFlowFakeEvidence(), executor = CoopFlowFakeExecutor(); executor.fail = true
        let c = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: CoopFlowFileLocks(url: url), enabled: true)
        let review = try await c.prepare(.apply(topicID: 1))
        do { _ = try await c.confirm(review); XCTFail() } catch {}
        session = try CoopFlowSession(accountID: 1, epoch: 2, token: "new-fixture")
        let next = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: CoopFlowFileLocks(url: url), enabled: true)
        do { _ = try await next.prepare(.withdraw(topicID: 1)); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .ambiguous) }
        XCTAssertEqual(executor.calls, 1)
    }
    func testTokenReplacementWithoutEpochStillInvalidatesReview() async throws {
        var session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture-old")
        let executor = CoopFlowFakeExecutor()
        let coordinator = CoopFlowCoordinator(current: { session }, evidence: CoopFlowFakeEvidence(), executor: executor, locks: locks(), enabled: true)
        let review = try await coordinator.prepare(.apply(topicID: 1))
        session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture-new")
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(executor.calls, 0)
    }
    func testExpiredReviewDoesNotDispatch() async throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        var now = Date(timeIntervalSince1970: 1000)
        let executor = CoopFlowFakeExecutor()
        let coordinator = CoopFlowCoordinator(current: { session }, evidence: CoopFlowFakeEvidence(), executor: executor, locks: locks(), enabled: true, now: { now })
        let review = try await coordinator.prepare(.apply(topicID: 1)); now.addTimeInterval(121)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(executor.calls, 0)
    }
    func testCorruptDurableLockStoreFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not-json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoopFlowFileLocks(url: url)
        XCTAssertThrowsError(try store.acquire("1:pool-topic-2")) { XCTAssertEqual($0 as? CoopFlowFailure, .storage) }
    }
    func testSuccessConsumesReview() async throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        let executor = CoopFlowFakeExecutor()
        let c = CoopFlowCoordinator(current: { session }, evidence: CoopFlowFakeEvidence(), executor: executor, locks: locks(), enabled: true)
        let review = try await c.prepare(.apply(topicID: 1))
        _ = try await c.confirm(review)
        do { _ = try await c.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(executor.calls, 1)
    }
}
