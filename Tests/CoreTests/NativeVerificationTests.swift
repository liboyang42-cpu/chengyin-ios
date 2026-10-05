import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class NativeVerificationTests: XCTestCase {
    private func system(transport: NativeVerificationTestTransport, enabled: Bool = true, now: @escaping () -> Date = Date.init) throws -> (NativeVerificationWorkflow, MerchantBusinessMemoryIntentStore) {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://verification.test")!)
        let session = try MerchantBusinessSession(accountID: 9, epoch: 1, token: "synthetic-token")
        let api = MerchantBusinessService(configuration: configuration, readTransport: transport, testingMutationTransport: enabled ? transport : nil)
        let journal = MerchantBusinessMemoryIntentStore()
        let reader = MerchantBusinessSessionReader(service: api, currentSession: { session })
        let redemption = MerchantRedemptionCoordinator(service: api, journal: journal, currentSession: { session })
        return (.init(reader: reader, journal: journal, redemption: redemption, now: now), journal)
    }
    func testSignedCouponRoutesWholeCodeAndNeverAuthenticatesLocally() throws {
        let context = try MerchantRedemptionContext.parse("cq1.synthetic.example.signature")
        XCTAssertEqual(context.kind, .coupon)
        XCTAssertEqual(context.request().body, .form(["code":"cq1.synthetic.example.signature"]))
        XCTAssertThrowsError(try MerchantRedemptionContext.parse("cq1.missing.segment"))
        XCTAssertThrowsError(try MerchantRedemptionContext.parse("v1.fixture.citynode_synthetic.signature"))
    }
    func testProductionDisabledConfirmStoresNoIntentAndSendsNothing() async throws {
        let transport = NativeVerificationTestTransport(); let (flow, journal) = try system(transport: transport, enabled: false)
        await flow.activate(); await flow.prepare(raw: "cq1.synthetic.example.signature")
        let review = try XCTUnwrap(flow.review)
        XCTAssertFalse(flow.canConfirm); await flow.confirm(review)
        XCTAssertEqual(flow.phase, .disabled); XCTAssertEqual(transport.mutations.count, 0); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testCancellationAndRepeatedConfirmationDoNotDuplicateDispatch() async throws {
        let transport = NativeVerificationTestTransport(); let (flow, _) = try system(transport: transport)
        await flow.activate(); await flow.prepare(raw: "v1.synthetic.activity.signature"); flow.cancelReview()
        XCTAssertNil(flow.review); XCTAssertEqual(transport.mutations.count, 0)
        await flow.prepare(raw: "v1.synthetic.activity.signature")
        let review = try XCTUnwrap(flow.review); await flow.confirm(review); await flow.confirm(review)
        XCTAssertEqual(transport.mutations.count, 1); XCTAssertEqual(flow.result?.outcome, .redeemed)
        XCTAssertFalse(flow.needsReadback)
    }
    func testFrozenReviewRejectsChangedMerchantBeforeMutation() async throws {
        let transport = NativeVerificationTestTransport(); let (flow, journal) = try system(transport: transport)
        await flow.activate(); await flow.prepare(raw: "v1.synthetic.topic.signature")
        let review = try XCTUnwrap(flow.review); transport.merchantID = 611; await flow.confirm(review)
        XCTAssertEqual(transport.mutations.count, 0); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testExpiredReviewCannotDispatch() async throws {
        let transport = NativeVerificationTestTransport(); var now = Date(timeIntervalSince1970: 100)
        let (flow, _) = try system(transport: transport, now: { now })
        await flow.activate(); await flow.prepare(raw: "v1.synthetic.topic.signature")
        let review = try XCTUnwrap(flow.review); now = now.addingTimeInterval(61); await flow.confirm(review)
        XCTAssertEqual(transport.mutations.count, 0); XCTAssertEqual(flow.issueKey, "verification.reviewExpired")
    }
    func testUnknownOutcomeLocksAcrossLeavingAndReadOnlyAccessRefresh() async throws {
        let transport = NativeVerificationTestTransport(); transport.unknown = true
        let (flow, journal) = try system(transport: transport)
        await flow.activate(); await flow.prepare(raw: "v1.synthetic.activity.signature")
        await flow.confirm(try XCTUnwrap(flow.review)); XCTAssertTrue(flow.needsReadback)
        let intents = try journal.intents(); XCTAssertEqual(intents.count, 1); XCTAssertEqual(intents[0].target, "redemption")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(intents), as: UTF8.self).contains("signature"))
        flow.deactivate(); await flow.activate(); XCTAssertTrue(flow.needsReadback); XCTAssertFalse(flow.canCapture)
        await flow.prepare(raw: "cq1.second.example.signature"); XCTAssertEqual(transport.mutations.count, 1)
    }
    func testLegacyStationChoiceUsesDedicatedRegistrationMerchantID() async throws {
        let transport = NativeVerificationTestTransport(); transport.choice = true
        let (flow, _) = try system(transport: transport)
        await flow.activate(); await flow.prepare(raw: #"{"type":"topic","code":"synthetic"}"#)
        await flow.confirm(try XCTUnwrap(flow.review))
        let choice = try XCTUnwrap(flow.result?.choices.first); XCTAssertEqual(choice.target, .stationRegistration(try .init(81)))
        flow.prepareChoice(choice.target); flow.cancelReview(); XCTAssertEqual(flow.phase, .choosing)
        flow.prepareChoice(choice.target); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(transport.mutations.count, 2)
        let request = transport.mutations[1], body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertEqual(request.url?.path, "/api/registration/scan_qr_code_station")
        XCTAssertTrue(body.contains("name=\"registrationMerchantId\"\r\n\r\n81\r\n")); XCTAssertFalse(body.contains("999"))
    }
    func testJournalCallbackCannotDispatchWithReplacedSession() async throws {
        let transport = NativeVerificationTestTransport()
        let api = MerchantBusinessService(configuration: try APIConfiguration(baseURL: URL(string: "https://verification.test")!),
            readTransport: transport, testingMutationTransport: transport)
        let first = try MerchantBusinessSession(accountID: 9, epoch: 1, token: "synthetic-old")
        let replacement = try MerchantBusinessSession(accountID: 9, epoch: 2, token: "synthetic-new")
        var current = first
        let journal = VerificationReserveHookJournal()
        journal.onReserve = { current = replacement }
        let coordinator = MerchantRedemptionCoordinator(service: api, journal: journal, currentSession: { current })
        do { try await coordinator.begin(MerchantRedemptionContext.parse("v1.synthetic.activity.signature"), expectedMerchantID: 610); XCTFail("Expected stale pre-dispatch fence") }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .unknown) }
        XCTAssertEqual(transport.mutations.count, 0)
        XCTAssertEqual(try journal.intents().count, 1)
    }
    func testDismissedInflightResultCannotResurrectChoiceAndKeepsUnknownLock() async throws {
        let transport = NativeVerificationTestTransport(); transport.suspend = true
        let (flow, journal) = try system(transport: transport)
        await flow.activate(); await flow.prepare(raw: "v1.synthetic.activity.signature")
        let review = try XCTUnwrap(flow.review)
        let task = Task { await flow.confirm(review) }
        await transport.waitForMutation()
        flow.deactivate(); transport.finish(); await task.value
        XCTAssertNil(flow.result); XCTAssertNil(flow.review); XCTAssertEqual(try journal.intents().count, 1)
        await flow.activate(); XCTAssertTrue(flow.needsReadback)
    }
}
@MainActor private final class NativeVerificationTestTransport: MerchantBusinessTestTransport {
    var merchantID = 610
    var unknown = false
    var choice = false
    var suspend = false
    private(set) var mutations: [URLRequest] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.path == "/api/merchant/access/me" {
            let raw = MerchantBusinessSyntheticFixtures.access.replacingOccurrences(of: "\"id\":610", with: "\"id\":\(merchantID)")
            return (Data(("{\"code\":200,\"data\":" + raw + "}").utf8), 200)
        }
        mutations.append(request)
        if suspend { await withCheckedContinuation { continuation = $0; waiter?.resume(); waiter = nil } }
        if unknown { throw URLError(.timedOut) }
        if choice, mutations.count == 1 {
            return (Data(#"{"code":500,"data":{"needStationChoice":true,"stations":[{"id":999,"registrationMerchantId":81,"name":"Synthetic station"}]}}"#.utf8), 200)
        }
        return (Data(#"{"code":200,"msg":"Synthetic acknowledged","data":{}}"#.utf8), 200)
    }
    func waitForMutation() async { if continuation != nil { return }; await withCheckedContinuation { waiter = $0 } }
    func finish() { continuation?.resume(); continuation = nil }
}

@MainActor private final class VerificationReserveHookJournal: MerchantBusinessIntentStore {
    private let storage = MerchantBusinessMemoryIntentStore()
    var onReserve: (() -> Void)?
    func intents() throws -> [MerchantBusinessIntent] { try storage.intents() }
    func reserve(_ intent: MerchantBusinessIntent) throws { try storage.reserve(intent); onReserve?() }
    func complete(_ intent: MerchantBusinessIntent) throws { try storage.complete(intent) }
}
