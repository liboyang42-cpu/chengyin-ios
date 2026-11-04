import XCTest
@testable import Questify

@MainActor final class PlayOperatingSummaryPresentationTests: XCTestCase {
    func testInactivePageDoesNotReadAndRetirementClearsVerifiedDisplay() async throws {
        let h = try Harness(); await h.read(); XCTAssertTrue(h.wire.requests.isEmpty)
        h.page.activate(); await h.read(); XCTAssertEqual(h.display?.tags.first?.value, "Current")
        h.page.retire(); XCTAssertNil(h.display); XCTAssertNil(h.page.summary)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testFailedRefreshNeverReusesRetainedCoordinatorSummary() async throws {
        for (status, code) in [(403, 403), (200, 403), (401, 401), (503, 503)] {
            let h = try Harness(); h.page.activate(); await h.read()
            XCTAssertNotNil(h.display); h.wire.nextFailure = (status, code); await h.read()
            XCTAssertNil(h.display); XCTAssertNil(h.page.summary)
            XCTAssertNotNil(h.model.summary) // Proves the UI owner, not an implicit Core clear, hides it.
            XCTAssertEqual(h.wire.requests.count, 2)
        }
    }
    func testBackgroundCancellationRejectsLatePrivateReply() async throws {
        let h = try Harness(); h.page.activate(); h.wire.suspendNext = true
        let work = Task { await h.read() }; await h.wire.waitForPending()
        h.page.retire(); h.wire.resume(tag: "Late private value"); await work.value
        XCTAssertNil(h.display); XCTAssertNil(h.page.summary); XCTAssertFalse(h.page.loading)
    }
    func testAccountSwitchDuringReadDoesNotPublishOldAccount() async throws {
        let h = try Harness(); h.page.activate(); h.wire.suspendNext = true
        let work = Task { await h.read() }; await h.wire.waitForPending()
        h.identity.session = try .init(accountID: 8, epoch: 2, namespace: "summary-test", token: "new-synthetic")
        h.wire.resume(tag: "Old account"); await work.value
        XCTAssertNil(h.display); XCTAssertEqual(h.model.phase, "stale")
    }
    func testSourceRevocationHidesExistingDisplayWithoutAnotherRequest() async throws {
        let h = try Harness(); h.page.activate(); await h.read(); XCTAssertNotNil(h.display)
        h.allowed = false; XCTAssertNil(h.display); await h.read()
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testNewerReadCannotBeOverwrittenByCancelledOlderReply() async throws {
        let h = try Harness(); h.page.activate(); h.wire.suspendNext = true
        let old = Task { await h.read() }; await h.wire.waitForPending()
        h.wire.tag = "New current value"; await h.read()
        XCTAssertEqual(h.display?.tags.first?.value, "New current value")
        h.wire.resume(tag: "Late old value"); await old.value
        XCTAssertEqual(h.display?.tags.first?.value, "New current value")
        XCTAssertEqual(h.model.summary?.tags.first?.value, "New current value")
    }
    func testReviewIsOneShotAndUnknownReadbackCannotResendRevocation() async throws {
        let h = try Harness(); h.page.activate(); await h.read(); h.prepare()
        let review = try XCTUnwrap(h.page.review)
        await h.revoke(review); await h.revoke(review)
        XCTAssertEqual(h.wire.posts, 1); XCTAssertEqual(h.model.unresolvedTagIDs, [81])
        XCTAssertEqual(h.model.phase, "unknown"); h.prepare(); XCTAssertNil(h.page.review)
    }
    func testCancelledWritePreservesUnknownUntilOriginalReadbackResolvesIt() async throws {
        let h = try Harness(); h.page.activate(); await h.read(); h.prepare()
        let review = try XCTUnwrap(h.page.review); h.wire.suspendNext = true
        let work = Task { await h.revoke(review) }; await h.wire.waitForPending()
        h.page.retire(); h.wire.resume(post: true); await work.value
        XCTAssertEqual(h.model.unresolvedTagIDs, [81]); XCTAssertNil(h.display)
        h.page.activate(); await h.read(); h.prepare(); XCTAssertNil(h.page.review)
        XCTAssertEqual(h.wire.posts, 1); XCTAssertEqual(h.model.unresolvedTagIDs, [81])
        h.wire.revoked = true; await h.read()
        XCTAssertTrue(h.model.unresolvedTagIDs.isEmpty); XCTAssertTrue(h.display?.tags.first?.revoked == true)
        XCTAssertEqual(h.wire.posts, 1)
    }
    func testReviewExpiresOnRefreshRetirementAndChangedSource() async throws {
        let h = try Harness(); h.page.activate(); await h.read(); h.prepare()
        let review = try XCTUnwrap(h.page.review)
        h.allowed = false; await h.revoke(review); XCTAssertEqual(h.wire.posts, 0)
        XCTAssertNil(h.page.review)
        h.allowed = true; await h.revoke(review); XCTAssertEqual(h.wire.posts, 0)
        await h.read(); await h.revoke(review); XCTAssertEqual(h.wire.posts, 0)
        h.prepare(); let next = try XCTUnwrap(h.page.review); h.page.retire()
        await h.revoke(next); XCTAssertEqual(h.wire.posts, 0)
    }
    func testMissingOriginalTagCapabilityNeverDispatchesWrite() async throws {
        let h = try Harness(tags: false); h.page.activate(); await h.read(); h.prepare()
        await h.revoke(try XCTUnwrap(h.page.review))
        XCTAssertEqual(h.wire.posts, 0); XCTAssertEqual(h.model.issue, .disabled)
        XCTAssertNil(h.display)
    }
    func testUncompletedNormalRouteRetainsExistingSummaryEligibility() async throws {
        let h = try Harness(); await h.runtime.load()
        XCTAssertEqual(h.runtime.snapshot?.availability, .active)
        let source = try XCTUnwrap(PlayOperatingSummarySource(runtime: h.runtime, summary: h.model))
        XCTAssertTrue(source.accepts(h.runtime, summary: h.model, currentSummary: { h.model }))
        XCTAssertFalse(source.accepts(h.runtime, summary: h.model, currentSummary: { h.makeSummary() }))
    }
    func testEqualSnapshotRefreshAndAccountChangeRetireCapturedSource() async throws {
        let h = try Harness(); await h.runtime.load()
        let source = try XCTUnwrap(PlayOperatingSummarySource(runtime: h.runtime, summary: h.model))
        let before = h.runtime.snapshot; await h.runtime.load()
        XCTAssertEqual(h.runtime.snapshot, before)
        XCTAssertFalse(source.accepts(h.runtime, summary: h.model, currentSummary: { h.model }))
        let fresh = try XCTUnwrap(PlayOperatingSummarySource(runtime: h.runtime, summary: h.model))
        h.identity.session = nil
        XCTAssertFalse(fresh.accepts(h.runtime, summary: h.model, currentSummary: { h.model }))
    }
    @MainActor private final class Identity {
        var session: PlayExperienceSession?
        init() throws { session = try .init(accountID: 7, epoch: 1, namespace: "summary-test", token: "synthetic-only") }
    }
    @MainActor private final class Harness {
        let identity: Identity, service: PlayExperienceService
        let wire: Wire
        let page = PlayOperatingSummaryPresentation()
        var allowed = true
        lazy var model = makeSummary()
        lazy var runtime = PlayExperienceCoordinator(scope: .topic(71), service: service,
            recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(),
            currentSession: { [identity] in identity.session })
        init(tags: Bool = true) throws {
            let wire = Wire()
            self.wire = wire; identity = try Identity()
            service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!),
                transport: wire, enabled: tags ? [.reads, .tags] : [.reads])
        }
        func makeSummary() -> PlayOperatingSummaryCoordinator {
            .init(topicID: 71, service: service, currentSession: { [identity] in identity.session })
        }
        var display: PlayOperatingSummary? { page.displayedSummary(model: model, current: { self.allowed }) }
        func read() async { await page.load(model: model, current: { self.allowed }) }
        func prepare() { page.prepareRevocation(tagID: 81, model: model, current: { self.allowed }) }
        func revoke(_ review: PlayOperatingSummaryPresentation.Revocation) async {
            await page.revoke(review, model: model, current: { self.allowed })
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var tag = "Current", revoked = false, suspendNext = false
        var nextFailure: (Int, Int)?
        var posts: Int { requests.filter { $0.httpMethod == "POST" }.count }
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var waiter: CheckedContinuation<Void, Never>?
        func waitForPending() async {
            if pending != nil { return }
            await withCheckedContinuation { waiter = $0 }
        }
        func resume(tag: String = "Current", post: Bool = false) {
            let work = pending; pending = nil; work?.resume(returning: (payload(tag: tag, post: post), 200))
        }
        private func payload(tag: String, post: Bool) -> Data {
            let data: [String: Any] = post ? ["id": 81, "status": "REVOKED"] :
                ["topicId": 71, "tags": [["id": 81, "tagValue": tag, "status": revoked ? "REVOKED" : "ACTIVE"]]]
            return try! JSONSerialization.data(withJSONObject: ["code": 200, "data": data])
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path == "/api/play/nodes" {
                return (Data(#"{"code":200,"data":{"topicId":71,"mode":1,"playable":true,"registered":true,"nodes":[{"nodeId":701,"name":"Question","done":false,"validationMethod":6}]}}"#.utf8), 200)
            }
            XCTAssertTrue(["/api/play/os/71", "/api/play/tag/81/revoke"].contains(request.url?.path ?? ""))
            if request.httpMethod == "POST" { XCTAssertEqual(request.url?.path, "/api/play/tag/81/revoke"); XCTAssertNil(request.httpBody) }
            if suspendNext {
                suspendNext = false
                return try await withCheckedThrowingContinuation { pending = $0; waiter?.resume(); waiter = nil }
            }
            if let (status, code) = nextFailure {
                nextFailure = nil
                return (try JSONSerialization.data(withJSONObject: ["code": code]), status)
            }
            return (payload(tag: tag, post: request.httpMethod == "POST"), 200)
        }
    }
}
