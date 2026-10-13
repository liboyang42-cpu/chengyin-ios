import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileWeeklyPointsSectionTests: XCTestCase {
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<100 { if condition() { return }; await Task.yield() }
        XCTAssertTrue(condition())
    }
    func testInitialAppearanceLoadsAndZeroRemainsAValue() async throws {
        let reader = Reader(), model = ProfileWeeklyPointsScreenModel(reader: Reader(), isCurrent: { true })
        model.appear(active: true); await settle { if case .content = model.state { return true }; return false }
        let owned = ProfileWeeklyPointsScreenModel(reader: reader, isCurrent: { true })
        owned.appear(active: true); await settle { if case .content = owned.state { return true }; return false }
        guard case .content(let value) = owned.state else { return XCTFail() }
        XCTAssertEqual(value.weekPoints, 0); XCTAssertEqual(reader.reads, 1)
        owned.disappear(); model.disappear()
    }
    func testFailureRetryPreservesHonestErrorUntilARealReadSucceeds() async {
        let reader = Reader(); reader.fail = true
        let model = ProfileWeeklyPointsScreenModel(reader: reader, isCurrent: { true })
        model.appear(active: true); await settle { model.state == .failed }
        XCTAssertEqual(reader.reads, 1); reader.fail = false; model.refresh()
        await settle { if case .content = model.state { return true }; return false }
        XCTAssertEqual(reader.reads, 2); model.disappear()
    }
    func testNoApprovalIsUnavailableWithoutDispatchAndLaterApprovalCanLoad() async {
        let reader = Reader(); reader.isConfigured = false
        let model = ProfileWeeklyPointsScreenModel(reader: reader, isCurrent: { true })
        model.appear(active: true); await Task.yield()
        XCTAssertEqual(model.state, .unavailable); XCTAssertEqual(reader.reads, 0)
        reader.isConfigured = true; model.refresh()
        await settle { if case .content = model.state { return true }; return false }
        reader.isConfigured = false
        XCTAssertEqual(model.state, .unavailable); model.disappear()
    }
    func testHiddenForegroundCannotRestartReadAndLateReplyCannotRefill() async {
        let reader = Reader(); reader.suspend = true
        let model = ProfileWeeklyPointsScreenModel(reader: reader, isCurrent: { true })
        model.appear(active: true); await settle { reader.pending != nil }
        model.disappear(); model.sceneChanged(active: true); reader.finish()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(model.state, .changed)
    }
    func testBackgroundRetiresResultAndOnlyVisibleReturnReadsAgain() async {
        let reader = Reader(), model = ProfileWeeklyPointsScreenModel(reader: Reader(), isCurrent: { true })
        let own = ProfileWeeklyPointsScreenModel(reader: reader, isCurrent: { true })
        own.appear(active: true); await settle { if case .content = own.state { return true }; return false }
        own.sceneChanged(active: false); XCTAssertEqual(own.state, .changed)
        own.sceneChanged(active: true); await settle { reader.reads == 2 }
        own.disappear(); model.sceneChanged(active: true); XCTAssertFalse(model.visible)
    }
    func testIdentityChangeAndOldOwnerCallbackCannotPublish() async {
        for change in ["account", "revision", "owner", "approval"] {
            let reader = Reader(); reader.suspend = true; var current = true
            let model = ProfileWeeklyPointsScreenModel(reader: reader, isCurrent: { current })
            model.appear(active: true); await settle { reader.pending != nil }
            switch change {
            case "account": reader.identity = .init(accountID: 82, epoch: 2, approvalRevision: UUID())
            case "revision": reader.identity = .init(accountID: 81, epoch: 1, viewerRevision: 2, approvalRevision: UUID())
            case "approval": reader.isConfigured = false
            default: current = false
            }
            reader.finish(); for _ in 0..<10 { await Task.yield() }
            if case .content = model.state { XCTFail(change) }
            model.disappear(); model.refresh(); XCTAssertEqual(reader.reads, 1)
        }
    }
    func testPublicOtherGuestAndRetiredOwnerNeverAcquireSelfEntry() {
        let social = ProfileSelfGrowthFixturePublicReader(), weekly = Reader()
        let access = ProfileWeeklyPointsAccess(reader: weekly, owner: social.identity)
        XCTAssertTrue(access.owns(memberID: 81, accountReader: social, isCurrent: true))
        XCTAssertFalse(access.owns(memberID: 82, accountReader: social, isCurrent: true))
        XCTAssertFalse(access.owns(memberID: 81, accountReader: social, isCurrent: false))
        social.identity = .init(accountID: nil, epoch: 2)
        XCTAssertFalse(access.owns(memberID: 81, accountReader: social, isCurrent: true))
        XCTAssertEqual(weekly.reads, 0)
    }
    func testNormalPublicProfileInitializerAcceptsSelfOnlyWeeklyAccess() {
        let social = ProfileSelfGrowthFixturePublicReader(), weekly = Reader()
        let view = SocialPublicProfileView(memberID: 81, reader: social, squareReader: social,
            weeklyPointsAccess: .init(reader: weekly, owner: social.identity))
        let host = UIHostingController(rootView: NavigationStack { view })
        host.loadViewIfNeeded(); XCTAssertNotNil(host.view)
        // Instantiation never manufactures an approval or issues a write.
        XCTAssertEqual(weekly.reads, 0)
    }
    func testNormalOwnerHostReadsWeeklyWhilePublicParentIsUnavailable() async {
        let social = ProfileSelfGrowthFixturePublicReader(), weekly = Reader()
        social.isConfigured = false
        let read = expectation(description: "independent own-profile weekly read")
        weekly.onRead = { read.fulfill() }
        let host = UIHostingController(rootView: NavigationStack {
            SocialPublicProfileView(memberID: 81, reader: social, squareReader: social,
                weeklyPointsAccess: .init(reader: weekly, owner: social.identity))
        }.environment(\.scenePhase, .active))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await fulfillment(of: [read], timeout: 2)
        XCTAssertEqual(weekly.reads, 1); XCTAssertFalse(social.isConfigured)
        window.isHidden = true; window.rootViewController = nil
    }
    func testUnavailablePublicParentDoesNotHideSelfUnavailableStateOrDispatch() async {
        let social = ProfileSelfGrowthFixturePublicReader(), weekly = Reader()
        social.isConfigured = false; weekly.isConfigured = false
        let access = ProfileWeeklyPointsAccess(reader: weekly, owner: social.identity)
        XCTAssertTrue(access.owns(memberID: 81, accountReader: social, isCurrent: true))
        let model = ProfileWeeklyPointsScreenModel(reader: weekly, isCurrent: {
            access.owns(memberID: 81, accountReader: social, isCurrent: true)
        })
        model.appear(active: true); await Task.yield()
        XCTAssertEqual(model.state, .unavailable); XCTAssertEqual(weekly.reads, 0)
        model.disappear()
    }
    @MainActor private final class Reader: ProfileWeeklyPointsReading {
        var identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1, viewerRevision: 1, approvalRevision: UUID())
        var isConfigured = true, fail = false, suspend = false
        var reads = 0
        var onRead: (() -> Void)?
        var pending: CheckedContinuation<ProfileWeeklyPoints, Error>?
        static var value: ProfileWeeklyPoints { try! JSONDecoder().decode(ProfileWeeklyPoints.self,
            from: Data(#"{"weekPoints":0,"rankPercentage":"TOP 50%","totalUsers":10,"userRank":5}"#.utf8)) }
        func weeklyPoints() async throws -> ProfileWeeklyPoints {
            reads += 1; onRead?()
            if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
            if fail { throw APIError.httpStatus(503) }
            return Self.value
        }
        func finish() { pending?.resume(returning: Self.value); pending = nil }
    }
}
