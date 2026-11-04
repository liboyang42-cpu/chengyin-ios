import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class PlayPlayerAdmissionSafetyTests: XCTestCase {
    private let configuration = try! APIConfiguration(baseURL: URL(string: "https://example.test")!)

    private func owner() throws -> PlayExperienceSession {
        try .init(accountID: 7, epoch: 1, namespace: "synthetic-l5", token: "synthetic-token")
    }
    private func row(_ status: String = "REJECTED", id: Int = 91, node: Int = 701,
                     task: String = "OBSERVE") -> PlayWireValue {
        .object(["submissionId": .int(id), "nodeId": .int(node), "taskCode": .string(task), "status": .string(status)])
    }
    private func projection(history: PlayWireValue? = .array([]), input: String = "TEXT",
                            taskCode: String = "OBSERVE", revision: Int = 2) throws -> PlayWireValue {
        var root = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        var player = try XCTUnwrap(root["player"]?.object)
        var nodes = try XCTUnwrap(player["nodes"]?.array)
        var node = try XCTUnwrap(nodes[0].object)
        var task = try XCTUnwrap(node["playerTask"]?.object)
        task["inputType"] = .string(input); task["taskCode"] = .string(taskCode)
        node["playerTask"] = .object(task); nodes[0] = .object(node)
        player["nodes"] = .array(nodes); player["mySubmissions"] = history
        root["player"] = .object(player); root["revision"] = .int(revision)
        return .object(root)
    }
    private func command(taskCode: String = "OBSERVE", requestID: String = "l5-original-attempt") throws -> PlayPlayerCommand {
        try .init(activityID: 41, nodeID: 701, requestID: requestID, expectedRevision: 2, action: .submit,
                  payload: ["taskCode": .string(taskCode), "evidenceUrls": .array([.string("text:synthetic")])])
    }
    private func service(_ wire: AdmissionWire, lifetime: PlayInteractionLifetime? = nil) -> PlayExperienceService {
        .init(configuration: configuration, transport: wire, enabled: [.reads, .playerCommands], readLifetime: lifetime)
    }
    private func model(_ wire: AdmissionWire, session: PlayExperienceSession,
                       lifetime: PlayInteractionLifetime? = nil, journal: (any PlayGameCommandJournal)? = nil) -> PlayPlayerGameCoordinator {
        .init(activityID: 41, service: service(wire, lifetime: lifetime), currentSession: { session }, journal: journal)
    }
    private func lifetimeRoot(_ owner: PlayExperienceSession) async throws -> (PlayExperienceCoordinator, PlayInteractionLifetime) {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(
            #"{"mode":1,"topicId":71,"registered":true,"playable":true,"nodes":[{"nodeId":701,"done":false,"arrived":true,"validationMethod":6}]}"#), 200)
        let root = PlayExperienceCoordinator(scope: .activity(41),
            service: .init(configuration: configuration, transport: wire, enabled: [.reads]),
            recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner })
        await root.load()
        return (root, try XCTUnwrap(root.makeInteractionLifetime()))
    }
    private func assertEvidenceBlocked(_ raw: PlayWireValue, file: StaticString = #filePath, line: UInt = #line) async throws {
        let wire = AdmissionWire(projection: raw), session = try owner(), journal = AdmissionJournal()
        let player = model(wire, session: session, journal: journal)
        await player.load()
        XCTAssertThrowsError(try player.evidenceTarget(nodeID: 701), file: file, line: line)
        await player.submit(try command())
        XCTAssertEqual(journal.writes, 0, file: file, line: line)
        XCTAssertEqual(wire.posts.count, 0, file: file, line: line)
        XCTAssertNil(player.pending, file: file, line: line)
    }

    func testMissingNullAndMalformedHistoryNeverBecomePermissionToSubmit() throws {
        let malformed: [PlayWireValue?] = [nil, .null, .string("not an array"), .object([:]), .bool(false), .int(0)]
        for history in malformed {
            let value = try PlayPlayerGameProjection(projection(history: history))
            XCTAssertTrue(value.submissions.isEmpty, "Keep the legacy decoded rows; constrain admission separately")
            XCTAssertFalse(value.allows(try command()))
        }
    }
    func testMalformedHistoryBlocksBothCameraAndAlbumBeforeJournalOrCommand() async throws {
        for input in ["SCAN", "PHOTO"] {
            let histories: [PlayWireValue?] = [nil, .null, .object([:])]
            for history in histories {
                try await assertEvidenceBlocked(projection(history: history, input: input))
            }
        }
    }
    func testConfirmedEmptyHistoryPreservesTextScanAndPhotoReview() async throws {
        XCTAssertTrue(try PlayPlayerGameProjection(projection()).allows(command()))
        for input in ["SCAN", "PHOTO"] {
            let wire = AdmissionWire(projection: try projection(input: input)), session = try owner()
            let player = model(wire, session: session)
            await player.load()
            let target = try player.evidenceTarget(nodeID: 701)
            XCTAssertTrue(player.acceptsEvidence(target))
            if input == "SCAN" { XCTAssertNoThrow(try player.reviewEvidence(target, scan: "synthetic-code")) }
            else { XCTAssertNoThrow(try player.reviewEvidence(target, photo: .photo(uploadedURL: "https://example.test/photo"))) }
            XCTAssertTrue(wire.posts.isEmpty)
        }
    }
    func testExactNewestRejectionPermitsRetryWithoutReplacingServerOrder() throws {
        let value = try PlayPlayerGameProjection(projection(history: .array([row(id: 92), row("APPROVED", id: 91)])))
        XCTAssertTrue(value.allows(try command()))
        XCTAssertEqual(value.submissions.first?["submissionId"].integer, 92)
    }
    func testExactRejectedHistoryStillPermitsCameraAndAlbumEvidence() async throws {
        for input in ["SCAN", "PHOTO"] {
            let wire = AdmissionWire(projection: try projection(history: .array([row()]), input: input))
            let player = model(wire, session: try owner())
            await player.load()
            let target = try player.evidenceTarget(nodeID: 701)
            XCTAssertTrue(player.acceptsEvidence(target))
            XCTAssertTrue(wire.posts.isEmpty)
        }
    }
    func testPendingApprovedAndRecordedDoNotAdmitAnotherSubmission() async throws {
        for status in ["PENDING", "APPROVED", "RECORDED"] {
            let raw = try projection(history: .array([row(status)]), input: "PHOTO")
            XCTAssertFalse(try PlayPlayerGameProjection(raw).allows(command()))
            try await assertEvidenceBlocked(raw)
        }
    }
    func testUnknownNewestRecordCannotFallBackToOlderRejection() throws {
        for status in ["UNKNOWN", "", "rejected"] {
            let value = try PlayPlayerGameProjection(projection(history: .array([row(status, id: 92), row(id: 91)])))
            XCTAssertFalse(value.allows(try command()))
        }
    }
    func testDuplicateUnorderedOrMalformedIdentitiesBlockNewEvidence() async throws {
        let histories: [[PlayWireValue]] = [[row(), row()], [row(id: 90), row(id: 91)],
            [row(id: 0)], [row(node: 0)], [.string("not a row")], [.object(["status": .string("REJECTED")])]]
        for history in histories {
            try await assertEvidenceBlocked(projection(history: .array(history), input: "SCAN"))
        }
    }
    func testAnotherTasksRejectionDoesNotPermitCurrentTaskSubmission() throws {
        let value = try PlayPlayerGameProjection(projection(history: .array([row(task: "ANOTHER_TASK")])))
        XCTAssertFalse(value.allows(try command()))
    }
    func testOtherNodeHistoryDoesNotBlockConfirmedEmptyCurrentTask() throws {
        let value = try PlayPlayerGameProjection(projection(history: .array([row("APPROVED", node: 702)])))
        XCTAssertTrue(value.allows(try command()))
    }
    func testTaskIdentifiersUseExactUTF8ForCommandAndRejection() throws {
        let composed = "CAF\u{00e9}", decomposed = "CAFe\u{0301}"
        XCTAssertEqual(composed, decomposed, "Swift canonical equality is not wire identity")
        XCTAssertFalse(try PlayPlayerGameProjection(projection(taskCode: composed)).allows(command(taskCode: decomposed)))
        let rejected = try PlayPlayerGameProjection(projection(history: .array([row(task: decomposed)]), taskCode: composed))
        XCTAssertFalse(rejected.allows(try command(taskCode: composed)))
        let exact = try PlayPlayerGameProjection(projection(history: .array([row(task: composed)]), taskCode: composed))
        XCTAssertTrue(exact.allows(try command(taskCode: composed)))
    }
    func testExpiredReadLifetimeStopsReviewAndDirectSubmissionBeforePersistence() async throws {
        let session = try owner(), (root, lifetime) = try await lifetimeRoot(session)
        let wire = AdmissionWire(projection: try projection()), journal = AdmissionJournal()
        let player = model(wire, session: session, lifetime: lifetime, journal: journal)
        await player.load()
        let context = try player.capturePlayerActionReview()
        let review = try player.preparePlayerActionReview(context, intent: .text(nodeID: 701, answer: "synthetic"))
        await root.load()
        XCTAssertFalse(lifetime.isCurrent); XCTAssertFalse(player.hasCurrentProjection)
        XCTAssertFalse(player.acceptsPlayerActionReview(context)); XCTAssertFalse(player.acceptsPlayerActionReview(review))
        XCTAssertThrowsError(try player.capturePlayerActionReview())
        await player.submitPlayerActionReview(review); await player.submit(try command()); await player.load()
        XCTAssertEqual(journal.writes, 0); XCTAssertNil(player.pending); XCTAssertEqual(wire.requests.count, 1)
    }
    func testExpiredReadLifetimeStopsCameraAndAlbumTargetsImmediately() async throws {
        for input in ["SCAN", "PHOTO"] {
            let session = try owner(), (root, lifetime) = try await lifetimeRoot(session)
            let wire = AdmissionWire(projection: try projection(input: input))
            let player = model(wire, session: session, lifetime: lifetime)
            await player.load()
            let target = try player.evidenceTarget(nodeID: 701), context = try player.captureEvidenceReview(target)
            await root.load()
            XCTAssertFalse(player.acceptsEvidence(target)); XCTAssertFalse(player.acceptsEvidenceReview(context))
            XCTAssertThrowsError(try player.evidenceTarget(nodeID: 701))
            XCTAssertThrowsError(try player.reviewEvidence(target, scan: "synthetic"))
            XCTAssertTrue(wire.posts.isEmpty)
        }
    }
    func testLifetimeExpiryDuringJournalWriteKeepsOriginalWithoutDispatch() async throws {
        let session = try owner(), (root, lifetime) = try await lifetimeRoot(session)
        let wire = AdmissionWire(projection: try projection()), journal = AdmissionJournal(), original = try command()
        let player = model(wire, session: session, lifetime: lifetime, journal: journal)
        await player.load(); journal.afterWrite = { await root.load() }
        await player.submit(original)
        XCTAssertEqual(journal.writes, 1); XCTAssertEqual(journal.clears, 0)
        XCTAssertEqual(try journal.saved?.value.command(), original)
        XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown"); XCTAssertTrue(wire.posts.isEmpty)
        await player.recover(); await player.retryExact()
        XCTAssertTrue(wire.posts.isEmpty); XCTAssertEqual(journal.clears, 0)
    }
    func testUnknownOriginalSurvivesLeaseExpiryAndFreshCoordinatorReadsReceiptOnly() async throws {
        let session = try owner(), (root, lifetime) = try await lifetimeRoot(session)
        let wire = AdmissionWire(projection: try projection()), journal = AdmissionJournal(), original = try command()
        wire.unknownCommand = true
        let player = model(wire, session: session, lifetime: lifetime, journal: journal)
        await player.load(); await player.submit(original)
        let saved = journal.saved
        await root.load(); await player.recover(); await player.retryExact()
        XCTAssertEqual(journal.saved, saved); XCTAssertEqual(wire.posts.count, 1)
        XCTAssertEqual(player.pending, original); XCTAssertFalse(player.hasCurrentProjection)
        let freshLifetime = try XCTUnwrap(root.makeInteractionLifetime())
        let reopened = model(wire, session: session, lifetime: freshLifetime, journal: journal)
        wire.readReceipt = .object(["activityId": .int(41), "requestId": .string(original.requestID), "outcome": .string("PENDING")])
        await reopened.load()
        XCTAssertEqual(reopened.pending, original); XCTAssertEqual(reopened.phase, "unknown")
        XCTAssertEqual(wire.posts.count, 1); XCTAssertEqual(journal.saved, saved)
        let receipt = try XCTUnwrap(wire.requests.last)
        XCTAssertEqual(receipt.url?.path, "/api/game/session/receipt")
        XCTAssertTrue(URLComponents(url: try XCTUnwrap(receipt.url), resolvingAgainstBaseURL: false)?.queryItems?
            .contains(.init(name: "requestId", value: original.requestID)) == true)
    }
    func testLateProjectionAfterLeaseExpiryCannotPublishReadyFacts() async throws {
        let session = try owner(), (root, lifetime) = try await lifetimeRoot(session)
        let wire = AdmissionWire(projection: try projection())
        wire.beforeView = { await root.load() }
        let player = model(wire, session: session, lifetime: lifetime)
        await player.load()
        XCTAssertNil(player.projection); XCTAssertFalse(player.hasCurrentProjection)
        XCTAssertNotEqual(player.phase, "ready"); XCTAssertTrue(wire.posts.isEmpty)
    }
    func testAccountSwitchRejectsPreparedReviewWithoutMovingOriginalJournal() async throws {
        let originalOwner = try owner()
        var current: PlayExperienceSession? = originalOwner
        let wire = AdmissionWire(projection: try projection()), journal = AdmissionJournal()
        let player = PlayPlayerGameCoordinator(activityID: 41, service: service(wire), currentSession: { current }, journal: journal)
        await player.load()
        let context = try player.capturePlayerActionReview()
        let review = try player.preparePlayerActionReview(context, intent: .text(nodeID: 701, answer: "synthetic"))
        current = try .init(accountID: 8, epoch: 2, namespace: "synthetic-l5", token: "synthetic-other-token")
        XCTAssertFalse(player.hasCurrentProjection); XCTAssertFalse(player.acceptsPlayerActionReview(review))
        await player.submitPlayerActionReview(review); await player.submit(try command())
        XCTAssertEqual(journal.writes, 0); XCTAssertTrue(wire.posts.isEmpty)
    }
    func testValidSubmissionStillPersistsThenReadsAppliedProjectionAndClears() async throws {
        let session = try owner(), wire = AdmissionWire(projection: try projection()), journal = AdmissionJournal()
        let player = model(wire, session: session, journal: journal)
        await player.load()
        let original = try command()
        wire.beforeCommand = { XCTAssertEqual(try journal.saved?.value.command(), original) }
        await player.submit(original)
        XCTAssertEqual(wire.posts.count, 1); XCTAssertEqual(journal.writes, 1); XCTAssertEqual(journal.clears, 1)
        XCTAssertEqual(player.phase, "ready"); XCTAssertNil(player.pending); XCTAssertNil(journal.saved)
        XCTAssertEqual(player.receipt?.requestID, original.requestID)
        XCTAssertEqual(wire.requests.map { $0.url?.path }, ["/api/game/session/view", "/api/game/session/command", "/api/game/session/view"])
    }
}

