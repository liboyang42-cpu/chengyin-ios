import XCTest
@testable import QuestifyCore

@MainActor private final class DirectionReader: CoopFlowReading {
    var session: CoopFlowSession?
    var sent: [CoopFlowJSON] = [], received: [CoopFlowJSON] = []
    var calls = 0
    var hook: (() -> Void)?
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        XCTAssertEqual(resource, .invitations); calls += 1; hook?()
        return .object(["sent": .array(sent), "received": .array(received)])
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
@MainActor private final class DirectionExecutor: CoopFlowExecuting {
    var dispatchScope: String? = "fixture-one"
    var calls = 0
    func permitsDispatch(_ operation: CoopFlowMutation) -> Bool { true }
    func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON { calls += 1; return .object([:]) }
}
@MainActor private final class MissingDirectionEvidence: CoopFlowEvidenceReading {
    func freshEvidence(for operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowEvidence {
        .init(baseline: .object(["id": .id(7), "status": .id(0), "fromId": .id(session.accountID)]), permitted: true)
    }
}
@MainActor final class CooperationInvitationDirectionDispatchTests: XCTestCase {
    private func row(_ status: Int = 0) -> CoopFlowJSON {
        // Deliberately misleading row direction: trusted source membership must win.
        .object(["id": .id(7), "fromId": .id(90), "toId": .id(92), "status": .id(status), "inviteType": .id(1), "invitationDirection": .string("received")])
    }
    private func session(_ account: Int = 91, epoch: UInt64 = 1, token: String = "fake") throws -> CoopFlowSession {
        try .init(accountID: account, epoch: epoch, token: token)
    }
    private func coordinator(_ reader: DirectionReader, _ executor: DirectionExecutor, enabled: Bool = true) -> CoopFlowCoordinator {
        .init(current: { reader.session }, evidence: CoopFlowSourceEvidenceReader(reader: reader), executor: executor,
              locks: CoopFlowFileLocks(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), enabled: enabled)
    }
    private func fails(_ error: CoopFlowFailure, _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected rejection") } catch let actual { XCTAssertEqual(actual as? CoopFlowFailure, error) }
    }
    func testOwnerAndEmployeeSentCancelThroughFreshPrepareAndConfirm() async throws {
        for account in [90,91] {
            let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session(account); reader.sent = [row()]
            let c = coordinator(reader, executor); let review = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why"))
            XCTAssertEqual(review.baseline["invitationDirection"], .string("sent"))
            _ = try await c.confirm(review); XCTAssertEqual(reader.calls, 2); XCTAssertEqual(executor.calls, 1)
        }
    }
    func testOwnerAndEmployeeReceivedAcceptAndReject() async throws {
        for account in [92,91] { for action in [CoopFlowHandle.accept, .reject] {
            let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session(account); reader.received = [row()]
            let c = coordinator(reader, executor); let review = try await c.prepare(.handle(inviteID: 7, action: action, reason: "why"))
            _ = try await c.confirm(review); XCTAssertEqual(reader.calls, 2); XCTAssertEqual(executor.calls, 1)
        } }
    }
    func testMissingDuplicateAndBothBoxesFailClosed() async throws {
        for mode in 0...2 {
            let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session()
            if mode == 1 { reader.sent = [row(),row()] }
            if mode == 2 { reader.sent = [row()]; reader.received = [row()] }
            let c = coordinator(reader, executor)
            await fails(mode == 0 ? .unavailable : .conflict) { _ = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why")) }
            XCTAssertEqual(executor.calls, 0)
        }
    }
    func testMissingFreshDirectionCannotInferPrincipal() async throws {
        let s = try session(90), executor = DirectionExecutor()
        let c = CoopFlowCoordinator(current: { s }, evidence: MissingDirectionEvidence(), executor: executor,
            locks: CoopFlowFileLocks(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), enabled: true)
        await fails(.permission) { _ = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why")) }
        XCTAssertEqual(executor.calls, 0)
    }
    func testDirectionChangeAtConfirmationRejects() async throws {
        let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session(); reader.sent = [row()]
        let c = coordinator(reader, executor); let review = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why"))
        reader.sent = []; reader.received = [row()]
        await fails(.permission) { _ = try await c.confirm(review) }; XCTAssertEqual(executor.calls, 0)
    }
    func testOldSessionAccountTokenEpochAndScopeReject() async throws {
        for mode in 0...3 {
            let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session(); reader.sent = [row()]
            let c = coordinator(reader, executor); let review = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why"))
            switch mode {
            case 0: reader.session = try session(93)
            case 1: reader.session = try session(epoch: 2)
            case 2: reader.session = try session(token: "replacement")
            default: executor.dispatchScope = "fixture-two"
            }
            await fails(.stale) { _ = try await c.confirm(review) }; XCTAssertEqual(executor.calls, 0)
        }
    }
    func testSwitchDuringFreshReadRejects() async throws {
        let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session(); reader.sent = [row()]
        let c = coordinator(reader, executor); let review = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why"))
        reader.hook = { reader.session = nil }
        await fails(.stale) { _ = try await c.confirm(review) }; XCTAssertEqual(executor.calls, 0)
    }
    func testProductionDefaultStillDisabled() async throws {
        let reader = DirectionReader(), executor = DirectionExecutor(); reader.session = try session(); reader.sent = [row()]
        let c = coordinator(reader, executor, enabled: false); let review = try await c.prepare(.handle(inviteID: 7, action: .cancel, reason: "why"))
        await fails(.disabled) { _ = try await c.confirm(review) }; XCTAssertEqual(executor.calls, 0)
    }
}
