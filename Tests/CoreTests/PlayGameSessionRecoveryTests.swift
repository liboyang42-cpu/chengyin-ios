import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class PlayGameSessionRecoveryTests: XCTestCase {
    @MainActor private final class Owner {
        var session: PlayExperienceSession?
        init() throws { session = try .init(accountID: 7, epoch: 1, namespace: "synthetic-cn", token: "synthetic-token") }
    }
    private func setup(enabled: Set<PlayExperienceCapability> = [.reads, .playerCommands]) async throws -> (Owner, ReceiptRecoveryWire, PlayPlayerGameCoordinator) {
        let owner = try Owner(), wire = ReceiptRecoveryWire()
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: enabled)
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.session })
        await model.load()
        return (owner, wire, model)
    }
    private func command(_ id: String = "original-request", revision: Int = 2) throws -> PlayPlayerCommand {
        try .init(activityID: 41, nodeID: 701, requestID: id, expectedRevision: revision, action: .choice, payload: ["choiceId": .string("LEFT")])
    }
    private func receipt(_ command: PlayPlayerCommand, outcome: String = "APPLIED", revision: Int = 3) -> PlayWireValue {
        .object(["activityId": .int(41), "requestId": .string(command.requestID), "action": .string(command.action.rawValue),
                 "receiptId": .int(91), "outcome": .string(outcome), "revision": .int(revision), "result": .object([:])])
    }
    private func projection(revision: Int = 3, sessionID: Int = 501) throws -> PlayWireValue {
        var value = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        value["revision"] = .int(revision); value["sessionId"] = .int(sessionID)
        return .object(value)
    }
    private func assertUnknown(_ model: PlayPlayerGameCoordinator, _ command: PlayPlayerCommand, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, "unknown", file: file, line: line)
        XCTAssertEqual(model.pending, command, file: file, line: line)
        XCTAssertThrowsError(try model.capturePlayerActionReview(), file: file, line: line)
    }

    func testCommandAjaxErrorCannotReplaceAuthoritativeFailedReceipt() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        wire.commands = [.businessError(500)]
        await model.submit(original)
        assertUnknown(model, original)
        await model.submit(try command("replacement-request"))
        XCTAssertEqual(wire.posts.count, 1)
        wire.receipts = [.value(receipt(original, outcome: "FAILED", revision: 2))]
        await model.recover()
        XCTAssertNil(model.pending); XCTAssertEqual(model.phase, "rejected")
        XCTAssertEqual(model.receipt?.outcome, "FAILED")
        XCTAssertThrowsError(try model.capturePlayerActionReview())
        wire.views = [.value(try projection(revision: 4))]
        await model.load()
        XCTAssertEqual(model.phase, "ready"); XCTAssertEqual(model.projection?.revision, 4)
    }

    func testReceiptAjaxErrorsKeepExactCommandAndNeverAuthorizeAnotherID() async throws {
        for code in [400, 403, 409, 500] {
            let (_, wire, model) = try await setup(), original = try command()
            await model.submit(original)
            wire.receipts = [.businessError(code)]
            await model.recover()
            assertUnknown(model, original)
            XCTAssertEqual(model.issue, .rejected(code, "Synthetic request failure"))
            await model.submit(try command("replacement-request"))
            XCTAssertEqual(wire.posts.count, 1)
            wire.commands = [.businessError(500)]
            await model.retryExact()
            assertUnknown(model, original)
            XCTAssertEqual(wire.posts.count, 2)
            XCTAssertEqual(wire.posts.first?.httpBody, wire.posts.last?.httpBody)
            let query = URLComponents(url: try XCTUnwrap(wire.receiptRequests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertTrue(query?.contains(.init(name: "requestId", value: original.requestID)) == true)
            XCTAssertTrue(query?.contains(.init(name: "activityId", value: "41")) == true)
        }
    }

    func testMissingPendingMalformedAndUnauthorizedReadsRemainUnknown() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        await model.submit(original)
        // The source's missing-row response has no action/revision/receiptId.
        let missing: PlayWireValue = .object(["activityId": .int(41), "requestId": .string(original.requestID), "outcome": .string("PENDING"), "replayed": .bool(false)])
        wire.receipts = [.value(missing)]
        await model.recover(); assertUnknown(model, original)
        XCTAssertEqual(model.issue, .unknownResult)
        wire.receipts = [.value(receipt(original, outcome: "PENDING", revision: 2)),
                         .value(.null), .businessError(401), .failure(.disabled), .failure(.unknownResult)]
        for _ in 0..<5 { await model.recover(); assertUnknown(model, original) }
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testUnmatchedTerminalReceiptsCannotClearOriginalAttempt() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        await model.submit(original)
        let changes: [(String, PlayWireValue)] = [("activityId", .int(42)), ("requestId", .string("different-request")),
                                                ("action", .string("PLAYER_HINT")), ("receiptId", .null)]
        for (key, value) in changes {
            var invalid = try XCTUnwrap(receipt(original, outcome: "FAILED").object)
            invalid[key] = value; wire.receipts = [.value(.object(invalid))]
            await model.recover(); assertUnknown(model, original)
        }
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testAppliedProjectionFailureRetriesOnlyReadbackWithoutAnotherPost() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        wire.commands = [.value(receipt(original))]; wire.views = [.businessError(500)]
        await model.submit(original)
        assertUnknown(model, original); XCTAssertEqual(model.receipt?.outcome, "APPLIED")
        XCTAssertEqual(model.projection?.revision, 2)
        wire.views = [.value(try projection())]
        await model.retryExact()
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
        XCTAssertEqual(model.projection?.revision, 3); XCTAssertNil(model.issue)
        XCTAssertEqual(wire.posts.count, 1); XCTAssertTrue(wire.receiptRequests.isEmpty)
    }

    func testAppliedReceiptFromRecoverySurvivesProjectionError() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        await model.submit(original)
        wire.receipts = [.value(receipt(original))]; wire.views = [.businessError(403)]
        await model.recover(); assertUnknown(model, original)
        XCTAssertEqual(model.receipt?.outcome, "APPLIED")
        wire.views = [.value(try projection())]
        await model.load()
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
        XCTAssertEqual(wire.posts.count, 1); XCTAssertEqual(wire.receiptRequests.count, 1)
    }

    func testRefreshUnknownReadsOriginalReceiptBeforeChangingProjection() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        await model.submit(original)
        wire.receipts = [.value(receipt(original, outcome: "PENDING", revision: 2))]
        wire.views = [.value(try projection(revision: 8, sessionID: 502))]
        await model.load()
        assertUnknown(model, original); XCTAssertEqual(model.projection?.sessionID, 501)
        XCTAssertEqual(wire.requests.last?.url?.path, "/api/game/session/receipt")
        XCTAssertEqual(wire.viewRequests.count, 1)
    }

    func testAppliedReceiptRequiresOriginalSessionAndCurrentRevision() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        wire.commands = [.value(receipt(original))]
        wire.views = [.value(try projection(revision: 2)), .value(try projection(revision: 8, sessionID: 502)), .value(try projection())]
        await model.submit(original); assertUnknown(model, original)
        await model.recover(); assertUnknown(model, original)
        XCTAssertEqual(model.projection?.sessionID, 501); XCTAssertEqual(model.projection?.revision, 2)
        await model.recover()
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testNewUnknownCommandDoesNotShowOrReusePreviousAppliedReceipt() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        wire.commands = [.value(receipt(original))]; wire.views = [.value(try projection())]
        await model.submit(original)
        let second = try command("second-request", revision: 3)
        await model.submit(second)
        assertUnknown(model, second); XCTAssertNil(model.receipt)
        wire.receipts = [.value(receipt(second, outcome: "FAILED", revision: 3))]
        await model.recover()
        XCTAssertEqual(model.phase, "rejected"); XCTAssertEqual(model.receipt?.requestID, second.requestID)
        XCTAssertEqual(wire.receiptRequests.count, 1)
    }

    func testDisabledFirstDispatchDoesNotCreateUnknownAttempt() async throws {
        let (_, wire, model) = try await setup(enabled: [.reads])
        await model.submit(try command())
        XCTAssertEqual(model.phase, "disabled"); XCTAssertEqual(model.issue, .disabled)
        XCTAssertNil(model.pending); XCTAssertTrue(wire.posts.isEmpty)
        await model.recover(); await model.retryExact()
        XCTAssertTrue(wire.receiptRequests.isEmpty)
    }

    func testLateRecoveryCannotPublishIntoAnotherAccountRealmOrEpoch() async throws {
        let replacements: [PlayExperienceSession] = [
            try .init(accountID: 8, epoch: 1, namespace: "synthetic-cn", token: "synthetic-token"),
            try .init(accountID: 7, epoch: 1, namespace: "synthetic-us", token: "synthetic-token"),
            try .init(accountID: 7, epoch: 2, namespace: "synthetic-cn", token: "synthetic-token")
        ]
        for replacement in replacements {
            let (owner, wire, model) = try await setup(), original = try command()
            await model.submit(original)
            wire.receipts = [.value(receipt(original))]
            wire.beforeReceiptReply = { owner.session = replacement }
            await model.recover()
            XCTAssertEqual(model.phase, "stale"); XCTAssertEqual(model.pending, original)
            XCTAssertNil(model.projection); XCTAssertNil(model.receipt); XCTAssertFalse(model.hasCurrentProjection)
            let count = wire.requests.count
            await model.recover(); await model.retryExact(); await model.load()
            XCTAssertEqual(wire.requests.count, count)
        }
    }

    func testSupersededFailedReceiptCannotOverwriteNewerAppliedReadback() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        await model.submit(original)
        wire.receipts = [.value(receipt(original, outcome: "FAILED", revision: 2)), .value(receipt(original))]
        wire.views = [.value(try projection())]
        wire.beforeReceiptReply = { await model.load() }
        await model.recover()
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
        XCTAssertEqual(model.receipt?.outcome, "APPLIED"); XCTAssertEqual(model.projection?.revision, 3)
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testCancelledFirstSubmissionNeverCreatesPending() async throws {
        let (_, wire, model) = try await setup(), original = try command()
        let task = Task { await model.submit(original) }
        task.cancel(); await task.value
        XCTAssertNil(model.pending); XCTAssertEqual(model.phase, "ready"); XCTAssertTrue(wire.posts.isEmpty)
    }
}

