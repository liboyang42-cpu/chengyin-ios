import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Synthetic in-memory data only. These tests do not contact an account or backend.
@MainActor
final class ParticipantCoordinatorSnapshotLifetimeTests: XCTestCase {
    func testSuccessfulCreateRetainsRowForSameEpochSelectionAndOriginalUUID() async throws {
        let row = try participant()
        let writer = SnapshotWriter(row: row)
        let reader = SnapshotReader()
        var changes = 0
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader,
                                                         onParticipantsChanged: { changes += 1 })
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        let result = await coordinator.confirm(confirmation)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(coordinator.state, .succeeded)
        XCTAssertEqual(coordinator.savedParticipant, row)
        coordinator.synchronizeSession()
        XCTAssertEqual(coordinator.savedParticipant, row)
        XCTAssertEqual(try snapshot(coordinator).row, row)
        XCTAssertEqual(writer.requestIDs, [confirmation.id])
        XCTAssertEqual(changes, 1)
        let duplicate = await coordinator.confirm(confirmation)
        XCTAssertEqual(duplicate, .blocked(.confirmationNoLongerValid))
        XCTAssertEqual(writer.requestIDs.count, 1)
    }

    func testLogoutRetiresPrivateRowWithoutDeletingSuccessfulOperationFact() async throws {
        let writer = SnapshotWriter(row: try participant())
        let reader = SnapshotReader()
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader)
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        _ = await coordinator.confirm(confirmation)
        let before = try snapshot(coordinator)
        XCTAssertNotNil(before.row)

        writer.identity = nil
        reader.identity = nil
        coordinator.synchronizeSession()
        let retired = try snapshot(coordinator)
        XCTAssertNil(retired.row)
        XCTAssertNil(coordinator.savedParticipant)
        XCTAssertEqual(retired.id, before.id)
        XCTAssertEqual(retired.identity, before.identity)
        XCTAssertEqual(retired.target, before.target)
        XCTAssertEqual(retired.state, .succeeded)
        XCTAssertEqual(retired.readGeneration, before.readGeneration)
        XCTAssertEqual(writer.requestIDs, [confirmation.id])

        // A new epoch of the same account must not revive old contact data.
        writer.identity = .init(accountID: 1, epoch: 2)
        reader.identity = writer.identity
        coordinator.synchronizeSession()
        XCTAssertNil(coordinator.savedParticipant)
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertEqual(coordinator.state, .succeeded)
        XCTAssertTrue(coordinator.canPrepare)
    }

    func testDirectAccountSwitchRetiresOnlyTheOldAccountsProjection() async throws {
        let writer = SnapshotWriter(row: try participant())
        let reader = SnapshotReader()
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader)
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        _ = await coordinator.confirm(confirmation)

        writer.identity = .init(accountID: 2, epoch: 2)
        reader.identity = writer.identity
        coordinator.synchronizeSession()
        XCTAssertNil(try snapshot(coordinator, accountID: 1).row)
        XCTAssertEqual(try snapshot(coordinator, accountID: 1).id, confirmation.id)
        XCTAssertEqual(try snapshot(coordinator, accountID: 1).state, .succeeded)
        XCTAssertNil(coordinator.savedParticipant)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.canPrepare)
        XCTAssertEqual(writer.requestIDs, [confirmation.id])
    }

    func testLateSuccessAfterDismissalCannotPopulateUnknownRecordOrClearItsLock() async throws {
        let row = try participant()
        let writer = SnapshotWriter(row: row)
        let reader = SnapshotReader()
        reader.rows = [row]
        var changes = 0
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader,
                                                         onParticipantsChanged: { changes += 1 })
        let gate = SnapshotResponseGate<ProfileParticipant?>()
        writer.operation = { try await gate.wait() }
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        defer { gate.finish(.failure(CancellationError())); task.cancel() }
        try await waitUntilRequested(gate)
        coordinator.leaveScreen(confirmation: confirmation)
        gate.finish(.success(row))
        let result = await task.value

        XCTAssertEqual(result, .ignoredStale)
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.cancelled))
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertNil(coordinator.savedParticipant)
        XCTAssertEqual(changes, 0)
        let read = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(read, .applied)
        XCTAssertEqual(coordinator.readbackState, .received(.list([row])))
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertEqual(try snapshot(coordinator).id, confirmation.id)
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.cancelled))
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(writer.requestIDs, [confirmation.id])
        XCTAssertEqual(reader.listCalls, 1)
    }

    func testRealSessionWriterLogoutRejectsLateRowAndSameAccountReentryKeepsReadOnlyRecovery() async throws {
        let row = try participant()
        var current: ParticipantWriteSession? = try ParticipantWriteSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let reader = SnapshotReader()
        reader.rows = [row]
        let gate = SnapshotResponseGate<(Data, Int)>()
        var requests: [URLRequest] = []
        let transport = SnapshotTransport { request in
            requests.append(request)
            return try await gate.wait()
        }
        let service = ParticipantService(
            configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!),
            transport: transport)
        let writer = ParticipantSessionWriter(service: service, currentSession: { current })
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader)
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        defer { gate.finish(.failure(CancellationError())); task.cancel() }
        try await waitUntilRequested(gate)
        current = nil
        reader.identity = nil
        coordinator.synchronizeSession()
        gate.finish(.success((Data(Self.successJSON.utf8), 200)))
        let result = await task.value
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertEqual(try snapshot(coordinator).state, .outcomeUnknown(.accountChanged))

        current = try ParticipantWriteSession(accountID: 1, epoch: 3, token: "synthetic-new-token")
        reader.identity = current?.identity
        coordinator.synchronizeSession()
        XCTAssertFalse(coordinator.canPrepare)
        let read = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(read, .applied)
        XCTAssertEqual(coordinator.readbackState, .received(.list([row])))
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.accountChanged))
        XCTAssertNil(coordinator.savedParticipant)
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertEqual(try snapshot(coordinator).id, confirmation.id)
        XCTAssertThrowsError(try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!))
        XCTAssertEqual(requests.count, 1)
        let body = String(decoding: try XCTUnwrap(requests.first?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"requestId\"\r\n\r\n\(confirmation.id.uuidString.lowercased())\r\n"))
        XCTAssertEqual(reader.listCalls, 1)
    }

    func testNonCooperativeWriterCannotRetainRowAfterIdentityRetirement() async throws {
        let row = try participant()
        let writer = SnapshotWriter(row: row)
        let reader = SnapshotReader()
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader)
        let gate = SnapshotResponseGate<ProfileParticipant?>()
        writer.operation = { try await gate.wait() }
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        defer { gate.finish(.failure(CancellationError())); task.cancel() }
        try await waitUntilRequested(gate)
        writer.identity = nil
        reader.identity = nil
        coordinator.synchronizeSession()
        gate.finish(.success(row))
        let result = await task.value
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertEqual(try snapshot(coordinator).id, confirmation.id)
        XCTAssertEqual(try snapshot(coordinator).state, .outcomeUnknown(.accountChanged))
        XCTAssertEqual(writer.requestIDs, [confirmation.id])
    }

    func testCancellationAfterDispatchDoesNotRetainReturnedRow() async throws {
        let row = try participant()
        let writer = SnapshotWriter(row: row)
        let reader = SnapshotReader()
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader)
        let gate = SnapshotResponseGate<ProfileParticipant?>()
        writer.operation = { try await gate.wait() }
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        defer { gate.finish(.failure(CancellationError())); task.cancel() }
        try await waitUntilRequested(gate)
        task.cancel()
        gate.finish(.success(row))
        let result = await task.value
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.cancelled))
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(writer.requestIDs, [confirmation.id])
    }

    func testLegacyNilAcknowledgmentRemainsSuccessfulWithoutInventingReturnedRow() async throws {
        let writer = SnapshotWriter(row: nil)
        let reader = SnapshotReader()
        var changes = 0
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader,
                                                         onParticipantsChanged: { changes += 1 })
        let confirmation = try coordinator.prepare(.save(draft()), expectedIdentity: reader.identity!)
        let result = await coordinator.confirm(confirmation)
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(coordinator.state, .succeeded)
        XCTAssertNil(coordinator.savedParticipant)
        XCTAssertNil(try snapshot(coordinator).row)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(writer.requestIDs, [confirmation.id])
    }

    private func waitUntilRequested<Value>(_ gate: SnapshotResponseGate<Value>,
                                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !gate.hasRequest {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                gate.finish(.failure(SnapshotGateFailure.timedOut))
                XCTFail("Synthetic transport/writer was not invoked before the test deadline", file: file, line: line)
                throw SnapshotGateFailure.timedOut
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private static let rowJSON = #"{"id":7,"fullName":"Synthetic Participant","mobilePhone":"13800000000","province":"Fixture Region","detailAddress":"Fixture Address"}"#
    private static var successJSON: String { "{\"code\":200,\"data\":\(rowJSON)}" }
    private func participant() throws -> ProfileParticipant {
        try JSONDecoder().decode(ProfileParticipant.self, from: Data(Self.rowJSON.utf8))
    }
    private func draft() -> ParticipantFormDraft {
        var value = ParticipantFormDraft()
        value.fullName = "Synthetic Participant"; value.mobilePhone = "13800000000"
        return value
    }

    private struct StoredSnapshot {
        let id: UUID
        let identity: ProfileReadIdentity
        let target: String
        let state: ParticipantMutationState
        let readGeneration: UInt64
        let row: ProfileParticipant?
    }

    // Inspect actual private storage because the public getter already hides retired rows.
    // This adds no product testing API and cannot mistake hidden PII for cleared PII.
    private func snapshot(_ coordinator: ParticipantMutationCoordinator, accountID: Int = 1) throws -> StoredSnapshot {
        let storage = try XCTUnwrap(Mirror(reflecting: coordinator).children.first { $0.label == "records" }?.value)
        let entry = try XCTUnwrap(Mirror(reflecting: storage).children.first {
            Mirror(reflecting: $0.value).children.first?.value as? Int == accountID
        })
        let record = try XCTUnwrap(Array(Mirror(reflecting: entry.value).children).last?.value)
        let fields = Array(Mirror(reflecting: record).children)
        func field(_ name: String) throws -> Any {
            try XCTUnwrap(fields.first { $0.label == name }?.value)
        }
        let optionalRow = Mirror(reflecting: try field("savedParticipant"))
        XCTAssertEqual(optionalRow.displayStyle, .optional)
        let id = try field("id")
        let identity = try field("originalIdentity")
        let target = try field("target")
        let state = try field("state")
        let readGeneration = try field("readGeneration")
        return StoredSnapshot(id: try XCTUnwrap(id as? UUID),
                              identity: try XCTUnwrap(identity as? ProfileReadIdentity),
                              target: String(describing: target),
                              state: try XCTUnwrap(state as? ParticipantMutationState),
                              readGeneration: try XCTUnwrap(readGeneration as? UInt64),
                              row: optionalRow.children.first?.value as? ProfileParticipant)
    }
}

@MainActor
private final class SnapshotWriter: ParticipantWriting {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var requestIDs: [UUID] = []
    var operation: () async throws -> ProfileParticipant?
    init(row: ProfileParticipant?) { operation = { row } }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        _ = try await performReturningParticipant(mutation, requestID: UUID(), expectedIdentity: expectedIdentity)
    }
    func performReturningParticipant(_ mutation: ParticipantMutation, requestID: UUID,
                                     expectedIdentity: ProfileReadIdentity) async throws -> ProfileParticipant? {
        guard identity == expectedIdentity else { throw ParticipantWriteError.notSent(.unauthorized) }
        requestIDs.append(requestID)
        return try await operation()
    }
}

