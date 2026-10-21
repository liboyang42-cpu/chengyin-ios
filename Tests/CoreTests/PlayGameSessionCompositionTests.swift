import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class PlayGameSessionCompositionTests: XCTestCase {
    typealias Anchors = PlayDurableRecoveryTests.Anchors
    typealias Blobs = PlayDurableRecoveryTests.Blobs

    @MainActor private final class SessionBox {
        var session: PlayExperienceSession?
        init(_ session: PlayExperienceSession?) {
            self.session = session
        }
    }

    private static let approvedTestEndpoints: [RegionalMarket: Set<String>] = [
        .china: ["https://example.test"],
        .unitedStates: ["https://us.example.test"],
    ]

    private func makeRegional(
        market: RegionalMarket = .china,
        baseURL: String = "https://example.test"
    ) throws -> RegionalConfiguration {
        try RegionalConfiguration(
            market: market,
            baseURL: baseURL,
            approvedBaseURLs: Self.approvedTestEndpoints
        )
    }

    private func makeStorageScope(
        regional: RegionalConfiguration,
        bundleIdentifier: String = "com.questify.synthetic",
        realm: String = "cn-prod"
    ) throws -> RegionalSessionStorageScope {
        try RegionalSessionStorageScope(
            configuration: regional,
            bundleIdentifier: bundleIdentifier,
            realm: realm
        )
    }

    private func makeSession(
        accountID: Int = 7,
        epoch: UInt64 = 1,
        namespace: String,
        token: String = "synthetic-token",
        role: String = "player"
    ) throws -> PlayExperienceSession {
        try PlayExperienceSession(
            accountID: accountID,
            epoch: epoch,
            namespace: namespace,
            token: token,
            role: role
        )
    }

    private func makeService(_ wire: CompositionWire) throws -> PlayExperienceService {
        PlayExperienceService(
            configuration: try .init(baseURL: URL(string: "https://example.test")!),
            transport: wire,
            enabled: [.reads, .playerCommands]
        )
    }

    private func makeCommand(
        id: String = "a01-ready-71",
        revision: Int = 4
    ) throws -> PlayPlayerCommand {
        try PlayPlayerCommand(
            activityID: 41,
            nodeID: 701,
            requestID: id,
            expectedRevision: revision,
            action: .choice,
            payload: ["choiceId": .string("LEFT")]
        )
    }

    private func makeProjection(revision: Int = 4, sessionID: Int = 501) throws -> PlayWireValue {
        var value = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        value["revision"] = .int(revision)
        value["sessionId"] = .int(sessionID)
        return .object(value)
    }

    private func makeReceipt(
        _ command: PlayPlayerCommand,
        outcome: String = "APPLIED",
        revision: Int = 5
    ) -> PlayWireValue {
        .object([
            "activityId": .int(41),
            "requestId": .string(command.requestID),
            "action": .string(command.action.rawValue),
            "receiptId": .int(501),
            "outcome": .string(outcome),
            "revision": .int(revision),
            "replayed": .bool(false),
            "result": .object([:]),
        ])
    }

    func testUnconfiguredSessionRegionalOrStorageScopeFailsClosedAndReturnsNilCoordinator() throws {
        let anchors = Anchors()
        let blobs = Blobs()
        let wire = CompositionWire()
        let service = try makeService(wire)
        let regional = try makeRegional()
        let storageScope = try makeStorageScope(regional: regional)
        let validSession = try makeSession(namespace: storageScope.service)
        let box = SessionBox(validSession)

        // Missing service fails closed.
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: nil,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )

        // Non-activity or non-positive activity scopes fail closed.
        for invalidScope in [PlaySessionScope.topic(41), .activity(0), .activity(-3)] {
            XCTAssertNil(
                PlayGameSessionJournalFactory.makeCoordinator(
                    scope: invalidScope,
                    service: service,
                    regionalConfiguration: regional,
                    storageScope: storageScope,
                    currentSession: { box.session },
                    anchors: anchors,
                    ciphertexts: blobs
                )
            )
            XCTAssertThrowsError(
                try PlayGameSessionJournalFactory.makeJournal(
                    session: validSession,
                    scope: invalidScope,
                    regionalConfiguration: regional,
                    storageScope: storageScope,
                    anchors: anchors,
                    ciphertexts: blobs
                )
            ) { error in
                XCTAssertEqual(error as? PlayGameSessionCompositionError, .unsupportedScope)
            }
        }

        // Absent session, regionalConfiguration, or storageScope fails closed.
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { nil },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: nil,
                storageScope: storageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: nil,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: try RegionalConfiguration(market: .china),
                storageScope: storageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )

        // Mismatched storageScope or session namespace fails closed.
        let otherRegional = try makeRegional(market: .unitedStates, baseURL: "https://us.example.test")
        let otherStorageScope = try makeStorageScope(regional: otherRegional, realm: "us-prod")
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: otherStorageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        let mismatchedNamespaceSession = try makeSession(namespace: "wrong-namespace")
        XCTAssertThrowsError(
            try PlayGameSessionJournalFactory.makeJournal(
                session: mismatchedNamespaceSession,
                scope: .activity(41),
                regionalConfiguration: regional,
                storageScope: storageScope,
                anchors: anchors,
                ciphertexts: blobs
            )
        ) { error in
            XCTAssertEqual(error as? PlayGameSessionCompositionError, .sessionScopeMismatch)
        }

        // Unsupported role fails closed.
        let unsupportedRoleSession = try makeSession(namespace: storageScope.service, role: "spectator")
        XCTAssertThrowsError(
            try PlayGameSessionJournalFactory.makeJournal(
                session: unsupportedRoleSession,
                scope: .activity(41),
                regionalConfiguration: regional,
                storageScope: storageScope,
                anchors: anchors,
                ciphertexts: blobs
            )
        ) { error in
            XCTAssertEqual(error as? PlayGameSessionCompositionError, .unsupportedRole)
        }

        // Explicit session diverging from currentSession() or nil prebuilt journal fails closed.
        let secondSession = try makeSession(accountID: 8, namespace: storageScope.service)
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                session: secondSession,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        XCTAssertNil(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { box.session },
                journal: nil
            )
        )
    }

    func testConfiguredDurableStoreWiresCoordinatorAndPersistsPendingCommandAcrossRebuild() async throws {
        let anchors = Anchors()
        let blobs = Blobs()
        let wire = CompositionWire()
        let service = try makeService(wire)
        let regional = try makeRegional()
        let storageScope = try makeStorageScope(regional: regional)
        let initialSession = try makeSession(epoch: 1, namespace: storageScope.service, token: "token-epoch-1")
        let box = SessionBox(initialSession)
        let original = try makeCommand()

        wire.views = [.value(try makeProjection(revision: 4))]
        let firstCoordinator = try XCTUnwrap(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )

        await firstCoordinator.load()
        XCTAssertEqual(firstCoordinator.phase, "ready")

        await firstCoordinator.submit(original)
        XCTAssertEqual(firstCoordinator.phase, "unknown")
        XCTAssertEqual(firstCoordinator.pending, original)
        XCTAssertEqual(wire.posts.count, 1)

        // Simulate app restart / token refresh for the same account and regional scope.
        let refreshedSession = try makeSession(epoch: 2, namespace: storageScope.service, token: "token-epoch-2")
        box.session = refreshedSession
        let secondCoordinator = try XCTUnwrap(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { box.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )

        wire.receipts = [.value(makeReceipt(original, outcome: "PENDING", revision: 4))]
        await secondCoordinator.load()
        XCTAssertEqual(secondCoordinator.phase, "unknown")
        XCTAssertEqual(secondCoordinator.pending, original)
        XCTAssertEqual(wire.posts.count, 1)

        wire.commands = [.value(makeReceipt(original, outcome: "APPLIED", revision: 5))]
        wire.views = [.value(try makeProjection(revision: 5))]
        await secondCoordinator.retryExact()
        XCTAssertEqual(secondCoordinator.phase, "ready")
        XCTAssertNil(secondCoordinator.pending)
        XCTAssertEqual(secondCoordinator.projection?.revision, 5)
        XCTAssertEqual(wire.posts.count, 2)
        XCTAssertEqual(wire.posts.last?.value(forHTTPHeaderField: "Authorization"), refreshedSession.token)

        let store = try PlayGameSessionJournalFactory.makeJournal(
            session: refreshedSession,
            scope: .activity(41),
            regionalConfiguration: regional,
            storageScope: storageScope,
            anchors: anchors,
            ciphertexts: blobs
        )
        let key = PlayRunStorageKey.make(session: refreshedSession, scope: .activity(41))
        let remaining = try await store.readGameCommand(key)
        XCTAssertNil(remaining)
    }

    func testConfiguredRecoveryClosureIsolatesAccountsAndFailsClosedOnCrossRoleAlias() async throws {
        let anchors = Anchors()
        let blobs = Blobs()
        let wire = CompositionWire()
        let service = try makeService(wire)
        let regional = try makeRegional()
        let storageScope = try makeStorageScope(regional: regional)
        let playerA = try makeSession(accountID: 7, namespace: storageScope.service, role: "player")
        let playerB = try makeSession(accountID: 8, namespace: storageScope.service, role: "player")
        let merchantSameAccount = try makeSession(accountID: 7, namespace: storageScope.service, role: "merchant")
        let original = try makeCommand()

        let boxA = SessionBox(playerA)
        let coordinatorA = try XCTUnwrap(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { boxA.session },
                makeRecovery: { session, scope, _, _ in
                    try PlayDurableRecovery(
                        owner: .init(session: session),
                        key: PlayRunStorageKey.make(session: session, scope: scope),
                        anchors: anchors,
                        ciphertexts: blobs
                    )
                }
            )
        )
        wire.views = [.value(try makeProjection(revision: 4))]
        await coordinatorA.load()
        await coordinatorA.submit(original)
        XCTAssertEqual(coordinatorA.phase, "unknown")

        // Another account gets its own isolated slot and loads ready.
        let boxB = SessionBox(playerB)
        let coordinatorB = try XCTUnwrap(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { boxB.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        wire.views = [.value(try makeProjection(revision: 4))]
        await coordinatorB.load()
        XCTAssertEqual(coordinatorB.phase, "ready")
        XCTAssertNil(coordinatorB.pending)

        // Same account ID + namespace with a different role fails closed when reading the player's slot.
        let boxMerchant = SessionBox(merchantSameAccount)
        let merchantCoordinator = try XCTUnwrap(
            PlayGameSessionJournalFactory.makeCoordinator(
                scope: .activity(41),
                service: service,
                regionalConfiguration: regional,
                storageScope: storageScope,
                currentSession: { boxMerchant.session },
                anchors: anchors,
                ciphertexts: blobs
            )
        )
        await merchantCoordinator.load()
        XCTAssertEqual(merchantCoordinator.phase, "failed")
        XCTAssertEqual(merchantCoordinator.issue, .persistenceUnavailable)
    }
}

@MainActor private final class CompositionWire: HTTPTransport {
    enum Reply {
        case value(PlayWireValue)
        case failure(PlayExperienceError)

        func result() throws -> (Data, Int) {
            switch self {
            case .value(let value):
                let envelope: PlayWireValue = .object(["code": .int(200), "data": value])
                return (try JSONEncoder().encode(envelope), 200)
            case .failure(let error):
                throw error
            }
        }
    }

    var commands: [Reply] = []
    var receipts: [Reply] = []
    var views: [Reply] = []
    var requests: [URLRequest] = []

    var posts: [URLRequest] {
        requests.filter { $0.httpMethod == "POST" }
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.path {
        case "/api/game/session/command":
            return try (commands.isEmpty ? .failure(.unknownResult) : commands.removeFirst()).result()
        case "/api/game/session/receipt":
            return try (receipts.isEmpty ? .failure(.unknownResult) : receipts.removeFirst()).result()
        case "/api/game/session/view":
            return try (views.isEmpty ? .value(try PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player)) : views.removeFirst()).result()
        default:
            XCTFail("Unexpected synthetic request")
            throw PlayExperienceError.malformed
        }
    }
}
