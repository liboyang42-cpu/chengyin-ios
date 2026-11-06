import XCTest
@testable import QuestifyCore

/// New regression source only; real service with synthetic HTTP, no real install or server grant.
/// Existing WorkshopPaidTextFixture is reused read-only. No old fixture or assertion is changed.
@MainActor final class WorkshopPaidInstalledTextRejectionRecoveryTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], delay = false
        var failure: Error?
        var response: (Data,Int)
        var suspended: CheckedContinuation<(Data,Int),Never>?
        init() throws { response = (try WorkshopPaidTextFixture.envelope(),200) }
        func send(_ request: URLRequest) async throws -> (Data,Int) { requests.append(request); if let failure { throw failure }; if delay { delay = false; return await withCheckedContinuation { suspended = $0 } }; return response }
        func wait() async { for _ in 0..<1000 { if suspended != nil { return }; await Task.yield() }; XCTFail("Expected suspended real service transport") }
        func resume(_ value: (Data,Int)) { let old = suspended; suspended = nil; old?.resume(returning:value) }
    }
    @MainActor private final class Harness {
        let context: RuntimeDependencyContext, wire: Wire, reference: WorkshopPaidInstalledTextReference
        var current: RuntimeDependencyContext?, approval: WorkshopPaidInstalledTextApproval?, unauthorized = 0
        lazy var lease = ContentDraftSessionLease(context: context, current: { [weak self] in self?.current })
        lazy var service = WorkshopPaidInstalledTextService(api: try! APIConfiguration(baseURL: context.baseURL), transport: wire, lease: lease, approval: approval, currentApproval: { [weak self] in self?.approval }, onUnauthorized: { [weak self] _ in self?.unauthorized += 1 })
        lazy var controller = WorkshopPaidInstalledTextController(reference: reference, service: service, lease: lease)
        init(approved: Bool = true) throws {
            context = .init(market: .china, baseURL: URL(string: "https://example.com/native")!, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-test-7", role: "player"))
            current = context; wire = try Wire(); reference = try WorkshopPaidTextFixture.reference()
            approval = approved ? try .init(context: context, expiresAt: .distantFuture) : nil
        }
        func read(_ a: WorkshopPaidInstalledTextAppearance) async throws { await (try XCTUnwrap(controller.appear(a)))() }
    }

    func testCurrentHTTPAndEnvelope401RetirePresentationAndLease() async throws {
        for envelope in [false, true] {
            let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
            let reference = h.reference
            h.wire.response = envelope ? (try WorkshopPaidTextFixture.data(["code": 401]), 200) : (Data(), 401)
            try await h.read(appearance)
            XCTAssertEqual(h.controller.phase, .invalidated)
            XCTAssertEqual(h.controller.issue, .unauthorized)
            XCTAssertNil(h.controller.content)
            XCTAssertFalse(h.lease.isCurrent)
            XCTAssertEqual(h.unauthorized, 1)
            XCTAssertNil(h.controller.offerReload(appearance))
            XCTAssertNil(h.controller.appear(.init()))
            XCTAssertEqual(h.wire.requests.count, 1)
            XCTAssertEqual(h.controller.reference, reference)
        }
    }

    func testMissingApprovalRetiresWithoutSending() async throws {
        let h = try Harness(approved: false), appearance = WorkshopPaidInstalledTextAppearance()
        try await h.read(appearance)
        XCTAssertEqual(h.controller.phase, .invalidated)
        XCTAssertEqual(h.controller.issue, .disabled)
        XCTAssertNil(h.controller.offerReload(appearance))
        XCTAssertNil(h.controller.content)
        XCTAssertFalse(h.lease.isCurrent)
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertEqual(h.unauthorized, 0)
    }

    func testWithdrawnApprovalDuringReadRetiresWithoutExposingLateBody() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        h.wire.delay = true
        let action = try XCTUnwrap(h.controller.appear(appearance))
        let task = Task { await action() }; await h.wire.wait()
        h.approval = nil
        h.wire.resume((try WorkshopPaidTextFixture.envelope(), 200)); await task.value
        XCTAssertEqual(h.controller.phase, .invalidated)
        XCTAssertEqual(h.controller.issue, .disabled)
        XCTAssertNil(h.controller.content)
        XCTAssertFalse(h.lease.isCurrent)
        XCTAssertNil(h.controller.offerReload(appearance))
        XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.unauthorized, 0)
    }

    func testNonAuthorityServerFailureRemainsExplicitlyRetryable() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        h.wire.response = (Data(), 503)
        try await h.read(appearance)
        XCTAssertEqual(h.controller.phase, .unavailable)
        XCTAssertEqual(h.controller.issue, .unavailable)
        XCTAssertTrue(h.lease.isCurrent)
        XCTAssertNil(h.controller.content)
        let original = try XCTUnwrap(h.wire.requests.first)
        h.wire.response = (try WorkshopPaidTextFixture.envelope(), 200)
        await (try XCTUnwrap(h.controller.offerReload(appearance)))()
        XCTAssertEqual(h.controller.phase, .loaded)
        XCTAssertNotNil(h.controller.content)
        XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertEqual(h.wire.requests.last?.httpBody, original.httpBody)
        XCTAssertEqual(h.wire.requests.last?.url, original.url)
        XCTAssertEqual(h.unauthorized, 0)
    }

    func testTransportTimeoutDoesNotRevokeAndRetryKeepsOriginalRequest() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        h.wire.failure = URLError(.timedOut)
        try await h.read(appearance)
        XCTAssertEqual(h.controller.phase, .unavailable)
        XCTAssertEqual(h.controller.issue, .unavailable)
        XCTAssertTrue(h.lease.isCurrent)
        XCTAssertEqual(h.unauthorized, 0)
        let original = try XCTUnwrap(h.wire.requests.first)
        h.wire.failure = nil
        await (try XCTUnwrap(h.controller.offerReload(appearance)))()
        XCTAssertEqual(h.controller.phase, .loaded)
        XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertEqual(h.wire.requests.last?.httpBody, original.httpBody)
        XCTAssertEqual(h.wire.requests.last?.url, original.url)
    }

    func testMalformedSuccessDoesNotInventRevocationOrInstallation() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        h.wire.response = (Data("{}".utf8), 200)
        try await h.read(appearance)
        XCTAssertEqual(h.controller.phase, .unavailable)
        XCTAssertEqual(h.controller.issue, .malformed)
        XCTAssertTrue(h.lease.isCurrent)
        XCTAssertNil(h.controller.content)
        XCTAssertNotNil(h.controller.offerReload(appearance))
        XCTAssertEqual(h.controller.reference, h.reference)
        XCTAssertEqual(h.unauthorized, 0)
    }

    func testOld401CannotRetireNewForegroundRead() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        h.wire.delay = true
        let old = try XCTUnwrap(h.controller.appear(appearance))
        let task = Task { await old() }; await h.wire.wait()
        h.controller.suspend(appearance)
        await (try XCTUnwrap(h.controller.resume(appearance)))()
        XCTAssertEqual(h.controller.phase, .loaded)
        h.wire.resume((Data(), 401)); await task.value
        XCTAssertEqual(h.controller.phase, .loaded)
        XCTAssertNotNil(h.controller.content)
        XCTAssertTrue(h.lease.isCurrent)
        XCTAssertEqual(h.unauthorized, 0)
        XCTAssertEqual(h.wire.requests.count, 2)
    }

    func testFreshRevalidationCanReadSameOriginalReferenceAfterRetirement() async throws {
        let old = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        old.wire.response = (Data(), 401); try await old.read(appearance)
        XCTAssertEqual(old.controller.phase, .invalidated)
        let fresh = try Harness()
        XCTAssertEqual(fresh.reference, old.reference)
        try await fresh.read(.init())
        XCTAssertEqual(fresh.controller.phase, .loaded)
        XCTAssertEqual(fresh.controller.reference, old.reference)
        XCTAssertNotNil(fresh.controller.content)
        XCTAssertEqual(fresh.wire.requests.count, 1)
        XCTAssertEqual(fresh.wire.requests.first?.url, old.wire.requests.first?.url)
        XCTAssertEqual(fresh.wire.requests.first?.httpBody, old.wire.requests.first?.httpBody)
        XCTAssertNil(old.controller.offerReload(appearance))
    }
}
