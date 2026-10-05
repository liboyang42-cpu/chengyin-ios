#if DEBUG
import SwiftUI

@MainActor private final class CouponManagementFixtureContext: ObservableObject, CouponManagementTransport, CouponPublisherAuthorizing, CouponManagementLocking {
    let isSynthetic = true
    @Published var session: CouponManagementSession? = try? .init(accountID: 910, namespace: "coupon-management-synthetic", epoch: 1, authorizationRevision: "fixture")
    @Published var mount = UUID()
    private var locks: [String: CouponManagementPending] = [:]
    private var stopped = false
    lazy var coordinator = makeCoordinator()
    func makeCoordinator() -> CouponManagementCoordinator {
        let value = CouponManagementCoordinator(adapter: .init(transport: self, syntheticWritesEnabled: !ProcessInfo.processInfo.arguments.contains("--coupon-management-disabled")), authorizer: self, locks: self, currentSession: { [weak self] in self?.session })
        if !ProcessInfo.processInfo.arguments.contains("--coupon-management-blank") { value.change(CouponManagementSyntheticFixtures.draft()) }
        return value
    }
    func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission { .init(revision: "synthetic-publisher", mayPublish: true) }
    func send(_ request: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int) {
        if request.mutates {
            if ProcessInfo.processInfo.arguments.contains("--coupon-management-unknown") { throw URLError(.timedOut) }
            if request.path == "/api/coupon/stop" { stopped = true }
            return (Data(#"{"code":200}"#.utf8), 200)
        }
        if stopped { return (Data(#"{"code":200,"data":[{"id":710,"name":"Synthetic gift coupon","status":4}]}"#.utf8), 200) }
        return (CouponManagementSyntheticFixtures.published, 200)
    }
    func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { locks[ownerKey + resource] }
    func acquire(_ value: CouponManagementPending) throws {
        let key = value.ownerKey + value.resource; guard locks[key] == nil else { throw CouponManagementError.locked }; locks[key] = value
    }
    func release(_ value: CouponManagementPending) throws { locks.removeValue(forKey: value.ownerKey + value.resource) }
    func reopen() { coordinator.leave(); coordinator = makeCoordinator(); mount = UUID() }
    func signOut() { session = nil; coordinator.synchronize(); mount = UUID() }
}
@MainActor struct CouponManagementFixtureHost: View {
    @StateObject private var context = CouponManagementFixtureContext()
    var body: some View {
        VStack {
            HStack {
                Button("couponManagement.fixtureReopen") { context.reopen() }.accessibilityIdentifier("couponManagement.fixture.reopen")
                Button("couponManagement.fixtureSignOut") { context.signOut() }.accessibilityIdentifier("couponManagement.fixture.signOut")
            }.buttonStyle(.bordered)
            NavigationStack {
                CouponManagementView(coordinator: context.coordinator, sessionKey: context.session, isSourceVisible: true)
            }.id(context.mount)
        }
    }
}
#endif
