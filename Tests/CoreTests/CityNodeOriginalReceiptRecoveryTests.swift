import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityNodeOriginalReceiptRecoveryTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private let code = "v1.2.citynode_9.0.fixture.signature"
    private func context() throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "merchant", session: try .init(accountID: 7, epoch: 1, namespace: "receipt-fixture", token: "synthetic-token"))
    }
    private func session() throws -> MerchantBusinessSession { try .init(accountID: 7, epoch: 1, token: "synthetic-token") }
    private func positive(member: Int = 9) -> String {
        "{\"code\":200,\"msg\":\"核销成功,券已发放玩家\",\"data\":{\"poiId\":2,\"memberId\":\(member),\"couponId\":3,\"couponGranted\":true}}"
    }
    private func reader(_ wire: Wire, _ grant: CityNodeRedemptionReceiptApproval?, _ context: RuntimeDependencyContext) -> CityNodeRedemptionReceiptReader {
        .init(approval: grant, transport: wire, context: { context }, selected: { grant })
    }
    private func intent(legacy: Bool = false) throws -> MerchantBusinessIntent {
        .init(scope: .init(realm: base.absoluteString, accountID: 7, epoch: 1), merchantID: 19,
              target: legacy ? "redemption" : try XCTUnwrap(CityNodeRedemptionTarget(code: code)).journalTarget, requestID: "local-original")
    }
    func testOnlyExactOriginalSuccessIsTerminal() throws {
        let target = try XCTUnwrap(CityNodeRedemptionTarget(code: code))
        for raw in [#"{"code":200}"#, #"{"code":200,"msg":"核销成功"}"#, positive(member: 10), #"{"code":400,"msg":"拒绝"}"#] {
            let body = try XCTUnwrap(JSONDecoder().decode(MerchantBusinessValue.self, from: Data(raw.utf8)).object)
            XCTAssertTrue(try CityNodeRedemptionResult(body: body, target: target).isUnknown)
        }
        let body = try XCTUnwrap(JSONDecoder().decode(MerchantBusinessValue.self, from: Data(positive().utf8)).object)
        XCTAssertTrue(try CityNodeRedemptionResult(body: body, target: target).redeemed)
        XCTAssertFalse(CityNodeRedemptionCode.acceptsPledgeRedeem("api/coupon/verification"))
    }
    func testReaderNilDoesNotSendAndCannotBecomeRedeem() async throws {
        let wire = Wire(), context = try context()
        let reader = reader(wire, nil, context)
        do { _ = try await reader.read(code, session: session(), merchantID: 19, realm: base.absoluteString); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testReceiptRefusalsAndMissingAuditRemainUnknown() async throws {
        let context = try context(), wire = Wire()
        let grant = try CityNodeRedemptionReceiptApproval(context: context, merchantID: 19, expiresAt: Date().addingTimeInterval(600))
        let reader = reader(wire, grant, context)
        for raw in [#"{"code":520,"msg":"待确认"}"#, #"{"code":500,"msg":"玩家未到店打卡,或该券已核销"}"#, #"{"code":200}"#] {
            wire.body = raw
            let result = try await reader.read(code, session: session(), merchantID: 19, realm: base.absoluteString)
            XCTAssertTrue(result.isUnknown)
        }
        XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path == "/native/api/verify/citynode/receipt" && $0.httpMethod == "POST" && !$0.httpShouldHandleCookies })
    }
    func testRecoverySettlesOriginalPendingWithoutRedeem() async throws {
        let context = try context(), session = try session(), wire = Wire(), journal = Journal()
        journal.records = [try intent()]; wire.body = positive()
        let grant = try CityNodeRedemptionReceiptApproval(context: context, merchantID: 19, expiresAt: Date().addingTimeInterval(600))
        let service = MerchantBusinessService(configuration: try .init(baseURL: base), readTransport: wire)
        let coordinator = CityNodeRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
        await coordinator.recover(code, reader: reader(wire, grant, context))
        XCTAssertTrue(coordinator.result?.redeemed == true); XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me", "receipt"])
    }
    func testAbsentReceiptKeepsOriginalIdentityAndLegacyDoesNotRead() async throws {
        for legacy in [false, true] {
            let context = try context(), session = try session(), wire = Wire(), journal = Journal()
            let pending = try intent(legacy: legacy); journal.records = [pending]
            let grant = try CityNodeRedemptionReceiptApproval(context: context, merchantID: 19, expiresAt: Date().addingTimeInterval(600))
            let service = MerchantBusinessService(configuration: try .init(baseURL: base), readTransport: wire)
            let coordinator = CityNodeRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
            await coordinator.recover(code, reader: reader(wire, grant, context))
            XCTAssertEqual(journal.records, [pending]); XCTAssertEqual(wire.requests.count, legacy ? 1 : 2)
        }
    }
    func testLateRevocationCannotSettlePositiveReceipt() async throws {
        let context = try context(), session = try session(), wire = Wire(), journal = Journal()
        let pending = try intent(); journal.records = [pending]; wire.body = positive()
        let grant = try CityNodeRedemptionReceiptApproval(context: context, merchantID: 19, expiresAt: Date().addingTimeInterval(600))
        wire.receiptCallback = { grant.revoke() }
        let service = MerchantBusinessService(configuration: try .init(baseURL: base), readTransport: wire)
        let coordinator = CityNodeRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
        await coordinator.recover(code, reader: reader(wire, grant, context))
        XCTAssertEqual(journal.records, [pending]); XCTAssertNotEqual(coordinator.result?.redeemed, true)
    }
    func testLocalClearFailureKeepsKnownReceiptAndLock() async throws {
        let context = try context(), session = try session(), wire = Wire(), journal = Journal()
        journal.records = [try intent()]; journal.failClear = true; wire.body = positive()
        let grant = try CityNodeRedemptionReceiptApproval(context: context, merchantID: 19, expiresAt: Date().addingTimeInterval(600))
        let service = MerchantBusinessService(configuration: try .init(baseURL: base), readTransport: wire)
        let coordinator = CityNodeRedemptionCoordinator(service: service, journal: journal, currentSession: { session })
        await coordinator.recover(code, reader: reader(wire, grant, context))
        XCTAssertTrue(coordinator.result?.redeemed == true); XCTAssertEqual(journal.records.count, 1)
    }
    private final class Wire: HTTPTransport {
        var body = #"{"code":520,"msg":"待确认"}"#; var requests: [URLRequest] = []; var receiptCallback: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.lastPathComponent == "me" {
                return (Data(#"{"code":200,"data":{"active":true,"merchant":{"id":19},"roleCode":"MERCHANT_CHECKIN","permissions":["merchant:verify"]}}"#.utf8), 200)
            }
            receiptCallback?(); return (Data(body.utf8), 200)
        }
    }
    private final class Journal: MerchantBusinessIntentStore {
        var records: [MerchantBusinessIntent] = []; var failClear = false
        func intents() throws -> [MerchantBusinessIntent] { records }
        func reserve(_ intent: MerchantBusinessIntent) throws { records.append(intent) }
        func complete(_ intent: MerchantBusinessIntent) throws {
            if failClear { throw MerchantBusinessFailure.journal }
            records.removeAll { $0 == intent }
        }
    }
}
