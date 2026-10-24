import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PlayPlayerActionReviewControllerTests: XCTestCase {
    @MainActor private final class Harness {
        var session: PlayExperienceSession?
        let wire = PlayerActionAppWire()
        var model: PlayPlayerGameCoordinator!
        var owner: PlayPlayerActionReviewController!
        var root: PlayPlayerActionRootController!
        let parent = UIViewController(), window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        init() throws {
            session = try .init(accountID: 1, epoch: 1, namespace: "player-action-app-tests", token: "synthetic-token")
            let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: [.reads, .playerCommands])
            model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { [weak self] in self?.session })
            owner = .init(model: model); root = .init(owner: owner); owner.attach(root)
        }
        func open() async {
            await model.load(); window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(root); parent.view.addSubview(root.view); root.didMove(toParent: parent); owner.appear(active: true)
        }
        func close() { owner.retire(); root.willMove(toParent: nil); root.view.removeFromSuperview(); root.removeFromParent(); window.isHidden = true; window.rootViewController = nil }
    }
    private func setup() async throws -> Harness { let h = try Harness(); await h.open(); return h }
    private func textReview(_ h: Harness, text: String = "Synthetic answer") throws -> PlayPlayerActionReviewController.Review {
        let ticket = try XCTUnwrap(h.owner.capture()); h.owner.setText(text, nodeID: 701, ticket: ticket)
        h.owner.prepare(.text(nodeID: 701, answer: h.owner.text(nodeID: 701)), ticket: ticket)
        return try XCTUnwrap(h.owner.review)
    }
    func testCancelPreservesExactDraftAndNewReviewHasIndependentID() async throws {
        let h = try await setup(); defer { h.close() }; let first = try textReview(h, text: "  中文 + answer  ")
        h.owner.cancel(first); XCTAssertEqual(h.owner.text(nodeID: 701), "  中文 + answer  ")
        let next = try textReview(h, text: h.owner.text(nodeID: 701)); XCTAssertNotEqual(first.id, next.id)
        XCTAssertEqual(next.value.detail, first.value.detail); XCTAssertEqual(h.wire.posts, 0)
    }
    func testOldCancelAndConfirmCannotAdoptReplacementReview() async throws {
        let h = try await setup(); defer { h.close() }; let old = try textReview(h)
        h.owner.cancel(old); let next = try textReview(h, text: "Replacement")
        h.owner.cancel(old); XCTAssertNil(h.owner.claim(old)); XCTAssertEqual(h.owner.review?.id, next.id)
        XCTAssertTrue(h.owner.canConfirm(next)); XCTAssertEqual(h.wire.posts, 0)
    }
    func testSynchronousClaimBlocksDoubleTapAndOneCommandKeepsFreshRead() async throws {
        let h = try await setup(); defer { h.close() }; let review = try textReview(h)
        let claim = try XCTUnwrap(h.owner.claim(review)); XCTAssertNil(h.owner.claim(review)); XCTAssertNil(h.owner.capture())
        XCTAssertEqual(h.wire.posts, 0); await h.owner.execute(claim); await h.owner.execute(claim)
        XCTAssertEqual(h.wire.posts, 1); XCTAssertEqual(h.wire.reads, 2); XCTAssertEqual(h.model.projection?.revision, 3)
        XCTAssertEqual(h.model.receipt?.requestID, review.value.command.requestID)
    }
    func testQueuedOldClaimCannotClearNewVisitReview() async throws {
        let h = try await setup(); defer { h.close() }; let claim = try XCTUnwrap(h.owner.claim(try textReview(h)))
        h.owner.retire(); h.owner.appear(active: true); let next = try textReview(h, text: "New visit")
        await h.owner.execute(claim); XCTAssertEqual(h.owner.review?.id, next.id); XCTAssertEqual(h.wire.posts, 0)
    }
    func testOldDraftBindingAndGestureRejectAfterReturn() async throws {
        let h = try await setup(); defer { h.close() }; let old = try XCTUnwrap(h.owner.capture())
        h.owner.retire(); h.owner.appear(active: true)
        h.owner.setText("Late old field", nodeID: 701, ticket: old); h.owner.prepare(.hint(nodeID: 701), ticket: old)
        XCTAssertEqual(h.owner.text(nodeID: 701), ""); XCTAssertNil(h.owner.review)
    }
    func testBackgroundClearsInputAndForegroundRequiresFreshReview() async throws {
        let h = try await setup(); defer { h.close() }; let review = try textReview(h)
        h.owner.background(); XCTAssertNil(h.owner.review); XCTAssertEqual(h.owner.text(nodeID: 701), ""); XCTAssertNil(h.owner.capture())
        h.owner.sceneChanged(active: true); XCTAssertNil(h.owner.claim(review)); XCTAssertNotNil(h.owner.capture())
        XCTAssertEqual(h.owner.text(nodeID: 701), "")
    }
    func testAccountReplacementBeforeQueuedDispatchSendsNothing() async throws {
        let h = try await setup(); defer { h.close() }; let claim = try XCTUnwrap(h.owner.claim(try textReview(h)))
        h.session = try .init(accountID: 2, epoch: 2, namespace: "player-action-app-tests", token: "synthetic-token")
        await h.owner.execute(claim); XCTAssertEqual(h.wire.posts, 0); XCTAssertEqual(h.owner.text(nodeID: 701), "")
    }
    func testCurrentSnapshotChangeMakesReviewCancellableButNotSubmittable() async throws {
        let h = try await setup(); defer { h.close() }; let review = try textReview(h)
        h.wire.raw = h.wire.raw.replacingOccurrences(of: "Write a synthetic observation", with: "Updated prompt"); await h.model.load()
        XCTAssertFalse(h.owner.canConfirm(review)); XCTAssertNil(h.owner.claim(review)); h.owner.cancel(review)
        XCTAssertNotNil(h.owner.capture()); XCTAssertEqual(h.wire.posts, 0)
    }
    func testUnknownKeepsOriginalPendingAndDoesNotAutomaticallyRetry() async throws {
        let h = try await setup(); defer { h.close() }; h.wire.fail = true; let review = try textReview(h)
        let claim = try XCTUnwrap(h.owner.claim(review)); await h.owner.execute(claim); await h.owner.execute(claim)
        XCTAssertEqual(h.model.pending?.requestID, review.value.command.requestID); XCTAssertEqual(h.model.phase, "unknown")
        XCTAssertNil(h.owner.capture()); XCTAssertEqual(h.wire.posts, 1); XCTAssertEqual(h.wire.reads, 1)
    }
    func testOldNativeRootSynchronousAndQueuedCallbacksCannotRetireReplacement() async throws {
        let h = try await setup(); defer { h.close() }; let old = try XCTUnwrap(h.root)
        old.willMove(toParent: nil); old.view.removeFromSuperview(); old.removeFromParent(); old.viewDidDisappear(false)
        let fresh = PlayPlayerActionRootController(owner: h.owner); h.root = fresh; h.owner.attach(fresh)
        h.parent.addChild(fresh); h.parent.view.addSubview(fresh.view); fresh.didMove(toParent: h.parent); h.owner.appear(active: true)
        let review = try textReview(h, text: "New root"); old.viewDidDisappear(false)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(h.owner.review?.id, review.id); XCTAssertEqual(h.owner.text(nodeID: 701), "New root"); XCTAssertTrue(h.owner.canConfirm(review))
    }
    func testNativeDepartureClearsDraftAndInvalidatesPendingConfirmation() async throws {
        let h = try await setup(); defer { h.close() }; let review = try textReview(h)
        h.root.willMove(toParent: nil); h.root.view.removeFromSuperview(); h.root.removeFromParent(); h.root.viewDidDisappear(false)
        XCTAssertNil(h.owner.review); XCTAssertNil(h.owner.claim(review)); XCTAssertEqual(h.owner.text(nodeID: 701), ""); XCTAssertNil(h.owner.capture())
    }
    func testAttachedModalCoverDoesNotEraseCurrentReview() async throws {
        let h = try await setup(); defer { h.close() }; let review = try textReview(h)
        h.parent.present(UIViewController(), animated: false); h.owner.disappear()
        XCTAssertEqual(h.owner.review?.id, review.id); XCTAssertTrue(h.owner.canConfirm(review)); h.parent.dismiss(animated: false)
    }
    func testAllFiveActionCardsCanBeConstructedInBothLanguagesWithoutSending() async throws {
        for intent in [PlayPlayerReviewIntent.role, .text(nodeID: 701, answer: "Synthetic"), .choice(nodeID: 701, choiceID: "LEFT"), .hint(nodeID: 701), .reveal(nodeID: 701)] {
            let h = try Harness()
            if case .role = intent { h.wire.raw = h.wire.raw.replacingOccurrences(of: "\"confirmed\":true", with: "\"confirmed\":false") }
            await h.open(); defer { h.close() }; h.owner.prepare(intent, ticket: h.owner.capture()); let review = try XCTUnwrap(h.owner.review)
            for locale in ["en", "zh-Hans"] {
                let host = UIHostingController(rootView: List { PlayPlayerActionReviewCard(owner: h.owner, offered: review) }.environment(\.locale, Locale(identifier: locale)))
                XCTAssertGreaterThan(host.sizeThatFits(in: CGSize(width: 300, height: 20_000)).height, 0)
            }
            XCTAssertEqual(h.wire.posts, 0)
        }
    }
    func testNormalPlayerHostInitialAppearanceOwnsFirstReview() async throws {
        let h = try Harness(); await h.model.load()
        let host = UIHostingController(rootView: PlayPlayerSessionView(model: h.model).environment(\.scenePhase, .active))
        h.window.rootViewController = host; h.window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { h.window.isHidden = true; h.window.rootViewController = nil }
        func anchor(_ c: UIViewController) -> PlayPlayerActionRootController? {
            if let value = c as? PlayPlayerActionRootController { return value }; return c.children.compactMap { anchor($0) }.first
        }
        let deadline = Date().addingTimeInterval(2)
        while anchor(host)?.owner?.capture() == nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let owner = try XCTUnwrap(anchor(host)?.owner); owner.prepare(.choice(nodeID: 701, choiceID: "LEFT"), ticket: owner.capture())
        let review = try XCTUnwrap(owner.review); XCTAssertEqual(review.value.detail, "Synthetic left path"); XCTAssertTrue(owner.canConfirm(review))
        owner.cancel(review); XCTAssertEqual(h.wire.posts, 0)
    }
}
private final class PlayerActionAppWire: HTTPTransport {
    var raw = PlayExperienceSyntheticFixtures.player
    var posts = 0, reads = 0, fail = false
    @MainActor func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.httpMethod == "POST" {
            posts += 1; if fail { throw PlayExperienceError.unknownResult }
            let body = try JSONDecoder().decode(PlayWireValue.self, from: try XCTUnwrap(request.httpBody))
            raw = raw.replacingOccurrences(of: "\"revision\":2", with: "\"revision\":3")
            let receipt: PlayWireValue = .object(["activityId": .int(41), "requestId": body["requestId"], "action": body["action"], "outcome": .string("APPLIED"), "revision": .int(3), "receiptId": .int(1)])
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": receipt])), 200)
        }
        reads += 1; return (PlayExperienceSyntheticFixtures.envelope(raw), 200)
    }
}
