import XCTest
@testable import QuestifyCore

@MainActor final class CoopRelationCancellationTests: XCTestCase {
    func testCancelledCurrentReadClearsLoadingWithoutPublishing() async throws {
        let reader=HeldCoopRelationReader(), model=CoopRelationDiscoveryModel()
        let started=expectation(description:"Current read dispatched")
        reader.onRead={ _ in started.fulfill() }
        let task=Task { await model.load(reader:reader) }
        await fulfillment(of:[started],timeout:2)
        XCTAssertTrue(model.isLoading)
        task.cancel(); reader.finish(1)
        await task.value
        XCTAssertFalse(model.isLoading); XCTAssertNil(model.value); XCTAssertFalse(model.failed)
    }
    func testOwnerReplacementDuringReadClearsLoadingWithoutAcceptingOldRows() async throws {
        for changeSession in [false,true] {
            let reader=HeldCoopRelationReader(), model=CoopRelationDiscoveryModel()
            let started=expectation(description:"Read dispatched before owner replacement")
            reader.onRead={ _ in started.fulfill() }
            var current=true
            let task=Task { await model.load(reader:reader,isCurrent:{current}) }
            await fulfillment(of:[started],timeout:2)
            if changeSession { reader.session=try .init(accountID:2,epoch:2,token:"synthetic-replacement") }
            else { current=false }
            reader.finish(1); await task.value
            XCTAssertFalse(model.isLoading); XCTAssertNil(model.value); XCTAssertFalse(model.failed)
        }
    }
    func testOldCancelledCompletionCannotFinishOrReplaceANewerRead() async throws {
        let reader=HeldCoopRelationReader(), model=CoopRelationDiscoveryModel()
        let firstStarted=expectation(description:"Old read dispatched"), nextStarted=expectation(description:"Replacement read dispatched")
        reader.onRead={ id in if id == 1 { firstStarted.fulfill() } else if id == 2 { nextStarted.fulfill() } }
        let old=Task { await model.load(reader:reader) }
        await fulfillment(of:[firstStarted],timeout:2)
        old.cancel()
        let next=Task { await model.load(reader:reader) }
        await fulfillment(of:[nextStarted],timeout:2)
        reader.finish(1); await old.value
        XCTAssertTrue(model.isLoading); XCTAssertNil(model.value); XCTAssertFalse(model.failed)
        reader.finish(2); await next.value
        XCTAssertFalse(model.isLoading); XCTAssertTrue(model.isCurrent(reader:reader))
        XCTAssertEqual(model.value?.merchants.first?.name,"Synthetic request 2")
    }
    func testAlreadyCancelledInvocationCannotInvalidateAcceptedNewerSnapshot() async throws {
        let reader=HeldCoopRelationReader(), model=CoopRelationDiscoveryModel()
        reader.immediate=true
        await model.load(reader:reader)
        let accepted=try XCTUnwrap(model.value)
        let gate=CoopRelationCancellationGate()
        let obsolete=Task { await gate.wait(); await model.load(reader:reader) }
        obsolete.cancel(); gate.open(); await obsolete.value
        XCTAssertEqual(reader.readCount,1)
        XCTAssertEqual(model.value,accepted); XCTAssertTrue(model.isCurrent(reader:reader)); XCTAssertFalse(model.isLoading)
    }
}
@MainActor private final class HeldCoopRelationReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID:1,epoch:1,token:"synthetic")
    var onRead: ((Int) -> Void)?
    var immediate=false
    private(set) var readCount=0
    private var pending: [Int:CheckedContinuation<CoopFlowJSON,Error>]=[:]
    private func response(_ id: Int) -> CoopFlowJSON {
        .object(["relations":.array([]),"discovery":.object(["merchants":.array([
            .object(["id":.id(8),"memberId":.id(41),"name":.string("Synthetic request \(id)")])]),"clubs":.array([])])])
    }
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        readCount += 1; let id=readCount
        if immediate { onRead?(id); return response(id) }
        // Deliberately does not cooperate with task cancellation: publication fencing
        // and generation-specific cleanup must remain correct after a late reply.
        return try await withCheckedThrowingContinuation { pending[id]=$0; onRead?(id) }
    }
    func finish(_ id: Int) { pending.removeValue(forKey:id)?.resume(returning:response(id)) }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
@MainActor private final class CoopRelationCancellationGate {
    private var opened=false
    private var waiting: CheckedContinuation<Void,Never>?
    func wait() async { if opened { return }; await withCheckedContinuation { waiting=$0 } }
    func open() { opened=true; let old=waiting; waiting=nil; old?.resume() }
}
