import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class BusinessPresentationApprovalTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "OWNER", token: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.com/native/")!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: "fixture", token: token))
    }
    private func endpoints(_ context: RuntimeDependencyContext, paths: Set<String>) throws -> OperationEndpointApproval {
        try .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, paths: paths)
    }
    private func couponApproval(_ context: RuntimeDependencyContext, origins: Set<String> = []) throws -> CouponCodeApproval {
        .init(market: .china, endpoints: try endpoints(context, paths: ["api/coupon/qr-token", "api/coupon/status"]), imageOrigins: origins)
    }
    private func couponSession(_ context: RuntimeDependencyContext) throws -> CouponCodeSession {
        try .init(accountID: context.session.accountID, epoch: context.session.epoch, namespace: context.session.namespace, role: context.role, token: context.session.token)
    }
    private func refundApproval(_ context: RuntimeDependencyContext) throws -> ClubOwnerRefundApproval {
        .init(market: .china, endpoints: try endpoints(context, paths: ["api/registration/cancel-by-owner", "api/club/access/me", "api/club/crm/checkin/detail"]))
    }
    private func fallback(_ context: RuntimeDependencyContext) -> ClubOwnerRefundFixtureAccess {
        let fixture = ClubOwnerRefundFixtureAccess(); fixture.identity = .init(accountID: context.session.accountID, epoch: context.session.epoch)
        fixture.namespace = context.session.namespace; return fixture
    }
    func testCouponFactoryIsDisabledWithoutExplicitApproval() async throws {
        let context = try context(), recorder = BusinessPresentationTestTransport()
        let service = CouponCodeApprovedService(configuration: try .init(baseURL: context.baseURL), transport: recorder, current: { context })
        XCTAssertFalse(service.enabled)
        do { _ = try await service.issue(historyID: 21, session: couponSession(context)); XCTFail() } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testCouponApprovedFactoryScopesIssueAndStatusAndNoExtraFields() async throws {
        let context = try context(), recorder = BusinessPresentationTestTransport()
        let service = CouponCodeApprovedService(configuration: try .init(baseURL: context.baseURL), approval: try couponApproval(context), transport: recorder, current: { context })
        recorder.response = #"{"code":200,"data":{"useStatus":0,"expiresIn":60,"token":"synthetic-server-token"}}"#
        _ = try await service.issue(historyID: 21, session: couponSession(context))
        recorder.response = #"{"code":200,"data":{"useStatus":1,"useTime":"2026-10-02 12:00:00"}}"#
        let status = try await service.status(historyID: 21, session: couponSession(context))
        XCTAssertEqual(status.useStatus, 1)
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/native/api/coupon/qr-token", "/native/api/coupon/status"])
        for request in recorder.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("name=\"couponHistoryId\"\r\n\r\n21") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
        }
    }
    func testCouponForeignSessionAndRoleChangeFailBeforeDispatch() async throws {
        let initial = try context(); var current: RuntimeDependencyContext? = initial
        let recorder = BusinessPresentationTestTransport()
        let service = CouponCodeApprovedService(configuration: try .init(baseURL: initial.baseURL), approval: try couponApproval(initial), transport: recorder, current: { current })
        do { _ = try await service.issue(historyID: 21, session: couponSession(context(account: 8))); XCTFail() } catch {}
        current = try context(role: "PLAYER")
        do { _ = try await service.status(historyID: 21, session: couponSession(initial)); XCTFail() } catch {}
        XCTAssertFalse(service.enabled); XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testCouponImageMustHaveExactApprovedOriginAndNoAPITransport() async throws {
        let context = try context(), recorder = BusinessPresentationTestTransport(), media = BusinessPresentationTestImages()
        let service = CouponCodeApprovedService(configuration: try .init(baseURL: context.baseURL), approval: try couponApproval(context, origins: ["https://images.example.com"]), transport: recorder, current: { context }, imageLoader: media)
        func receipt(_ url: String) throws -> CouponCodeReceipt {
            try JSONDecoder().decode(CouponCodeReceipt.self, from: Data("{\"useStatus\":0,\"expiresIn\":60,\"qrcodeUrl\":\"\(url)\"}".utf8))
        }
        _ = try await service.image(receipt("https://images.example.com/code.png"))
        XCTAssertEqual(media.requests, ["https://images.example.com/code.png"]); XCTAssertTrue(recorder.requests.isEmpty)
        do { _ = try await service.image(receipt("https://other.example.com/code.png")); XCTFail() } catch {}
        XCTAssertEqual(media.requests.count, 1)
    }
    func testCouponMediaLateSessionChangeRejectsResponse() async throws {
        let context = try context(); var current: RuntimeDependencyContext? = context
        let media = BusinessPresentationTestImages(); media.onRead = { current = nil }
        let service = CouponCodeApprovedService(configuration: try .init(baseURL: context.baseURL), approval: try couponApproval(context, origins: ["https://images.example.com"]), transport: BusinessPresentationTestTransport(), current: { current }, imageLoader: media)
        let receipt = try JSONDecoder().decode(CouponCodeReceipt.self, from: Data(#"{"useStatus":0,"expiresIn":60,"qrcodeUrl":"https://images.example.com/code.png"}"#.utf8))
        do { _ = try await service.image(receipt); XCTFail() } catch {}
        XCTAssertFalse(service.enabled)
    }
    func testCouponUnauthorizedNotifiesOnlyMatchingSessionAndClearsCode() async throws {
        let context = try context(), session = try couponSession(context), recorder = BusinessPresentationTestTransport()
        recorder.response = #"{"code":401}"#
        let service = CouponCodeApprovedService(configuration: try .init(baseURL: context.baseURL), approval: try couponApproval(context), transport: recorder, current: { context })
        var notified: CouponCodeSession?
        let model = CouponCodeCoordinator(historyID: 21, service: service, currentSession: { session }, onUnauthorized: { notified = $0 })
        await model.confirmPresentation()
        XCTAssertEqual(notified, session); XCTAssertEqual(model.phase, .login); XCTAssertNil(model.displayToken)
    }
    func testRefundDefaultConfiguredAccessKeepsReadOnlyAndNoSend() async throws {
        let context = try context(), fixture = fallback(context), recorder = BusinessPresentationTestTransport()
        let readOnly = ClubOwnerRefundReadOnlyAccess(governance: fixture.governance)
        let access = ClubOwnerRefundConfiguredAccess(fallback: readOnly, configuration: try .init(baseURL: context.baseURL), transport: recorder, current: { context })
        XCTAssertFalse(access.canDispatch); XCTAssertFalse(access.canDispatchOffline)
        let target = try ClubOwnerRefundTarget(clubID: 81, registrationID: 121)
        let evidence = try await access.evidence(target)
        XCTAssertEqual(evidence.target, target); XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testRefundApprovalRequiresAllPathsAndExactAccountMarketNamespace() throws {
        let context = try context()
        XCTAssertTrue(try refundApproval(context).matches(context))
        let partial = ClubOwnerRefundApproval(market: .china, endpoints: try endpoints(context, paths: ["api/registration/cancel-by-owner"]))
        XCTAssertFalse(partial.matches(context)); XCTAssertFalse(try refundApproval(context).matches(self.context(account: 8)))
        let other = RuntimeDependencyContext(market: .unitedStates, baseURL: context.baseURL, role: context.role, session: context.session)
        XCTAssertFalse(try refundApproval(context).matches(other))
    }
    func testRefundConfiguredAccessUsesFreshOwnerReadsExactFormAndRetainsBothLocks() async throws {
        let context = try context(), fixture = fallback(context), recorder = BusinessPresentationTestTransport()
        recorder.refundFixture = true
        let access = ClubOwnerRefundConfiguredAccess(fallback: fixture, configuration: try .init(baseURL: context.baseURL), approval: try refundApproval(context), transport: recorder, current: { context })
        let locks = ClubOwnerRefundMemoryLocks(), target = try ClubOwnerRefundTarget(clubID: 81, registrationID: 121)
        let model = ClubOwnerRefundCoordinator(access: access, locks: locks)
        XCTAssertTrue(access.canDispatch); XCTAssertFalse(access.canDispatchOffline)
        let review = try await model.prepare(target, ownerID: UUID()); await model.confirm(review)
        XCTAssertEqual(model.state(target).phase, .acknowledged); XCTAssertEqual(locks.values.count, 2)
        let requests = recorder.requests.filter { $0.url?.path.hasSuffix("cancel-by-owner") == true }
        XCTAssertEqual(requests.count, 1)
        let body = String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n121")); XCTAssertFalse(body.contains("amount")); XCTAssertFalse(body.contains("clubId"))
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(model.state(target).receipt?.cash, .processing)
    }
    func testRefundRoleOrTokenChangeBetweenReviewAndConfirmCannotSend() async throws {
        let initial = try context(); var current: RuntimeDependencyContext? = initial
        let fixture = fallback(initial), recorder = BusinessPresentationTestTransport(); recorder.refundFixture = true
        let access = ClubOwnerRefundConfiguredAccess(fallback: fixture, configuration: try .init(baseURL: initial.baseURL), approval: try refundApproval(initial), transport: recorder, current: { current })
        let locks = ClubOwnerRefundMemoryLocks(), model = ClubOwnerRefundCoordinator(access: access, locks: locks)
        let target = try ClubOwnerRefundTarget(clubID: 81, registrationID: 121)
        let review = try await model.prepare(target, ownerID: UUID())
        current = try context(token: "rotated"); await model.confirm(review)
        XCTAssertTrue(locks.values.isEmpty); XCTAssertFalse(recorder.requests.contains { $0.url?.path.hasSuffix("cancel-by-owner") == true })
        XCTAssertEqual(model.state(target).phase, .idle)
    }
    func testRefundAmbiguousDispatchStaysUnknownAndNeverReplays() async throws {
        let context = try context(), fixture = fallback(context), recorder = BusinessPresentationTestTransport(); recorder.refundFixture = true; recorder.failRefund = true
        let access = ClubOwnerRefundConfiguredAccess(fallback: fixture, configuration: try .init(baseURL: context.baseURL), approval: try refundApproval(context), transport: recorder, current: { context })
        let locks = ClubOwnerRefundMemoryLocks(), model = ClubOwnerRefundCoordinator(access: access, locks: locks)
        let target = try ClubOwnerRefundTarget(clubID: 81, registrationID: 121)
        let review = try await model.prepare(target, ownerID: UUID()); await model.confirm(review); await model.confirm(review); await model.reconcile(target)
        XCTAssertEqual(model.state(target).phase, .outcomeUnknown); XCTAssertEqual(locks.values.count, 2)
        XCTAssertEqual(recorder.requests.filter { $0.url?.path.hasSuffix("cancel-by-owner") == true }.count, 1)
        do { _ = try await model.prepare(target, ownerID: UUID()); XCTFail() } catch {}
    }
}
private final class BusinessPresentationTestImages: ObjectCardImageLoading {
    var requests: [String] = []
    var onRead: (() -> Void)?
    func image(url: String) async throws -> Data { requests.append(url); onRead?(); return Data([137,80,78,71]) }
}
@MainActor private final class BusinessPresentationTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = "{}"
    var refundFixture = false
    var failRefund = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard refundFixture else { return (Data(response.utf8), 200) }
        let path = request.url?.path ?? ""
        let body: String
        if path.hasSuffix("api/club/access/me") {
            body = #"{"code":200,"data":{"active":true,"club":{"id":81},"roleCodes":["CLUB_OWNER"],"permissions":["club:member:list:read"],"canManageRoles":true}}"#
        } else if path.hasSuffix("api/club/crm/checkin/detail") {
            body = #"{"code":200,"data":{"registrationId":121,"displayName":"Fixture attendee","orderNo":"SYNTHETIC-PARENT","statusCode":"PENDING","railStep":0,"canRefund":true}}"#
        } else {
            if failRefund { throw URLError(.timedOut) }
            body = #"{"code":200,"data":{"registrationId":121,"scope":"PARENT_ORDER","cancellationStatus":"CANCELLED","cashRefundStatus":"PROCESSING","pointsRefundStatus":"RETURNED"}}"#
        }
        return (Data(body.utf8), 200)
    }
}
