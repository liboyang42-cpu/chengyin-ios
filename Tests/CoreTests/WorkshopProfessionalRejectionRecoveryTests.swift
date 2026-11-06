import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// New source-only regressions of original status/cancel transport; no real materialization.
@MainActor final class WorkshopProfessionalRejectionRecoveryTests: XCTestCase {
    typealias F = WorkshopProfessionalFixture
    final class Memory: TemplateAuthoringStorage {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    final class Wire: HTTPTransport, WorkshopPaidProfessionalMutationTransport {
        let context: RuntimeDependencyContext, command: WorkshopPaidProfessionalCommand
        var state = "CREATED", status = 200, pause = false, pauseWrite = false, reads = 0, writes = 0
        var pending: CheckedContinuation<(Data, Int), Never>?
        init(_ context: RuntimeDependencyContext, _ command: WorkshopPaidProfessionalCommand) { self.context = context; self.command = command }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            reads += 1
            if pause { return await withCheckedContinuation { pending = $0 } }
            guard request.url?.lastPathComponent == "status" else { throw WorkshopPaidProfessionalIssue.invalid }
            return (try F.data(["code": 200, "data": F.operation(command, state: state)]), status)
        }
        func sendWorkshopPaidProfessional(_ request: URLRequest, authorization: WorkshopPaidProfessionalDispatchAuthorization) async throws -> (Data, Int) {
            try authorization.consume(request, context: context, revision: authorization.approvalRevision)
            writes += 1
            if pauseWrite { return await withCheckedContinuation { pending = $0 } }
            return (try F.data(["code": 200, "data": F.operation(command, state: "CANCELLED")]), 200)
        }
        func wait() async { for _ in 0..<1000 { if pending != nil { return }; await Task.yield() }; XCTFail("Expected delayed synthetic response") }
        func reject() { let old = pending; pending = nil; old?.resume(returning: (Data(), 401)) }
    }
    final class Fixture {
        let context: RuntimeDependencyContext, command: WorkshopPaidProfessionalCommand, reference: WorkshopPaidInstalledTextReference
        let wire: Wire, memory: Memory
        var current: RuntimeDependencyContext?, read: WorkshopPaidProfessionalReadApproval?, write: WorkshopPaidProfessionalWriteApproval?
        lazy var lease = ContentDraftSessionLease(context: context, current: { [weak self] in self?.current })
        lazy var store = try! WorkshopPaidProfessionalPendingStore(storage: memory, context: context, reference: reference)
        lazy var service = WorkshopPaidProfessionalService(api: try! APIConfiguration(baseURL: context.baseURL), transport: wire, lease: lease,
            readApproval: read, currentReadApproval: { [weak self] in self?.read }, writeApproval: write, currentWriteApproval: { [weak self] in self?.write })
        lazy var controller = WorkshopPaidProfessionalController(reference: reference, service: service, store: store, lease: lease)
        init(memory: Memory? = nil, writing: Bool = true) throws {
            context = try WorkshopOwnedTestData.context(); current = context
            command = try F.command(); reference = try WorkshopPaidTextFixture.reference()
            wire = Wire(context, command); self.memory = memory ?? Memory()
            read = try .init(context: context, expiresAt: .distantFuture)
            write = writing ? try .init(context: context, expiresAt: .distantFuture) : nil
        }
        func load(_ a: WorkshopPaidProfessionalAppearance) async throws {
            try store.save(command); await (try XCTUnwrap(controller.appear(a)))()
        }
    }
    func testCurrentStatus401RetiresHistoricalEntryAndKeepsOriginalStore() async throws {
        let f = try Fixture(), a = WorkshopPaidProfessionalAppearance(); try await f.load(a)
        let operation = try XCTUnwrap(f.controller.operation), bytes = f.memory.values
        XCTAssertEqual(f.controller.generatedTemplateID(a, expected: operation), 700)
        f.wire.status = 401
        await (try XCTUnwrap(f.controller.offerRefreshStatus(a)))()
        XCTAssertEqual(f.controller.phase, .invalidated); XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertNil(f.controller.generatedTemplateID(a, expected: operation))
        XCTAssertNil(f.controller.operation); XCTAssertNil(f.controller.command)
        XCTAssertTrue(f.controller.operations.isEmpty); XCTAssertTrue(f.controller.targets.isEmpty)
        XCTAssertNil(f.controller.offerRefreshStatus(a)); XCTAssertNil(f.controller.offerAcknowledge(a))
        XCTAssertEqual(f.memory.values, bytes); XCTAssertEqual(f.wire.writes, 0)
        let fresh = try Fixture(memory: f.memory, writing: false), display = WorkshopPaidProfessionalAppearance()
        try await fresh.load(display)
        XCTAssertEqual(fresh.controller.operation?.requestId, f.command.requestId)
        XCTAssertEqual(fresh.controller.phase, .operation); XCTAssertEqual(fresh.wire.writes, 0)
        XCTAssertEqual(fresh.memory.values, bytes)
    }
    func testDispatchedCancel401RetiresPageWithoutClaimingRollback() async throws {
        let f = try Fixture(), a = WorkshopPaidProfessionalAppearance(); f.wire.state = "PREPARED"; try await f.load(a)
        f.wire.pauseWrite = true
        let action = try XCTUnwrap(f.controller.offerCancelPending(a)), bytes = f.memory.values
        let task = Task { await action() }; await f.wire.wait(); f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.phase, .invalidated); XCTAssertEqual(f.controller.issue, .unauthorized)
        XCTAssertEqual(f.wire.writes, 1); XCTAssertEqual(f.memory.values, bytes)
        XCTAssertEqual(try f.store.load()?.wireData(), try f.command.wireData())
        XCTAssertNil(f.controller.offerCancelPending(a)); XCTAssertNil(f.controller.offerAcknowledge(a))
    }
    func testWriteWithdrawalPreservesIndependentOriginalStatusRead() async throws {
        let f = try Fixture(), a = WorkshopPaidProfessionalAppearance(); f.wire.state = "PREPARED"; try await f.load(a)
        f.wire.pauseWrite = true
        let action = try XCTUnwrap(f.controller.offerCancelPending(a)), bytes = f.memory.values
        let task = Task { await action() }; await f.wire.wait()
        f.write = nil; f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.issue, .disabled); XCTAssertEqual(f.controller.phase, .operation)
        XCTAssertTrue(f.lease.isCurrent); XCTAssertEqual(f.memory.values, bytes)
        await (try XCTUnwrap(f.controller.offerRefreshStatus(a)))()
        XCTAssertEqual(f.controller.operation?.state, .prepared)
        XCTAssertEqual(f.wire.writes, 1)
    }
    func testTransientStatusFailurePreservesOriginalRecoveryAndNeverWrites() async throws {
        let f = try Fixture(), a = WorkshopPaidProfessionalAppearance(); try await f.load(a)
        let bytes = f.memory.values; f.wire.status = 503
        await (try XCTUnwrap(f.controller.offerRefreshStatus(a)))()
        XCTAssertEqual(f.controller.phase, .operation); XCTAssertTrue(f.lease.isCurrent)
        XCTAssertEqual(f.memory.values, bytes); XCTAssertEqual(f.wire.writes, 0)
        f.wire.status = 200; await (try XCTUnwrap(f.controller.offerRefreshStatus(a)))()
        XCTAssertEqual(f.controller.operation?.state, .created)
    }
    func testLate401CannotRetireFreshAppearance() async throws {
        let f = try Fixture(), old = WorkshopPaidProfessionalAppearance(); try f.store.save(f.command)
        f.wire.pause = true
        let action = try XCTUnwrap(f.controller.appear(old)), task = Task { await action() }
        await f.wire.wait(); f.controller.close(old)
        let fresh = WorkshopPaidProfessionalAppearance(); f.wire.pause = false
        await (try XCTUnwrap(f.controller.appear(fresh)))()
        f.wire.reject(); await task.value
        XCTAssertEqual(f.controller.phase, .operation); XCTAssertTrue(f.lease.isCurrent)
        XCTAssertEqual(f.controller.operation?.requestId, f.command.requestId)
        XCTAssertEqual(f.wire.writes, 0)
    }
}