@MainActor
private final class SnapshotReader: ProfileReading {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var rows: [ProfileParticipant] = []
    var listCalls = 0
    func profileParticipants() async throws -> [ProfileParticipant] { listCalls += 1; return rows }
    func profileParticipant(id: Int) async throws -> ProfileParticipant {
        guard let row = rows.first(where: { $0.id == id }) else { throw APIError.malformedResponse }
        return row
    }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}

private final class SnapshotTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}

private enum SnapshotGateFailure: Error { case timedOut, alreadyRequested }

/// A test-owned bounded response, including cleanup when a preceding assertion throws.
@MainActor
private final class SnapshotResponseGate<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var deadlineTask: Task<Void, Never>?
    private(set) var hasRequest = false
    private let file: StaticString
    private let line: UInt

    init(file: StaticString = #filePath, line: UInt = #line) {
        self.file = file; self.line = line
    }

    func wait() async throws -> Value {
        try Task.checkCancellation()
        guard !hasRequest else {
            XCTFail("Synthetic response gate was requested more than once", file: file, line: line)
            throw SnapshotGateFailure.alreadyRequested
        }
        hasRequest = true
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            deadlineTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
                guard let self else { return }
                XCTFail("Synthetic response continuation exceeded its test deadline", file: self.file, line: self.line)
                self.finish(.failure(SnapshotGateFailure.timedOut))
            }
        }
    }

    func finish(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        deadlineTask?.cancel(); deadlineTask = nil
        continuation?.resume(with: result); continuation = nil
    }
}
