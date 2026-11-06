import Foundation
import XCTest
@testable import Questify

@MainActor final class ParticipantFormLateActionTests: XCTestCase {
    private func setup() async throws -> (ParticipantFormModel, FormLateActionIO) {
        let io = FormLateActionIO()
        let c = ParticipantMutationCoordinator(writer: io, reader: io)
        let model = ParticipantFormModel(id: nil, reader: io, coordinator: c)
        await model.load(); model.draft.fullName = "Name"; model.draft.mobilePhone = "13900000000"
        model.prepareSave(); _ = await model.confirmMutation()
        XCTAssertEqual(model.operation, .outcomeUnknown(.transport))
        return (model, io)
    }
    func testQueuedReadAfterDepartureDoesNotStartRequest() async throws {
        let (model, io) = try await setup()
        model.disappear()
        await model.readBack()
        XCTAssertFalse(model.canReadBack); XCTAssertEqual(io.reads, 0)
        XCTAssertEqual(model.readback, .idle)
    }
    func testOldReadCompletionCannotRepopulateDepartedModelFromNewRead() async throws {
        let (model, io) = try await setup()
        io.suspendFirstRead = true
        let task = Task { await model.readBack() }
        defer { io.finish(); task.cancel() }
        for _ in 0..<1000 { if io.pending != nil { break }; await Task.yield() }
        guard io.pending != nil else { XCTFail("Read did not start"); return }
        model.disappear()
        _ = await model.coordinator.readBackUncertainOutcome()
        XCTAssertEqual(model.coordinator.readbackState, .received(.list([])))
        io.finish(); await task.value
        XCTAssertEqual(model.readback, .idle)
        XCTAssertTrue(model.draft.fullName.isEmpty); XCTAssertFalse(model.canReadBack)
        XCTAssertEqual(io.reads, 2)
    }
    func testQueuedRetryAfterBackgroundDoesNotDispatchAndKeepsOriginalPayload() async throws {
        let (model, io) = try await setup()
        let original = try XCTUnwrap(model.originalCreateRetry)
        XCTAssertTrue(model.canRetryOriginalCreate)
        model.suspendOriginalCreateRetry()
        let retried = await model.retryOriginalCreate()
        XCTAssertFalse(retried); XCTAssertFalse(model.canRetryOriginalCreate)
        XCTAssertEqual(io.writes, 1); XCTAssertEqual(model.originalCreateRetry, original)
        model.resumeOriginalCreateRetry()
        XCTAssertTrue(model.canRetryOriginalCreate)
    }
}
@MainActor private final class FormLateActionIO: ProfileReading, ParticipantWriting {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var writes = 0, reads = 0
    var suspendFirstRead = false
    var pending: CheckedContinuation<[ProfileParticipant], Never>?
    func finish() { let held = pending; pending = nil; held?.resume(returning: []) }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        writes += 1; throw ParticipantWriteError.outcomeUnknown(.transport)
    }
    func profileParticipants() async throws -> [ProfileParticipant] {
        reads += 1
        if suspendFirstRead && reads == 1 { return await withCheckedContinuation { pending = $0 } }
        return []
    }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}
