import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ParticipantReadbackRecordFenceTests: XCTestCase {
    func testLateReadCannotClearDifferentPendingRecordWithSameReadGeneration() async throws {
        try await checkLateRead(returningToSameOwner: false)
    }
    func testLateReadCannotClearRestoredSameRecordInNewIdentity() async throws {
        try await checkLateRead(returningToSameOwner: true)
    }
    private func checkLateRead(returningToSameOwner: Bool) async throws {
        let io = ReadbackFenceIO(), journal = ReadbackFenceJournal()
        var owner = "a"
        let oldID = UUID()
        journal.values["a"] = .init(operationID: oldID, ownerKey: "a", targetKey: "profile.participants")
        journal.values["b"] = .init(operationID: UUID(), ownerKey: "b", targetKey: "profile.participants")
        let c = ParticipantMutationCoordinator(writer: io, reader: io, pendingJournal: journal, pendingOwner: { owner })
        let old = Task { await c.readBackUncertainOutcome() }
        defer { io.finishAll(); old.cancel() }
        for _ in 0..<1000 { if io.waiting[0] != nil { break }; await Task.yield() }
        guard io.waiting[0] != nil else { XCTFail("First read did not start"); return }
        owner = "b"; io.identity = .init(accountID: 1, epoch: 2); c.synchronizeSession()
        if returningToSameOwner { owner = "a"; io.identity = .init(accountID: 1, epoch: 3); c.synchronizeSession() }
        let current = Task { await c.readBackUncertainOutcome() }
        defer { io.finishAll(); current.cancel() }
        for _ in 0..<1000 { if io.waiting[1] != nil { break }; await Task.yield() }
        guard io.waiting[1] != nil else { XCTFail("Replacement read did not start"); return }
        XCTAssertEqual(c.readbackState, .loading)
        io.finish(0)
        let oldResult = await old.value
        XCTAssertEqual(oldResult, .ignoredStale)
        XCTAssertEqual(c.readbackState, .loading)
        let duplicate = await c.readBackUncertainOutcome()
        XCTAssertEqual(duplicate, .blocked(.readbackInProgress))
        io.finish(1); _ = await current.value
        XCTAssertEqual(c.readbackState, .received(.list([])))
        XCTAssertFalse(c.canPrepare); XCTAssertEqual(io.reads, 2)
    }
}
@MainActor private final class ReadbackFenceJournal: OperationPendingJournal {
    var values: [String: OperationPendingRecord] = [:]
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { values[ownerKey] }
    func write(_ record: OperationPendingRecord) throws { XCTFail("Readback must not write journal") }
    func clear(_ record: OperationPendingRecord) throws { XCTFail("Readback must not clear journal") }
}
@MainActor private final class ReadbackFenceIO: ProfileReading, ParticipantWriting {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var reads = 0
    var waiting: [Int: CheckedContinuation<[ProfileParticipant], Never>] = [:]
    func finish(_ i: Int) { waiting.removeValue(forKey: i)?.resume(returning: []) }
    func finishAll() { for i in Array(waiting.keys) { finish(i) } }
    func profileParticipants() async throws -> [ProfileParticipant] {
        let i = reads; reads += 1
        return await withCheckedContinuation { waiting[i] = $0 }
    }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws { XCTFail("Readback must not write") }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}
