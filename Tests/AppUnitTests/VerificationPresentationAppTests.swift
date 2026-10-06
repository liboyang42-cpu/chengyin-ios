import XCTest
@testable import Questify

@MainActor final class VerificationPresentationAppTests: XCTestCase {
    func testShippedBusinessPresentationApprovalsRemainNil() {
        let dependencies = NativeRuntimeDependencies.dormant
        XCTAssertNil(dependencies.verificationCodeApproval)
        XCTAssertNil(dependencies.couponCodeApproval)
        XCTAssertNil(dependencies.ownerRefundApproval)
    }
    func testNormalSessionFactoriesRemainUnavailableWithoutApprovedDeployment() async {
        let session = AppSession()
        let ticket = session.makeVerificationCodeCoordinator(target: .init(kind: .ticket, id: 31))
        let city = session.makeVerificationCodeCoordinator(target: .init(kind: .cityVoucher, id: 31))
        await ticket.present(); await city.present()
        XCTAssertNil(ticket.displayCode); XCTAssertNil(city.displayCode)
        XCTAssertFalse(session.makeCouponCodeCoordinator(historyID: 21).enabled)
        XCTAssertFalse(session.clubOwnerRefundCoordinator.canDispatch)
    }
    func testOrdinaryCouponFactoryRejectsQueuedConfirmationAfterActualRoleABA() async throws {
        let wire = CouponViewerRevisionWire(), session = try couponSession(wire)
        await loginCouponSession(session)
        let old = session.makeCouponCodeCoordinator(historyID: 71)
        let presentation = try XCTUnwrap(old.beginPresentation())
        let queued = try XCTUnwrap(old.offerConfirmation(presentation: presentation))
        wire.role = "merchant"; await session.refreshOwnAccount()
        XCTAssertEqual(session.account?.effectiveRole, "merchant")
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertEqual(session.account?.effectiveRole, "player")
        await old.confirmPresentation(permit: queued)
        XCTAssertEqual(old.phase, .stale); XCTAssertNil(old.displayToken)
        XCTAssertNil(old.beginPresentation())
        XCTAssertFalse(wire.paths.contains { $0.contains("/coupon/") })
    }
    func testFreshOrdinaryCouponFactoryAfterRoleABAGetsNewReviewWithQRGrantStillClosed() async throws {
        let wire = CouponViewerRevisionWire(), session = try couponSession(wire)
        await loginCouponSession(session)
        let old = session.makeCouponCodeCoordinator(historyID: 71)
        let presentation = try XCTUnwrap(old.beginPresentation())
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNil(old.offerConfirmation(presentation: presentation))
        let fresh = session.makeCouponCodeCoordinator(historyID: 71)
        let freshPresentation = try XCTUnwrap(fresh.beginPresentation())
        let offered = try XCTUnwrap(fresh.offerConfirmation(presentation: freshPresentation))
        XCTAssertEqual(fresh.phase, .review)
        await fresh.confirmPresentation(permit: offered)
        XCTAssertFalse(fresh.enabled); XCTAssertEqual(fresh.phase, .disabled)
        XCTAssertFalse(wire.paths.contains { $0.contains("/coupon/") })
    }
    func testUnchangedRoleRefreshKeepsOrdinaryCouponReviewCurrent() async throws {
        let wire = CouponViewerRevisionWire(), session = try couponSession(wire)
        await loginCouponSession(session)
        let current = session.makeCouponCodeCoordinator(historyID: 71)
        let presentation = try XCTUnwrap(current.beginPresentation())
        await session.refreshOwnAccount()
        XCTAssertNotNil(current.offerConfirmation(presentation: presentation))
        XCTAssertFalse(wire.paths.contains { $0.contains("/coupon/") })
    }
    private func loginCouponSession(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(session.account?.effectiveRole, "player")
    }
    private func couponSession(_ wire: CouponViewerRevisionWire) throws -> AppSession {
        let suite = "coupon-viewer-revision-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let base = "https://example.test/coupon-viewer-revision"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base,
            approvedBaseURLs: [.china: [base]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.coupon-viewer-revision", realm: "synthetic")
        let vault = CouponViewerRevisionVault()
        return AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }).makeSession()
    }
}
@MainActor private final class CouponViewerRevisionVault: AppTokenStorage {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor private final class CouponViewerRevisionWire: HTTPTransport {
    var role = "player"
    private(set) var paths: [String] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""; paths.append(path)
        if path.hasSuffix("/phone") {
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "token": "synthetic-viewer-7", "data": ["id": 7, "role": role]]), 200)
        }
        if path.hasSuffix("/userInfo") {
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "appUser": ["userId": 7, "role": role]]), 200)
        }
        XCTFail("Unreviewed request: \(path)"); throw APIError.notConfigured
    }
}
