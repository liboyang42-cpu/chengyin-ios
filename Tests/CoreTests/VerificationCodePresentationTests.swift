import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class VerificationCodePresentationTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "PLAYER", token: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.com/native/")!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: "fixture", token: token))
    }
    private func receipt(kind: VerificationCodeKind = .ticket, id: Int = 31, account: Int = 7, expiry: Int64 = 1_300_000) throws -> VerificationCodeReceipt {
        try JSONDecoder().decode(VerificationCodeReceipt.self, from: Data(payload(kind: kind, id: id, account: account, expiry: expiry).utf8))
    }
    private func payload(kind: VerificationCodeKind = .ticket, id: Int = 31, account: Int = 7, expiry: Int64 = 1_300_000) -> String {
        let type = kind == .ticket ? "topic" : "citynode_\(account)"
        return "{\"code\":\"v1.\(id).\(type).\(expiry).9.\(String(repeating: "A", count: 43))\",\"expiresAt\":\(expiry),\"ttlMs\":300000,\"type\":\"\(type)\",\"poiId\":\(id)}"
    }
    private func detail(status: Int = 2, verified: Int = 0) throws -> OrderLifecycleDetail {
        try JSONDecoder().decode(OrderLifecycleDetail.self, from: Data("{\"id\":31,\"registrationStatus\":\(status),\"verificationStatus\":\(verified),\"purchaseKind\":3,\"entitlements\":[{\"id\":1,\"status\":0}]}".utf8))
    }
    private func approval(_ context: RuntimeDependencyContext, kinds: Set<VerificationCodeKind> = [.ticket, .cityVoucher], paths: Set<String> = ["api/verify/dyncode/issue", "api/registration/info", "api/verify/citynode/issue"]) throws -> VerificationCodeApproval {
        .init(market: .china, endpoints: try .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, paths: paths), kinds: kinds)
    }
    func testReceiptBindsExactServerCodeTargetOwnerAndExpiry() throws {
        let date = Date(timeIntervalSince1970: 1000), target = VerificationCodeTarget(kind: .cityVoucher, id: 31)
        let value = try receipt(kind: .cityVoucher)
        XCTAssertTrue(try value.validatedCode(target: target, accountID: 7, requestedAt: date, now: date).hasPrefix("v1.31.citynode_7."))
        XCTAssertThrowsError(try value.validatedCode(target: target, accountID: 8, requestedAt: date, now: date))
        XCTAssertThrowsError(try value.validatedCode(target: .init(kind: .cityVoucher, id: 32), accountID: 7, requestedAt: date, now: date))
        XCTAssertThrowsError(try value.validatedCode(target: .init(kind: .ticket, id: 31), accountID: 7, requestedAt: date, now: date))
    }
    func testMissingAbsoluteExpiryAndControlCharactersCannotRender() {
        for json in [#"{"code":"v1.31.topic.1300000.9.A","ttlMs":300000}"#,
                     #"{"code":"line\nbreak","expiresAt":1300000,"ttlMs":300000}"#,
                     #"{"code":"valid-looking","expiresAt":1300000,"ttlMs":300001}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(VerificationCodeReceipt.self, from: Data(json.utf8)))
        }
    }
    func testExpiryMustMatchSignedPayloadAndCannotBeReplacedWithTTL() throws {
        let raw = payload().replacingOccurrences(of: "\"expiresAt\":1300000", with: "\"expiresAt\":1300001")
        let value = try JSONDecoder().decode(VerificationCodeReceipt.self, from: Data(raw.utf8)), target = VerificationCodeTarget(kind: .ticket, id: 31)
        XCTAssertThrowsError(try value.validatedCode(target: target, accountID: 7, requestedAt: Date(timeIntervalSince1970: 1000), now: Date(timeIntervalSince1970: 1000)))
        let expired = try receipt(expiry: 900_000)
        XCTAssertThrowsError(try expired.validatedCode(target: target, accountID: 7, requestedAt: Date(timeIntervalSince1970: 1000), now: Date(timeIntervalSince1970: 1000)))
    }
    func testDefaultServiceCannotReachTransport() async throws {
        let context = try context(), recorder = VerificationCodeTestTransport()
        let service = VerificationCodeHTTPService(configuration: try .init(baseURL: context.baseURL), kind: .ticket, transport: recorder, current: { context })
        XCTAssertFalse(service.enabled)
        do { _ = try await service.issue(.init(kind: .ticket, id: 31), context: context); XCTFail() } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testApprovalRequiresIndependentKindAndReadbackPath() throws {
        let context = try context()
        XCTAssertFalse(try approval(context, kinds: []).allows(.ticket, context: context))
        XCTAssertFalse(try approval(context, paths: ["api/verify/dyncode/issue"]).allows(.ticket, context: context))
        XCTAssertTrue(try approval(context).allows(.cityVoucher, context: context))
        XCTAssertFalse(try approval(context).allows(.ticket, context: self.context(account: 8)))
    }
    func testExactIssueFormsAndNoRedemptionRoute() async throws {
        let context = try context(), recorder = VerificationCodeTestTransport()
        for kind in [VerificationCodeKind.ticket, .cityVoucher] {
            recorder.body = "{\"code\":200,\"data\":\(payload(kind: kind))}"
            let service = VerificationCodeHTTPService(configuration: try .init(baseURL: context.baseURL), approval: try approval(context), kind: kind, transport: recorder, current: { context })
            _ = try await service.issue(.init(kind: kind, id: 31), context: context)
            let request = try XCTUnwrap(recorder.requests.last)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, kind == .ticket ? "/native/api/verify/dyncode/issue" : "/native/api/verify/citynode/issue")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"\(kind == .ticket ? "registrationId" : "poiId")\"\r\n\r\n31"))
            XCTAssertFalse(body.contains("amount")); XCTAssertFalse(body.contains("memberId"))
        }
    }
    func testRoleTokenEpochChangesDisableCapturedServiceBeforeNetwork() async throws {
        let initial = try context(); var current: RuntimeDependencyContext? = initial
        let recorder = VerificationCodeTestTransport()
        let service = VerificationCodeHTTPService(configuration: try .init(baseURL: initial.baseURL), approval: try approval(initial), kind: .ticket, transport: recorder, current: { current })
        for next in [try context(role: "MERCHANT"), try context(token: "replacement"), try context(epoch: 2)] {
            current = next; XCTAssertFalse(service.enabled)
            do { _ = try await service.issue(.init(kind: .ticket, id: 31), context: initial); XCTFail() } catch {}
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testTicketCanIssueAfterFirstChapterWasVerified() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail(verified: 1))
        let model = VerificationCodeCoordinator(target: .init(kind: .ticket, id: 31), service: fixture, current: { context }, now: { Date(timeIntervalSince1970: 1000) })
        await model.present()
        XCTAssertEqual(fixture.issues, 1); XCTAssertEqual(model.phase, .ready); XCTAssertNotNil(model.displayCode)
        XCTAssertEqual(fixture.orderReads, 1)
    }
    func testTicketExpiryClearsAndRequiresManualRetry() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail())
        var now = Date(timeIntervalSince1970: 1000)
        let model = VerificationCodeCoordinator(target: .init(kind: .ticket, id: 31), service: fixture, current: { context }, now: { now })
        await model.present(); XCTAssertEqual(model.remainingSeconds, 300)
        now = Date(timeIntervalSince1970: 1300); XCTAssertNil(model.displayCode)
        await model.tick(); XCTAssertEqual(model.phase, .expired); XCTAssertEqual(fixture.issues, 1)
        fixture.receipt = try receipt(expiry: 1_600_000); await model.present()
        XCTAssertEqual(fixture.issues, 2); XCTAssertEqual(model.phase, .ready)
    }
    func testCityExpiryReissuesButFailureDoesNotLoop() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(kind: .cityVoucher), detail: try detail())
        var now = Date(timeIntervalSince1970: 1000)
        let model = VerificationCodeCoordinator(target: .init(kind: .cityVoucher, id: 31), service: fixture, current: { context }, now: { now })
        await model.present(); fixture.receipt = try receipt(kind: .cityVoucher, expiry: 1_600_000)
        now = Date(timeIntervalSince1970: 1300); await model.tick()
        XCTAssertEqual(fixture.issues, 2); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(fixture.orderReads, 0)
        fixture.failure = VerificationCodeFailure.failed; now = Date(timeIntervalSince1970: 1600); await model.tick()
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.displayCode)
        for _ in 0..<5 { await model.tick() }
        XCTAssertEqual(fixture.issues, 3)
    }
    func testPauseAndDismissErasePayloadAndNeverAutoResume() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail())
        let model = VerificationCodeCoordinator(target: .init(kind: .ticket, id: 31), service: fixture, current: { context }, now: { Date(timeIntervalSince1970: 1000) })
        await model.present(); model.pause(); await model.tick()
        XCTAssertNil(model.displayCode); XCTAssertNil(model.readback); XCTAssertEqual(model.remainingSeconds, 0); XCTAssertEqual(fixture.issues, 1)
        model.invalidate(); XCTAssertEqual(model.phase, .review)
    }
    func testAccountChangeAndClockRollbackHideBeforeNextTick() async throws {
        let first = try context(); var current: RuntimeDependencyContext? = first
        let fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail())
        var now = Date(timeIntervalSince1970: 1000)
        let model = VerificationCodeCoordinator(target: .init(kind: .ticket, id: 31), service: fixture, current: { current }, now: { now })
        await model.present(); now = Date(timeIntervalSince1970: 999); XCTAssertNil(model.displayCode); await model.tick(); XCTAssertEqual(model.phase, .expired)
        now = Date(timeIntervalSince1970: 1000); await model.present(); current = try context(account: 8)
        XCTAssertNil(model.displayCode); await model.tick(); XCTAssertEqual(model.phase, .stale); XCTAssertNil(model.readback)
    }
    func testRepeatedTapAndLateCallbackAfterPauseCannotResurrectCode() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail())
        fixture.holdIssue = true
        let model = VerificationCodeCoordinator(target: .init(kind: .cityVoucher, id: 31), service: fixture, current: { context }, now: { Date(timeIntervalSince1970: 1000) })
        let task = Task { await model.present() }
        for _ in 0..<20 { if fixture.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(fixture.pending)
        await model.present(); XCTAssertEqual(fixture.issues, 1)
        model.pause(); pending.resume(returning: try receipt(kind: .cityVoucher)); await task.value
        XCTAssertNil(model.displayCode); XCTAssertEqual(model.phase, .paused)
    }
    func testReadbackUsesRegistrationAndDoesNotInferFirstScanAsCompletion() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail())
        let model = VerificationCodeCoordinator(target: .init(kind: .ticket, id: 31), service: fixture, current: { context }, now: { Date(timeIntervalSince1970: 1000) })
        await model.present(); fixture.detail = try detail(verified: 1); await model.checkOrder()
        XCTAssertNotNil(model.displayCode); XCTAssertEqual(fixture.issues, 1)
        fixture.detail = try detail(status: 3); await model.checkOrder()
        XCTAssertNil(model.displayCode); XCTAssertEqual(model.phase, .unavailable); XCTAssertEqual(fixture.orderReads, 3)
    }
    func testUnauthorizedClearsAndNotifiesOnlyCurrentSession() async throws {
        let context = try context(), fixture = VerificationCodeTestService(receipt: try receipt(), detail: try detail())
        var expired: RuntimeDependencyContext?
        let model = VerificationCodeCoordinator(target: .init(kind: .cityVoucher, id: 31), service: fixture, current: { context }, now: { Date(timeIntervalSince1970: 1000) }, onUnauthorized: { expired = $0 })
        fixture.failure = VerificationCodeFailure.login; await model.present()
        XCTAssertEqual(expired, context); XCTAssertEqual(model.phase, .login); XCTAssertNil(model.displayCode)
    }
}
@MainActor private final class VerificationCodeTestService: VerificationCodeServing {
    var enabled = true
    var receipt: VerificationCodeReceipt
    var detail: OrderLifecycleDetail
    var issues = 0; var orderReads = 0
    var failure: Error?
    var holdIssue = false
    var pending: CheckedContinuation<VerificationCodeReceipt, Error>?
    init(receipt: VerificationCodeReceipt, detail: OrderLifecycleDetail) { self.receipt = receipt; self.detail = detail }
    func issue(_ target: VerificationCodeTarget, context: RuntimeDependencyContext) async throws -> VerificationCodeReceipt {
        issues += 1
        if let failure { throw failure }
        if holdIssue { return try await withCheckedThrowingContinuation { pending = $0 } }
        return receipt
    }
    func order(id: Int, context: RuntimeDependencyContext) async throws -> OrderLifecycleDetail { orderReads += 1; return detail }
}
@MainActor private final class VerificationCodeTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var body = "{}"
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), 200) }
}