@MainActor private final class AdmissionWire: HTTPTransport {
    var projection: PlayWireValue
    var requests: [URLRequest] = []
    var posts: [URLRequest] { requests.filter { $0.httpMethod == "POST" } }
    var unknownCommand = false
    var readReceipt: PlayWireValue = .null
    var beforeView: (() async -> Void)?
    var beforeCommand: (() throws -> Void)?
    init(projection: PlayWireValue) { self.projection = projection }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let value: PlayWireValue
        switch request.url?.path {
        case "/api/game/session/view":
            await beforeView?(); value = projection
        case "/api/game/session/receipt": value = readReceipt
        case "/api/game/session/command":
            try beforeCommand?()
            if unknownCommand { throw PlayExperienceError.unknownResult }
            let command = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request.httpBody))
            value = .object(["activityId": command["activityId"], "requestId": command["requestId"],
                             "action": command["action"], "outcome": .string("APPLIED"), "receiptId": .int(901),
                             "revision": .int(2), "result": .object([:])])
        default: XCTFail("Unexpected request"); throw PlayExperienceError.malformed
        }
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": value])), 200)
    }
}

@MainActor private final class AdmissionJournal: PlayGameCommandJournal {
    var saved: PlayGameCommandJournalSnapshot?
    var writes = 0, clears = 0
    var afterWrite: (() async -> Void)?
    func readGameCommand(_ key: String) async throws -> PlayGameCommandJournalSnapshot? { saved }
    func recordGameCommand(_ value: PlayPendingGameCommand, key: String) async throws -> PlayGameCommandJournalSnapshot {
        guard saved == nil else { throw PlayExperienceError.persistenceUnavailable }
        writes += 1
        let record = PlayGameCommandJournalSnapshot(value: value, generation: Data(UUID().uuidString.utf8))
        saved = record; await afterWrite?(); return record
    }
    func clearGameCommand(_ snapshot: PlayGameCommandJournalSnapshot, key: String) async throws {
        guard saved == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        clears += 1; saved = nil
    }
}
