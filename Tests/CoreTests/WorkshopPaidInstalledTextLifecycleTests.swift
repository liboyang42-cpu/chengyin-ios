import XCTest
@testable import QuestifyCore

// Original transport and harness copied byte-for-byte from WorkshopPaidInstalledTextTests.
// Shared payloads remain in the unchanged WorkshopPaidTextFixture; no new API or body schema.
@MainActor final class WorkshopPaidInstalledTextLifecycleTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], delay = false
        var response: (Data,Int)
        var suspended: CheckedContinuation<(Data,Int),Never>?
        init() throws { response = (try WorkshopPaidTextFixture.envelope(),200) }
        func send(_ request: URLRequest) async throws -> (Data,Int) { requests.append(request); if delay { delay = false; return await withCheckedContinuation { suspended = $0 } }; return response }
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

    func testBackgroundClearsBodyAndForegroundReadsSameOriginalReference() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        try await h.read(appearance)
        let reference = h.controller.reference, request = try XCTUnwrap(h.wire.requests.first)
        XCTAssertNotNil(h.controller.content)
        h.controller.suspend(appearance)
        XCTAssertNil(h.controller.content); XCTAssertEqual(h.controller.phase, .idle)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.controller.reference, reference)
        XCTAssertFalse(h.controller.refreshVisiblePermission(appearance))
        await (try XCTUnwrap(h.controller.resume(appearance)))()
        XCTAssertEqual(h.controller.phase, .loaded)
        XCTAssertEqual(h.controller.content?.sourceJSON, WorkshopPaidTextFixture.source)
        XCTAssertEqual(h.controller.reference, reference); XCTAssertEqual(h.wire.requests.count, 2)
        let resumed = try XCTUnwrap(h.wire.requests.last)
        XCTAssertEqual(resumed.url, request.url); XCTAssertEqual(resumed.httpBody, request.httpBody)
    }

    func testBackgroundRetiresQueuedProtectedReadBeforeDispatch() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        let queued = try XCTUnwrap(h.controller.appear(appearance))
        h.controller.suspend(appearance); await queued()
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(h.controller.content)
        XCTAssertNil(h.controller.offerReload(appearance))
        await (try XCTUnwrap(h.controller.resume(appearance)))()
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.controller.phase, .loaded)
    }

    func testLateBackgroundSuccessOr401CannotReplaceForegroundBody() async throws {
        for late401 in [false, true] {
            let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
            h.wire.delay = true
            let action = try XCTUnwrap(h.controller.appear(appearance))
            let task = Task { await action() }; await h.wire.wait()
            h.controller.suspend(appearance); XCTAssertNil(h.controller.content)
            await (try XCTUnwrap(h.controller.resume(appearance)))()
            XCTAssertEqual(h.controller.phase, .loaded)
            let current = h.controller.content, count = h.wire.requests.count
            h.wire.resume(late401 ? (Data(), 401) : (try WorkshopPaidTextFixture.envelope(), 200))
            await task.value
            XCTAssertEqual(h.unauthorized, 0); XCTAssertEqual(h.wire.requests.count, count)
            XCTAssertEqual(h.controller.phase, .loaded)
            XCTAssertEqual(h.controller.content?.sourceJSON, current?.sourceJSON)
            XCTAssertEqual(h.controller.reference, h.reference)
        }
    }

    func testLocalRevokedOrReissuedGrantClearsVisibleBodyWithoutNetwork() async throws {
        for reissued in [false, true] {
            let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
            try await h.read(appearance); let count = h.wire.requests.count
            h.approval = reissued ? try .init(context: h.context, expiresAt: .distantFuture) : nil
            XCTAssertFalse(h.controller.refreshVisiblePermission(appearance))
            XCTAssertNil(h.controller.content); XCTAssertEqual(h.controller.phase, .invalidated)
            XCTAssertEqual(h.controller.issue, .disabled); XCTAssertEqual(h.wire.requests.count, count)
            XCTAssertEqual(h.controller.reference, h.reference)
            XCTAssertNil(h.controller.resume(appearance)); XCTAssertNil(h.controller.appear(.init()))
        }
    }

    func testVisibleGrantExpiryClearsBodyUsingOnlyInjectedLocalClock() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        var instant = Date(timeIntervalSince1970: 100)
        h.approval = try .init(context: h.context, expiresAt: Date(timeIntervalSince1970: 101))
        let service = WorkshopPaidInstalledTextService(api: try APIConfiguration(baseURL: h.context.baseURL),
            transport: h.wire, lease: h.lease, approval: h.approval, currentApproval: { h.approval },
            now: { instant }, onUnauthorized: { _ in XCTFail("Local expiry cannot expire another session through HTTP") })
        let controller = WorkshopPaidInstalledTextController(reference: h.reference, service: service, lease: h.lease)
        await (try XCTUnwrap(controller.appear(appearance)))()
        XCTAssertEqual(controller.phase, .loaded); XCTAssertNotNil(controller.content)
        let count = h.wire.requests.count
        instant = Date(timeIntervalSince1970: 101)
        XCTAssertFalse(controller.refreshVisiblePermission(appearance))
        XCTAssertNil(controller.content); XCTAssertEqual(controller.phase, .invalidated)
        XCTAssertEqual(controller.issue, .disabled); XCTAssertEqual(h.wire.requests.count, count)
        XCTAssertEqual(controller.reference, h.reference)
    }

    func testValidVisiblePermissionChecksNeverFetchOrChangeBody() async throws {
        let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
        try await h.read(appearance)
        let count = h.wire.requests.count, source = h.controller.content?.sourceJSON
        for _ in 0..<3 { XCTAssertTrue(h.controller.refreshVisiblePermission(appearance)) }
        XCTAssertEqual(h.wire.requests.count, count); XCTAssertEqual(h.controller.phase, .loaded)
        XCTAssertEqual(h.controller.content?.sourceJSON, source)
    }

    func testClosedOrReplacedOwnerCannotResumeSuspendedBody() async throws {
        for ownerChanged in [false, true] {
            let h = try Harness(), appearance = WorkshopPaidInstalledTextAppearance()
            try await h.read(appearance); let count = h.wire.requests.count
            h.controller.suspend(appearance)
            if ownerChanged { h.current = nil } else { h.controller.close(appearance) }
            XCTAssertNil(h.controller.resume(appearance)); XCTAssertNil(h.controller.content)
            XCTAssertFalse(h.controller.refreshVisiblePermission(appearance))
            XCTAssertEqual(h.wire.requests.count, count); XCTAssertEqual(h.controller.reference, h.reference)
            XCTAssertEqual(h.controller.phase, ownerChanged ? .invalidated : .idle)
        }
    }
}
