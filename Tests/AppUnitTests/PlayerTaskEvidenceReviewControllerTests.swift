import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Synthetic transport and captures only. UIHostingController cases are authored,
/// not substitutes for a future simulator or physical camera acceptance run.
@MainActor final class PlayerTaskEvidenceReviewControllerTests: XCTestCase {
    @MainActor private final class Harness {
        var session: PlayExperienceSession?
        let transport: EvidenceReviewAppTransport
        var model: PlayPlayerGameCoordinator!
        var device: PlayDeviceCaptureCoordinator!
        var owner: PlayerTaskEvidenceReviewController!
        var root: PlayerTaskEvidenceRootController!
        let parent = UIViewController(), window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        var bytes = Data([1]), uploads: [Data] = []
        init(kind: String) throws {
            session = try .init(accountID: 1, epoch: 1, namespace: "evidence-review-app-tests", token: "synthetic-token")
            transport = EvidenceReviewAppTransport(kind: kind)
            let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: [.reads, .playerCommands])
            model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { [weak self] in self?.session })
            let provider = PlaySyntheticDeviceProvider(supported: [.photo, .scan]) { [weak self] kind, _ in
                kind == .scan ? .scan("Captured + 中文") : .photo(self?.bytes ?? Data(), mimeType: "image/png")
            }
            device = PlayDeviceCaptureCoordinator(provider: provider, upload: { [weak self] bytes, _, _ in
                self?.uploads.append(bytes); return "https://example.test/issued-synthetic-photo"
            }, current: { [weak self] in
                guard let session = self?.session else { return nil }
                return try? .init(session: session, scope: .activity(41), nodeID: 701)
            })
        }
        func start() async throws {
            await model.load()
            owner = .init(target: try model.evidenceTarget(nodeID: 701), player: model, device: device)
            root = .init(owner: owner); owner.attach(root)
            window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(root); parent.view.addSubview(root.view); root.didMove(toParent: parent)
            owner.appear(active: true)
        }
        func close() {
            owner?.retire(); root?.willMove(toParent: nil); root?.view.removeFromSuperview(); root?.removeFromParent()
            window.isHidden = true; window.rootViewController = nil
        }
    }
    private func setup(_ kind: String = "SCAN") async throws -> Harness {
        let h = try Harness(kind: kind); try await h.start(); return h
    }
    func testCancelPreservesExactManualInputAndReopenFreezesTrimmedWireValue() async throws {
        let h = try await setup(); defer { h.close() }
        let ticket = h.owner.captureInput(); h.owner.updateManual("  A + / 中文  ", offered: ticket)
        h.owner.prepareManual(h.owner.manualText, offered: ticket); let first = try XCTUnwrap(h.owner.review)
        XCTAssertEqual(first.scan, "A + / 中文"); XCTAssertEqual(h.transport.posts, 0)
        h.owner.cancel(first); XCTAssertEqual(h.owner.manualText, "  A + / 中文  ")
        h.owner.prepareManual(h.owner.manualText, offered: h.owner.captureInput())
        let next = try XCTUnwrap(h.owner.review); XCTAssertNotEqual(first.id, next.id); XCTAssertEqual(first.scan, next.scan)
        h.owner.cancel(first); XCTAssertEqual(h.owner.review?.id, next.id)
    }
    func testConfirmationClaimsSynchronouslyAndSendsOnlyOnceThroughFreshRead() async throws {
        let h = try await setup(); defer { h.close() }
        h.owner.prepareManual("Synthetic", offered: h.owner.captureInput()); let review = try XCTUnwrap(h.owner.review)
        let claim = try XCTUnwrap(h.owner.claim(review)); XCTAssertNil(h.owner.claim(review)); XCTAssertEqual(h.transport.posts, 0)
        let submitted = await h.owner.execute(claim); XCTAssertTrue(submitted)
        let duplicate = await h.owner.execute(claim); XCTAssertFalse(duplicate)
        XCTAssertEqual(h.transport.posts, 1); XCTAssertEqual(h.transport.reads, 2); XCTAssertEqual(h.model.projection?.revision, 3)
    }
    func testQueuedConfirmAfterExitAndReopenCannotBorrowNewVisit() async throws {
        let h = try await setup(); defer { h.close() }
        h.owner.prepareManual("Synthetic", offered: h.owner.captureInput()); let claim = try XCTUnwrap(h.owner.claim(try XCTUnwrap(h.owner.review)))
        h.owner.retire(); h.owner.appear(active: true)
        let sent = await h.owner.execute(claim); XCTAssertFalse(sent); XCTAssertEqual(h.transport.posts, 0)
    }
    func testOldKeyboardAndCaptureTicketCannotWriteOrCaptureAfterReopen() async throws {
        let h = try await setup(); defer { h.close() }; let ticket = h.owner.captureInput()
        h.owner.updateManual("Old input", offered: ticket); h.owner.retire(); h.owner.appear(active: true)
        h.owner.updateManual("Late keyboard", offered: ticket); await h.owner.captureDevice(.scan, offered: ticket)
        XCTAssertEqual(h.owner.manualText, ""); XCTAssertNil(h.device.output)
        h.owner.prepareManual("Old gesture", offered: ticket); XCTAssertNil(h.owner.review)
    }
    func testAccountReplacementBetweenClaimAndExecuteNeverPosts() async throws {
        let h = try await setup(); defer { h.close() }
        h.owner.prepareManual("Synthetic", offered: h.owner.captureInput()); let claim = try XCTUnwrap(h.owner.claim(try XCTUnwrap(h.owner.review)))
        h.session = try .init(accountID: 2, epoch: 2, namespace: "evidence-review-app-tests", token: "synthetic-token")
        let sent = await h.owner.execute(claim); XCTAssertFalse(sent); XCTAssertEqual(h.transport.posts, 0)
    }
    func testChangedProjectionBeforeClaimLeavesExpiredReviewOnlyCancellable() async throws {
        let h = try await setup(); defer { h.close() }
        h.owner.prepareManual("Synthetic", offered: h.owner.captureInput()); let review = try XCTUnwrap(h.owner.review)
        h.transport.projection = h.transport.projection.replacingOccurrences(of: "Write a synthetic observation", with: "Changed prompt")
        await h.model.load(); XCTAssertFalse(h.owner.canConfirm(review)); XCTAssertNil(h.owner.claim(review))
        h.owner.cancel(review); XCTAssertNotNil(h.owner.captureInput()); XCTAssertEqual(h.transport.posts, 0)
    }
    func testUnknownAttemptRetainsExistingPendingAndNeverCreatesSecondRequest() async throws {
        let h = try await setup(); defer { h.close() }; h.transport.fail = true
        h.owner.prepareManual("Synthetic", offered: h.owner.captureInput()); let claim = try XCTUnwrap(h.owner.claim(try XCTUnwrap(h.owner.review)))
        _ = await h.owner.execute(claim); let request = try XCTUnwrap(h.model.pending?.requestID)
        _ = await h.owner.execute(claim); h.owner.prepareManual("Second", offered: h.owner.captureInput())
        XCTAssertEqual(h.transport.posts, 1); XCTAssertEqual(h.model.phase, "unknown"); XCTAssertEqual(h.model.pending?.requestID, request)
        XCTAssertNil(h.owner.review)
    }
    func testCapturedScanReviewPinsOutputIDAndExactDisplayedContents() async throws {
        let h = try await setup(); defer { h.close() }
        await h.owner.captureDevice(.scan, offered: h.owner.captureInput()); let output = try XCTUnwrap(h.device.outputID)
        h.owner.prepareCapturedScan(outputID: output, offered: h.owner.captureInput()); let review = try XCTUnwrap(h.owner.review)
        XCTAssertEqual(review.outputID, output); XCTAssertEqual(review.scan, "Captured + 中文"); XCTAssertEqual(h.transport.posts, 0)
        h.owner.cancel(review); XCTAssertEqual(h.device.outputID, output)
    }
    func testCancelledPhotoUploadKeepsCaptureWithoutUploading() async throws {
        let h = try await setup("PHOTO"); defer { h.close() }
        await h.owner.captureDevice(.photo, offered: h.owner.captureInput()); let output = try XCTUnwrap(h.device.outputID)
        h.owner.prepareUpload(outputID: output, offered: h.owner.captureInput()); let review = try XCTUnwrap(h.owner.review)
        XCTAssertEqual(review.photo, Data([1])); h.owner.cancel(review)
        XCTAssertEqual(h.device.outputID, output); XCTAssertTrue(h.uploads.isEmpty); XCTAssertNil(h.device.uploadedPhoto)
    }
    func testReplacementPhotoBetweenClaimAndExecuteCannotUploadDifferentBytes() async throws {
        let h = try await setup("PHOTO"); defer { h.close() }
        await h.owner.captureDevice(.photo, offered: h.owner.captureInput()); let old = try XCTUnwrap(h.device.outputID)
        h.owner.prepareUpload(outputID: old, offered: h.owner.captureInput()); let claim = try XCTUnwrap(h.owner.claim(try XCTUnwrap(h.owner.review)))
        h.bytes = Data([2]); await h.device.capture(.photo)
        let sent = await h.owner.execute(claim); XCTAssertFalse(sent); XCTAssertTrue(h.uploads.isEmpty)
        XCTAssertNotEqual(h.device.outputID, old)
    }
    func testUploadAndTaskSubmissionRemainSeparateExplicitConfirmations() async throws {
        let h = try await setup("PHOTO"); defer { h.close() }
        await h.owner.captureDevice(.photo, offered: h.owner.captureInput()); let output = try XCTUnwrap(h.device.outputID)
        h.owner.prepareUpload(outputID: output, offered: h.owner.captureInput()); let upload = try XCTUnwrap(h.owner.claim(try XCTUnwrap(h.owner.review)))
        let uploadedOnly = await h.owner.execute(upload); XCTAssertFalse(uploadedOnly)
        XCTAssertEqual(h.uploads, [Data([1])]); XCTAssertEqual(h.transport.posts, 0); XCTAssertEqual(h.device.outputID, output)
        h.owner.prepareUploadedPhoto(outputID: output, offered: h.owner.captureInput()); let review = try XCTUnwrap(h.owner.review)
        guard case .submit(let prepared) = review.action else { return XCTFail("Missing explicit submission review") }
        XCTAssertEqual(prepared.command.payload["evidenceUrls"]?.array?.first?.text, "https://example.test/issued-synthetic-photo")
        let sent = await h.owner.execute(try XCTUnwrap(h.owner.claim(review))); XCTAssertTrue(sent)
        XCTAssertEqual(h.transport.posts, 1); XCTAssertEqual(h.transport.reads, 2)
    }
    func testNativeParentDepartureClearsMemoryAndCancelsQueuedWork() async throws {
        let h = try await setup(); defer { h.close() }
        h.owner.updateManual("Sensitive synthetic input", offered: h.owner.captureInput())
        h.owner.prepareManual(h.owner.manualText, offered: h.owner.captureInput()); let claim = try XCTUnwrap(h.owner.claim(try XCTUnwrap(h.owner.review)))
        h.root.willMove(toParent: nil); h.root.view.removeFromSuperview(); h.root.removeFromParent(); h.root.viewDidDisappear(false)
        XCTAssertEqual(h.owner.manualText, ""); XCTAssertNil(h.owner.review); XCTAssertNil(h.owner.captureInput())
        let sent = await h.owner.execute(claim); XCTAssertFalse(sent); XCTAssertEqual(h.transport.posts, 0)
    }
    func testAttachedCameraCoverDoesNotRetireVisibleInputVisit() async throws {
        let h = try await setup(); defer { h.close() }
        h.owner.updateManual("Synthetic preserved", offered: h.owner.captureInput())
        h.parent.present(UIViewController(), animated: false); h.owner.disappear()
        XCTAssertEqual(h.owner.manualText, "Synthetic preserved"); XCTAssertNotNil(h.owner.captureInput())
        h.parent.dismiss(animated: false)
    }
    func testNormalHostInitialAppearanceEnablesExactInPageReview() async throws {
        let h = try Harness(kind: "SCAN"); await h.model.load(); let target = try h.model.evidenceTarget(nodeID: 701)
        let host = UIHostingController(rootView: PlayerTaskEvidenceView(target: target, player: h.model, device: h.device).environment(\.scenePhase, .active))
        h.window.rootViewController = host; h.window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { h.window.isHidden = true; h.window.rootViewController = nil }
        func anchor(_ root: UIViewController) -> PlayerTaskEvidenceRootController? {
            if let value = root as? PlayerTaskEvidenceRootController { return value }
            return root.children.compactMap { anchor($0) }.first
        }
        let deadline = Date().addingTimeInterval(2)
        while anchor(host)?.owner?.captureInput() == nil && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let owner = try XCTUnwrap(anchor(host)?.owner); let ticket = try XCTUnwrap(owner.captureInput())
        owner.updateManual("First render", offered: ticket); owner.prepareManual(owner.manualText, offered: ticket)
        let review = try XCTUnwrap(owner.review); XCTAssertEqual(review.scan, "First render"); XCTAssertTrue(owner.canConfirm(review))
        XCTAssertEqual(h.transport.posts, 0); owner.cancel(review); XCTAssertEqual(owner.manualText, "First render")
    }

    func testOldRootSynchronousDisappearanceCannotRetireReplacementRoot() async throws {
        let h = try await setup(); defer { h.close() }; let old = try XCTUnwrap(h.root)
        old.willMove(toParent: nil); old.view.removeFromSuperview(); old.removeFromParent()
        let fresh = PlayerTaskEvidenceRootController(owner: h.owner); h.root = fresh; h.owner.attach(fresh)
        h.parent.addChild(fresh); h.parent.view.addSubview(fresh.view); fresh.didMove(toParent: h.parent)
        h.owner.appear(active: true); h.owner.updateManual("New visit input", offered: h.owner.captureInput())
        h.owner.prepareManual(h.owner.manualText, offered: h.owner.captureInput()); let review = try XCTUnwrap(h.owner.review)
        old.viewDidDisappear(false)
        XCTAssertEqual(h.owner.manualText, "New visit input"); XCTAssertEqual(h.owner.review?.id, review.id)
        XCTAssertTrue(h.owner.canConfirm(review))
    }
    func testAlreadyQueuedOldRootCallbackCannotClearNewRootInputOrCapture() async throws {
        let h = try await setup(); defer { h.close() }; let old = try XCTUnwrap(h.root)
        old.willMove(toParent: nil); old.view.removeFromSuperview(); old.removeFromParent()
        old.viewDidDisappear(false)
        let fresh = PlayerTaskEvidenceRootController(owner: h.owner); h.root = fresh; h.owner.attach(fresh)
        h.parent.addChild(fresh); h.parent.view.addSubview(fresh.view); fresh.didMove(toParent: h.parent)
        h.owner.appear(active: true); h.owner.updateManual("Replacement input", offered: h.owner.captureInput())
        await h.owner.captureDevice(.scan, offered: h.owner.captureInput())
        let output = try XCTUnwrap(h.device.outputID)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(h.owner.manualText, "Replacement input"); XCTAssertEqual(h.device.outputID, output)
        XCTAssertNotNil(h.owner.captureInput())
    }

}

private final class EvidenceReviewAppTransport: HTTPTransport {
    var projection: String
    var reads = 0, posts = 0
    var fail = false
    init(kind: String) { projection = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"\(kind)\"") }
    @MainActor func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.httpMethod == "POST" {
            posts += 1; if fail { throw PlayExperienceError.unknownResult }
            let body = try JSONDecoder().decode(PlayWireValue.self, from: try XCTUnwrap(request.httpBody))
            projection = projection.replacingOccurrences(of: "\"revision\":2", with: "\"revision\":3")
            let receipt: PlayWireValue = .object(["activityId": .int(41), "requestId": body["requestId"], "action": body["action"], "outcome": .string("APPLIED"), "revision": .int(3), "receiptId": .int(1), "result": .object([:])])
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": receipt])), 200)
        }
        reads += 1; return (PlayExperienceSyntheticFixtures.envelope(projection), 200)
    }
}
