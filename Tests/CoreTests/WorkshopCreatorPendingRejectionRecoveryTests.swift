import XCTest
@testable import QuestifyCore

/// Source-only tests using original synthetic data and transports without editing them.
@MainActor final class WorkshopCreatorPendingRejectionRecoveryTests: XCTestCase {
    typealias DataFixture = WorkshopCreatorPendingCoreTests
    @MainActor final class Wire: HTTPTransport, WorkshopCreatorPendingMutationTransport {
        let original: DataFixture.Wire
        var rejectRead = false, delayWrite = false, loseWrite = false
        var pending: CheckedContinuation<(Data, Int), Never>?
        var bodies: [Data] = []
        init(_ original: DataFixture.Wire) { self.original = original }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if rejectRead { return (Data(), 401) }
            return try await original.send(request)
        }
        func sendWorkshopCreatorPendingAuthor(_ request: URLRequest, authorization: WorkshopCreatorPendingAuthorization) async throws -> (Data, Int) {
            let result = try await original.sendWorkshopCreatorPendingAuthor(request, authorization: authorization)
            bodies.append(try XCTUnwrap(request.httpBody))
            if delayWrite { return await withCheckedContinuation { pending = $0 } }
            if loseWrite { throw WorkshopCreatorConsentIssue.unavailable }
            return result
        }
        func wait() async {
            for _ in 0..<1000 { if pending != nil { return }; await Task.yield() }
            XCTFail("Expected delayed synthetic author response")
        }
        func reject() { let value = pending; pending = nil; value?.resume(returning: (Data(), 401)) }
    }
    @MainActor final class Fixture {
        let base: DataFixture.Fixture, wire: Wire
        let memory: WorkshopCreatorPendingControllerTests.Memory
        let source = WorkshopCreatorPendingControllerTests.Source()
        lazy var store = try! WorkshopCreatorPendingStore(storage: memory, context: base.context, sourceTemplateId: 91)
        lazy var service = WorkshopCreatorPendingService(api: try! APIConfiguration(baseURL: base.context.baseURL), transport: wire, lease: base.lease,
            author: base.author, list: base.list, detail: base.detail,
            currentAuthor: { [weak self] in self?.base.author }, currentList: { [weak self] in self?.base.list }, currentDetail: { [weak self] in self?.base.detail },
            now: { DataFixture.now }, onUnauthorized: { [weak self] _ in self?.base.unauthorized += 1 })
        lazy var controller = WorkshopCreatorPendingController(sourceTemplateId: 91, service: service, previewService: source, lease: base.lease, store: store,
            canAuthor: { [weak self] in self?.base.author != nil }, now: { DataFixture.now }, makeConsent: { _, _ in nil })
        init(memory: WorkshopCreatorPendingControllerTests.Memory? = nil) throws {
            base = try DataFixture.Fixture(); wire = Wire(base.wire)
            self.memory = memory ?? WorkshopCreatorPendingControllerTests.Memory()
        }
        func load(_ a: WorkshopCreatorPendingAppearance) async throws { await (try XCTUnwrap(controller.appear(a)))() }
    }

    func testCurrentList401RetiresFormAndLocksOldActions() async throws {
        let f = try Fixture(), a = WorkshopCreatorPendingAppearance()
        f.controller.form.termsDocument = "Synthetic unsubmitted local text"
        f.wire.rejectRead = true; try await f.load(a)
        XCTAssertEqual(f.controller.phase, .invalidated)
        XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertEqual(f.controller.form, WorkshopCreatorPendingForm())
        XCTAssertNil(f.controller.preview); XCTAssertTrue(f.controller.items.isEmpty)
        XCTAssertFalse(f.base.lease.isCurrent)
        XCTAssertNil(f.controller.offerLoad(a)); XCTAssertNil(f.controller.offerRetry(a))
        XCTAssertEqual(f.base.unauthorized, 1); XCTAssertEqual(f.base.wire.writes, 0)
    }

    func testDispatched401KeepsExactUnknownJournalAndFreshSessionRequiresExplicitRetry() async throws {
        let f = try Fixture(), a = WorkshopCreatorPendingAppearance(), command = try DataFixture.command()
        try f.store.retain(command); try await f.load(a)
        f.wire.delayWrite = true
        let action = try XCTUnwrap(f.controller.offerRetry(a)), bytes = f.memory.values
        let task = Task { await action() }; await f.wire.wait(); f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.phase, .invalidated)
        XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(try f.store.load()?.data(), try command.data())
        XCTAssertNil(f.controller.receipt); XCTAssertNil(f.controller.offerRetry(a))
        XCTAssertEqual(f.base.wire.writes, 1)
        let fresh = try Fixture(memory: f.memory), displayed = WorkshopCreatorPendingAppearance()
        try await fresh.load(displayed)
        XCTAssertEqual(fresh.base.wire.writes, 0)
        XCTAssertNil(fresh.controller.receipt)
        XCTAssertEqual(fresh.memory.values, bytes)
        // No author-status route exists. Only an explicit same-request retry is offered.
        await (try XCTUnwrap(fresh.controller.offerRetry(displayed)))()
        XCTAssertEqual(fresh.wire.bodies, [try command.data()])
        XCTAssertEqual(fresh.base.wire.writes, 1)
        XCTAssertNotNil(fresh.controller.receipt)
    }

    func testIndependentWriteWithdrawalDoesNotRetireReadSessionOrEraseUnknown() async throws {
        let f = try Fixture(), a = WorkshopCreatorPendingAppearance(), command = try DataFixture.command()
        try f.store.retain(command); try await f.load(a); f.wire.delayWrite = true
        let action = try XCTUnwrap(f.controller.offerRetry(a)), bytes = f.memory.values
        let task = Task { await action() }; await f.wire.wait()
        f.base.author = nil; f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.issue, .disabled)
        XCTAssertEqual(f.controller.phase, .failed)
        XCTAssertTrue(f.base.lease.isCurrent); XCTAssertEqual(f.base.unauthorized, 0)
        XCTAssertEqual(f.memory.values, bytes); XCTAssertFalse(f.controller.canRetry)
        await (try XCTUnwrap(f.controller.offerLoad(a)))()
        XCTAssertEqual(f.controller.phase, .editing)
        XCTAssertEqual(f.base.wire.writes, 1)
    }

    func testUnknownTransportOutcomeKeepsOriginalRetryAndDoesNotRetire() async throws {
        let f = try Fixture(), a = WorkshopCreatorPendingAppearance(), command = try DataFixture.command()
        try f.store.retain(command); try await f.load(a); f.wire.loseWrite = true
        let bytes = f.memory.values
        await (try XCTUnwrap(f.controller.offerRetry(a)))()
        XCTAssertEqual(f.controller.issue, .unknown); XCTAssertEqual(f.controller.phase, .failed)
        XCTAssertTrue(f.base.lease.isCurrent); XCTAssertTrue(f.controller.canRetry)
        XCTAssertEqual(f.memory.values, bytes); XCTAssertEqual(f.base.wire.writes, 1)
    }

    func testOld401DoesNotRetireReplacementAppearance() async throws {
        let f = try Fixture(), old = WorkshopCreatorPendingAppearance(), command = try DataFixture.command()
        try f.store.retain(command); try await f.load(old); f.wire.delayWrite = true
        let action = try XCTUnwrap(f.controller.offerRetry(old))
        let task = Task { await action() }; await f.wire.wait()
        f.controller.close(old)
        let fresh = WorkshopCreatorPendingAppearance(); try await f.load(fresh)
        f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.phase, .editing); XCTAssertTrue(f.base.lease.isCurrent)
        XCTAssertEqual(f.base.unauthorized, 0); XCTAssertEqual(f.base.wire.writes, 1)
        XCTAssertEqual(try f.store.load()?.data(), try command.data())
    }
}