@MainActor private final class ReceiptRecoveryWire: HTTPTransport {
    enum Reply {
        case value(PlayWireValue), businessError(Int), failure(PlayExperienceError)
        func result() throws -> (Data, Int) {
            let envelope: PlayWireValue
            switch self {
            case .value(let value): envelope = .object(["code": .int(200), "data": value])
            case .businessError(let code): envelope = .object(["code": .int(code), "msg": .string("Synthetic request failure"), "data": .null])
            case .failure(let error): throw error
            }
            return (try JSONEncoder().encode(envelope), 200)
        }
    }
    var commands: [Reply] = [], receipts: [Reply] = [], views: [Reply] = []
    var requests: [URLRequest] = []
    var beforeReceiptReply: (() async -> Void)?
    var posts: [URLRequest] { requests.filter { $0.httpMethod == "POST" } }
    var receiptRequests: [URLRequest] { requests.filter { $0.url?.path == "/api/game/session/receipt" } }
    var viewRequests: [URLRequest] { requests.filter { $0.url?.path == "/api/game/session/view" } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.path {
        case "/api/game/session/command":
            return try (commands.isEmpty ? .failure(.unknownResult) : commands.removeFirst()).result()
        case "/api/game/session/receipt":
            let reply: Reply = receipts.isEmpty ? .failure(.unknownResult) : receipts.removeFirst()
            if let hook = beforeReceiptReply { beforeReceiptReply = nil; await hook() }
            return try reply.result()
        case "/api/game/session/view":
            return try (views.isEmpty ? .value(try PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player)) : views.removeFirst()).result()
        default: XCTFail("Unexpected synthetic request"); throw PlayExperienceError.malformed
        }
    }
}
