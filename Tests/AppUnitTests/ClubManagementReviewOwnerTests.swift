import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ClubManagementReviewOwnerTests: XCTestCase {
    @MainActor private final class Access: ClubManagementAccess {
        var identity: ClubReadIdentity? = .init(accountID: 1, epoch: 1)
        let isConfigured = true
        var sends = 0, reads = 0
        var acknowledged = false, unknown = false, readbackFails = false
        var wait: CheckedContinuation<Void, Never>?
        var hold = false
        func snapshot(clubID: Int) async throws -> ClubManagementSnapshot {
            reads += 1
            if hold { await withCheckedContinuation { wait = $0 } }
            if acknowledged && readbackFails { throw APIError.malformedResponse }
            let club = try JSONDecoder().decode(ClubRecord.self, from: Data(#"{"id":81,"name":"Example club","isOwner":true,"isJoined":true}"#.utf8))
            let requests = try JSONDecoder().decode([ClubManagementRequest].self, from: Data((acknowledged ? "[]" : #"[{"memberId":3,"nickname":"Example applicant","joinMessage":"Hello"}]"#).utf8))
            return .init(club: club, requests: requests, members: [])
        }
        func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
            sends += 1
            if unknown { throw ClubActionWriteError.outcomeUnknown(.transport) }
            acknowledged = true
            return .init(state: nil, message: "Acknowledged")
        }
    }
    @MainActor private final class Harness {
        let access = Access()
        let owner = ClubManagementReviewOwner()
        lazy var coordinator = ClubManagementCoordinator(access: access)
        var active = true, revision: UInt64 = 0
        var context: ClubManagementReviewOwner.Context {
            .init(clubID: 81, identity: access.identity, revision: revision,
                  access: ObjectIdentifier(access), coordinator: ObjectIdentifier(coordinator))
        }
        func appear() { owner.appear(context) }
        func prepare(_ action: ClubManagementAction = .approve) async throws -> ClubManagementReviewOwner.Item {
            let attachment = try XCTUnwrap(owner.attachment), source = context
            let review = try await coordinator.prepare(clubID: 81, action: action, memberID: 3,
                expectedIdentity: XCTUnwrap(access.identity), ownerID: attachment)
            guard owner.stage(review, attachment: attachment, context: source, active: active) else {
                coordinator.cancel(review); throw ClubActionBlock.staleConfirmation
            }
            return try XCTUnwrap(owner.item)
        }
        func binding(_ item: ClubManagementReviewOwner.Item) -> Binding<Bool> {
            owner.binding(item, context: { self.context }, active: { self.active }, cancelled: { self.coordinator.cancel($0.confirmation) })
        }
        func depart(_ id: UUID) {
            guard owner.depart(id), let identity = access.identity else { return }
            coordinator.leaveScreen(clubID: 81, expectedIdentity: identity, ownerID: id)
        }
        func dispatch(_ item: ClubManagementReviewOwner.Item) async {
            guard owner.permitsDispatch(item, context: context, active: active) else { coordinator.cancel(item.confirmation); return }
            _ = await coordinator.confirm(item.confirmation)
        }
    }
    private func ready() -> Harness { let h = Harness(); h.appear(); return h }
    func testPrepareIsFreshAndNeverSendsUntilClaim() async throws {
        let h = ready(), item = try await h.prepare()
        XCTAssertEqual(h.access.reads, 1); XCTAssertEqual(h.access.sends, 0)
        XCTAssertEqual(item.confirmation.memberID, 3); XCTAssertEqual(item.confirmation.memberName, "Example applicant")
        await h.dispatch(item); XCTAssertEqual(h.access.sends, 0)
    }
    func testCancelThenReopenRejectsOldNilSetter() async throws {
        let h = ready(), old = try await h.prepare(), binding = h.binding(old)
        binding.wrappedValue = false; h.owner.dismissed(old)
        let fresh = try await h.prepare(.reject)
        binding.wrappedValue = false; h.owner.dismissed(old)
        XCTAssertEqual(h.owner.item, fresh); XCTAssertTrue(h.binding(fresh).wrappedValue)
        XCTAssertFalse(h.owner.claim(old, context: h.context, active: true)); XCTAssertEqual(h.access.sends, 0)
    }
    func testExplicitOldCancelDoesNotTouchNewConfirmation() async throws {
        let h = ready(), old = try await h.prepare()
        h.binding(old).wrappedValue = false; h.owner.dismissed(old)
        let fresh = try await h.prepare()
        XCTAssertFalse(h.owner.cancel(old)); XCTAssertEqual(h.owner.item, fresh)
    }
    func testApprovalClaimSendsOnceAndUsesAuthoritativeReadback() async throws {
        let h = ready(), item = try await h.prepare()
        XCTAssertTrue(h.owner.claim(item, context: h.context, active: true))
        XCTAssertFalse(h.owner.claim(item, context: h.context, active: true))
        await h.dispatch(item); await h.dispatch(item)
        XCTAssertEqual(h.access.sends, 1); XCTAssertEqual(h.access.reads, 2)
        guard case .acknowledged = h.coordinator.state(clubID: 81), case .received(let snapshot) = h.coordinator.readback(clubID: 81) else { return XCTFail() }
        XCTAssertTrue(snapshot.requests.isEmpty)
    }
    func testRejectUsesSameExplicitConfirmationAndReadback() async throws {
        let h = ready(), item = try await h.prepare(.reject)
        XCTAssertEqual(item.confirmation.action, .reject)
        XCTAssertTrue(h.owner.claim(item, context: h.context, active: true)); await h.dispatch(item)
        XCTAssertEqual(h.access.sends, 1)
        guard case .received(let snapshot) = h.coordinator.readback(clubID: 81) else { return XCTFail() }
        XCTAssertTrue(snapshot.requests.isEmpty)
    }
    func testUnknownDoesNotReplayOrBecomeAcknowledged() async throws {
        let h = ready(), item = try await h.prepare(); h.access.unknown = true
        XCTAssertTrue(h.owner.claim(item, context: h.context, active: true)); await h.dispatch(item); await h.dispatch(item)
        guard case .outcomeUnknown = h.coordinator.state(clubID: 81) else { return XCTFail() }
        XCTAssertEqual(h.access.sends, 1); XCTAssertTrue(h.coordinator.state(clubID: 81).preventsNewAction)
        _ = await h.coordinator.readBack(clubID: 81)
        XCTAssertTrue(h.coordinator.state(clubID: 81).preventsNewAction); XCTAssertEqual(h.access.sends, 1)
    }
    func testAcknowledgementWithReadbackFailureDoesNotInventMembership() async throws {
        let h = ready(), item = try await h.prepare(); h.access.readbackFails = true
        XCTAssertTrue(h.owner.claim(item, context: h.context, active: true)); await h.dispatch(item)
        guard case .acknowledged = h.coordinator.state(clubID: 81) else { return XCTFail() }
        XCTAssertEqual(h.coordinator.readback(clubID: 81), .unavailable); XCTAssertEqual(h.access.sends, 1)
    }
    func testBackgroundBeforeDispatchRejectsClaimWithoutSending() async throws {
        let h = ready(), item = try await h.prepare()
        XCTAssertTrue(h.owner.claim(item, context: h.context, active: true))
        h.active = false; h.depart(item.attachment); await h.dispatch(item)
        XCTAssertEqual(h.access.sends, 0); XCTAssertNil(h.owner.item)
    }
    func testAccountAndSameAccountRevisionChangesRejectOldClaim() async throws {
        for changeAccount in [true, false] {
            let h = ready(), item = try await h.prepare()
            if changeAccount { h.access.identity = .init(accountID: 2, epoch: 2) } else { h.revision += 1 }
            XCTAssertFalse(h.owner.claim(item, context: h.context, active: true))
            XCTAssertFalse(h.binding(item).wrappedValue); XCTAssertEqual(h.access.sends, 0)
        }
    }
    func testActualAttachmentDepartureRejectsLatePrepare() async throws {
        let h = ready(), attachment = try XCTUnwrap(h.owner.attachment); h.access.hold = true
        let task = Task { try await h.prepare() }
        for _ in 0..<100 { if h.access.wait != nil { break }; await Task.yield() }
        XCTAssertNotNil(h.access.wait); h.depart(attachment)
        h.access.hold = false; h.access.wait?.resume(); h.access.wait = nil
        do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertNil(h.owner.item); XCTAssertEqual(h.access.sends, 0)
    }
    func testOldAttachmentHideAndDepartureCannotRetireNewDetail() async throws {
        let h = ready(), old = try XCTUnwrap(h.owner.attachment)
        h.depart(old); h.appear(); let fresh = try await h.prepare()
        h.owner.hide(old); h.depart(old)
        XCTAssertTrue(h.owner.current(fresh, context: h.context, active: true)); XCTAssertNotEqual(old, fresh.attachment)
    }
    func testOwnModalCoverageAllowsConfirmationButRealDepartureRejectsIt() async throws {
        let h = ready(), item = try await h.prepare()
        h.owner.cover(item.attachment); h.owner.hide(item.attachment)
        XCTAssertTrue(h.owner.current(item, context: h.context, active: true))
        h.depart(item.attachment)
        XCTAssertFalse(h.owner.claim(item, context: h.context, active: true)); XCTAssertEqual(h.access.sends, 0)
    }
    @MainActor private struct Host: View {
        @ObservedObject var owner: ClubManagementReviewOwner
        let h: Harness
        var body: some View {
            Text("Management detail").background {
                if let attachment = owner.attachment {
                    ClubManagementReviewLifetime(covered: { owner.cover(attachment) }, departed: { h.depart(attachment) }).id(attachment)
                }
                if let item = owner.item {
                    ClubManagementReviewPresentation(item: item, owner: owner, context: { h.context }, active: { h.active },
                        cancelled: { h.coordinator.cancel($0.confirmation) }) { Text("Review") }.id(item.id)
                }
            }.onAppear { h.appear() }
        }
    }
    private enum WaitFailure: Error { case timeout }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition()); if !condition() { throw WaitFailure.timeout }
    }
    func testRealHostInitiallyNilPresentsCancelsAndReopensConcreteReview() async throws {
        let h = Harness(), window = try HostedNavigationSceneWindow()
        let host = UIHostingController(rootView: AnyView(Host(owner: h.owner, h: h)))
        window.window.rootViewController = host; window.window.makeKeyAndVisible(); defer { window.retire() }
        try await wait { h.owner.attachment != nil }
        let first = try await h.prepare(), old = h.binding(first)
        try await wait { host.presentedViewController?.viewIfLoaded?.window != nil }
        old.wrappedValue = false
        try await wait { host.presentedViewController == nil }
        let next = try await h.prepare(.reject)
        try await wait { host.presentedViewController?.viewIfLoaded?.window != nil }
        old.wrappedValue = false; h.owner.dismissed(first); XCTAssertEqual(h.owner.item, next); XCTAssertEqual(h.access.sends, 0)
    }
    func testRealHostDismantleRetiresReviewAndCannotReappearFromOldBinding() async throws {
        let h = Harness(), window = try HostedNavigationSceneWindow()
        let host = UIHostingController(rootView: AnyView(Host(owner: h.owner, h: h)))
        window.window.rootViewController = host; window.window.makeKeyAndVisible(); defer { window.retire() }
        try await wait { h.owner.attachment != nil }
        let item = try await h.prepare(), old = h.binding(item)
        try await wait { host.presentedViewController?.viewIfLoaded?.window != nil }
        host.rootView = AnyView(Text("Departed"))
        try await wait { h.owner.attachment == nil && host.presentedViewController == nil }
        old.wrappedValue = true
        XCTAssertNil(h.owner.item); XCTAssertFalse(h.owner.claim(item, context: h.context, active: true))
    }
}
