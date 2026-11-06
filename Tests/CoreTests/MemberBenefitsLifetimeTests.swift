import Foundation
import Observation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class BenefitsSuspendedWire: HTTPTransport {
    var requests: [URLRequest] = []
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(unauthorized: Bool = false) {
        let value = pending; pending = nil
        value?.resume(returning: (Data((unauthorized ? "{\"code\":401}" : "{\"code\":200,\"data\":{\"role\":\"player\",\"permission\":{\"withdrawable\":true}}}").utf8), 200))
    }
}
@MainActor private final class BenefitsObservationCount { var value = 0 }
@MainActor final class MemberBenefitsLifetimeTests: XCTestCase {
    private func context(role: String = "player", account: Int = 7, token: String = "synthetic-benefits", epoch: UInt64 = 1, namespace: String = "benefits", base: String = "https://benefits.example.test/native") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: base)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
    }
    func testOriginalInitializerDefaultsAndEqualityRemainCompatible() throws {
        let approval = UUID()
        let a = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: approval)
        let b = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: approval, role: nil, viewerRevision: 0)
        XCTAssertEqual(a, b); XCTAssertNil(a.role); XCTAssertEqual(a.viewerRevision, 0)
    }
    func testRoleAndViewerAreIdentityFencesNotPermissions() throws {
        let a = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: nil, role: "player", viewerRevision: 1)
        let b = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: nil, role: "merchant", viewerRevision: 1)
        let c = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: nil, role: "player", viewerRevision: 3)
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, c)
        let reader = MemberHomeSessionReader(service: nil, currentSession: { c }); XCTAssertFalse(reader.roleInfoAvailable)
    }
    func testRoleComparisonDoesNotCollapseDistinctUTF8() throws {
        let a = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: nil, role: "é", viewerRevision: 1)
        let b = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: nil, role: "e\u{301}", viewerRevision: 1)
        XCTAssertNotEqual(a, b)
    }
    func testViewerRevisionPreventsUnobservedRoleABARestoringOldScope() throws {
        var value = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: UUID(), role: "player", viewerRevision: 1)
        let first = value, reader = MemberHomeSessionReader(service: nil, currentSession: { value }), scope = reader.scope
        value = try .init(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: first.roleInfoApproval, role: "merchant", viewerRevision: 2)
        // No read of reader.scope while in B.
        value = try .init(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: first.roleInfoApproval, role: "player", viewerRevision: 3)
        XCTAssertNotEqual(reader.scope, scope); XCTAssertNotEqual(value, first)
    }
    private func assertLateABARejected(unauthorized: Bool) async throws {
        let wire = BenefitsSuspendedWire(), grant = UUID()
        var value = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: grant, role: "player", viewerRevision: 1)
        var expirations = 0
        let reader = MemberHomeSessionReader(service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://benefits.example.test/native")!), transport: wire), currentSession: { value }, onUnauthorized: { _ in expirations += 1 })
        let task = Task { try await reader.roleInfo() }
        for _ in 0..<100 { if wire.pending != nil { break }; await Task.yield() }
        guard wire.pending != nil else { task.cancel(); XCTFail("Synthetic admission failed"); return }
        value = try .init(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: grant, role: "merchant", viewerRevision: 2)
        value = try .init(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: grant, role: "player", viewerRevision: 3)
        wire.finish(unauthorized: unauthorized)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
    }
    func testLateSuccessCannotPopulateNewViewerAfterABA() async throws { try await assertLateABARejected(unauthorized: false) }
    func testLateUnauthorizedCannotExpireCurrentViewerAfterABA() async throws { try await assertLateABARejected(unauthorized: true) }
    func testPermissionScopeAndTwentyFourHourLimitAreUnchanged() throws {
        let c = try context()
        XCTAssertThrowsError(try MemberRoleInfoReadApproval(context: c, expiresAt: Date().addingTimeInterval(86_500)))
        XCTAssertThrowsError(try MemberRoleInfoReadApproval(context: c, expiresAt: .distantPast))
        XCTAssertThrowsError(try MemberRoleInfoReadApproval(context: context(role: "unknown"), expiresAt: Date().addingTimeInterval(60)))
        let value = try MemberRoleInfoReadApproval(context: c, expiresAt: Date().addingTimeInterval(60)); defer { value.revoke() }
        let configuration = try APIConfiguration(baseURL: c.baseURL)
        XCTAssertTrue(value.endpoints.allows(configuration: configuration, namespace: c.session.namespace, accountID: 7, path: MemberRoleInfoReadRoute.path))
        XCTAssertFalse(value.endpoints.allows(configuration: configuration, namespace: c.session.namespace, accountID: 7, path: "api/user/info"))
    }
    func testWallClockArgumentCannotUndoRevocation() throws {
        let c = try context(), value = try MemberRoleInfoReadApproval(context: c, expiresAt: Date().addingTimeInterval(60))
        let deadline = value.clientDeadline; value.revoke()
        XCTAssertFalse(value.matches(c, now: .distantPast)); XCTAssertEqual(value.clientDeadline, deadline)
    }
    func testDeadlineIsCapturedAtConstructionNotTimerAdmission() throws {
        let c = try context(), before = ContinuousClock().now
        let value = try MemberRoleInfoReadApproval(context: c, expiresAt: Date().addingTimeInterval(60)); defer { value.revoke() }
        XCTAssertGreaterThan(value.clientDeadline, before)
        XCTAssertLessThan(value.clientDeadline, ContinuousClock().now.advanced(by: .seconds(61)))
        let deadline = value.clientDeadline
        for _ in 0..<50 { XCTAssertTrue(value.matches(c, now: .distantPast)); XCTAssertEqual(value.clientDeadline, deadline) }
    }
    func testElapsedMonotonicLeaseCannotMatchRolledBackWallClock() async throws {
        let c = try context(), value = try MemberRoleInfoReadApproval(context: c, expiresAt: Date().addingTimeInterval(0.05)); defer { value.revoke() }
        try await ContinuousClock().sleep(until: value.clientDeadline.advanced(by: .milliseconds(10)))
        XCTAssertFalse(value.matches(c, now: .distantPast))
    }
    func testAllOriginalContextChecksRemainEffective() throws {
        let c = try context(), value = try MemberRoleInfoReadApproval(context: c, expiresAt: Date().addingTimeInterval(60)); defer { value.revoke() }
        for next in [try context(role: "merchant"), try context(account: 8), try context(token: "other"), try context(epoch: 2), try context(namespace: "other"), try context(base: "https://other.example.test")] { XCTAssertFalse(value.matches(next)) }
        XCTAssertTrue(value.matches(c))
    }
    func testSynchronizedScopePublishesWithoutWaitingForAReadResponse() throws {
        let grant = UUID(), count = BenefitsObservationCount()
        var current = try MemberHomeSession(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: grant, role: "player", viewerRevision: 1)
        let reader = MemberHomeSessionReader(service: nil, currentSession: { current }), first = reader.scope
        withObservationTracking { _ = reader.scope } onChange: { MainActor.assumeIsolated { count.value += 1 } }
        current = try .init(accountID: 7, epoch: 1, token: "synthetic-benefits", roleInfoApproval: grant, role: "merchant", viewerRevision: 2)
        _ = reader.scope // Host synchronization, no HTTP or SwiftUI task.
        XCTAssertEqual(count.value, 1); XCTAssertNotEqual(reader.scope, first)
    }
    func testOriginalPermissionMappingDoesNotInferEarningsFromRoleOrMissingFlags() throws {
        for role in ["player", "club", "merchant"] {
            let bytes = try JSONSerialization.data(withJSONObject: ["role": role, "permission": ["maxThemes": NSNull()]])
            let value = try JSONDecoder().decode(MemberRoleInfo.self, from: bytes)
            XCTAssertEqual(value.benefits.count, 9); XCTAssertFalse(value.benefits.contains { $0.opensEarnings })
            XCTAssertEqual(value.benefits.first?.routeLimit, .unlimited)
        }
    }
}
