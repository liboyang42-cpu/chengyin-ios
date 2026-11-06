import XCTest
@testable import Questify

/// Exercises the normal AppSession factory. Synthetic auth/storage only; no runtime grant.
@MainActor final class PlayPlayerJournalCompositionTests: XCTestCase {
    private let base = URL(string: "https://player-recovery.example/native")!
    private func deployment(realm: String = "synthetic") throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.questify.player-recovery", realm: realm)
    }
    private func root(_ wire: Wire, recovery: PlayRecoveryConstruction, realm: String = "synthetic") throws -> AppCompositionRoot {
        let suite = "player-recovery-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        return .init(deployment: .reviewed(try deployment(realm: realm)), storage: .init(defaults: defaults,
            tokenStore: { _ in vault }, playRecovery: recovery), makeTransport: { wire },
            sessionDependencies: { _ in .dormant })
    }
    private func login(_ app: AppSession, accountID: Int = 7) async throws {
        app.authChannels.cancel()
        await app.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(app.account?.id, accountID)
        guard app.account?.id == accountID else { throw APIError.malformedResponse }
    }
    private func command(_ requestID: String = "original-player-attempt") throws -> PlayPlayerCommand {
        try .init(activityID: 41, nodeID: 701, requestID: requestID, expectedRevision: 4,
            action: .choice, payload: ["choiceId": .string("LEFT")])
    }
    private func seed(_ construction: PlayRecoveryConstruction, app: AppSession) async throws -> (PlayDurableRecovery, PlayGameCommandJournalSnapshot, String) {
        let deployment = try deployment()
        let owner = try PlayExperienceSession(accountID: 7, epoch: app.sessionRevision,
            namespace: deployment.storageScope.service, token: "synthetic-7", role: "player")
        let key = PlayRunStorageKey.make(session: owner, scope: .activity(41))
        let journal = try construction.make(session: owner, scope: .activity(41),
            regionalConfiguration: deployment.regional, storageScope: deployment.storageScope)
        let pending = try PlayPendingGameCommand(command: command(), session: owner, sessionID: 501)
        return (journal, try await journal.recordGameCommand(pending, key: key), key)
    }
    func testAnonymousAndInvalidScopeHaveNoPlayerCoordinatorOrRequest() async throws {
        let wire = Wire(), app = try root(wire, recovery: .unavailable).makeSession()
        XCTAssertNil(app.playPlayer(scope: .activity(41)))
        try await login(app)
        XCTAssertNil(app.playPlayer(scope: .topic(41)))
        XCTAssertNil(app.playPlayer(scope: .activity(0)))
        XCTAssertNil(app.playPlayer(scope: .activity(-1)))
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    func testNormalFactoryRestoresExactEnvelopeAndReusesOneCoordinatorWithoutGrant() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), app = try root(wire, recovery: construction).makeSession(); try await login(app)
        let (journal, marker, key) = try await seed(construction, app: app)
        let model = try XCTUnwrap(app.playPlayer(scope: .activity(41)))
        XCTAssertTrue(model === app.playPlayer(scope: .activity(41)))
        await model.load()
        XCTAssertEqual(model.pending, try command()); XCTAssertEqual(model.phase, "unknown")
        XCTAssertEqual(model.issue, .disabled); XCTAssertNil(model.projection)
        await model.submit(try command("replacement-is-forbidden")); await model.retryExact(); await model.recover()
        XCTAssertEqual(model.pending, try command()); XCTAssertEqual(model.phase, "unknown")
        let kept = try await journal.readGameCommand(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    func testFreshRootAndLoginRestoreJournalWithoutPostingOriginalCommand() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), first = try root(wire, recovery: construction).makeSession(); try await login(first)
        let (journal, marker, key) = try await seed(construction, app: first)
        let old = try XCTUnwrap(first.playPlayer(scope: .activity(41))); await old.load()
        await first.logout(); XCTAssertFalse(old.hasCurrentProjection)
        let reopened = try root(wire, recovery: construction).makeSession(); try await login(reopened)
        let restored = try XCTUnwrap(reopened.playPlayer(scope: .activity(41)))
        XCTAssertFalse(restored === old); await restored.load()
        await old.retryExact(); await old.recover()
        XCTAssertEqual(restored.pending, try command()); XCTAssertEqual(restored.phase, "unknown")
        let kept = try await journal.readGameCommand(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    func testUnavailableConstructionNeverFallsBackToMemoryCoordinator() async throws {
        let wire = Wire(), app = try root(wire, recovery: .unavailable).makeSession(); try await login(app)
        XCTAssertNil(app.playPlayer(scope: .activity(41)))
        XCTAssertNil(app.playPlayer(scope: .activity(41)))
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    func testUnreadableDurableStoreBlocksLoadWithoutNewCommand() async throws {
        let blobs = Blobs(), construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: blobs)
        let wire = Wire(), app = try root(wire, recovery: construction).makeSession(); try await login(app)
        let (journal, marker, key) = try await seed(construction, app: app)
        await blobs.setUnreadable(true)
        let model = try XCTUnwrap(app.playPlayer(scope: .activity(41))); await model.load()
        XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertTrue(model.localRecoveryFailed)
        XCTAssertNil(model.pending); XCTAssertNil(model.projection)
        await model.submit(try command("must-not-overwrite")); XCTAssertTrue(wire.gameRequests.isEmpty)
        await blobs.setUnreadable(false); await model.load()
        XCTAssertEqual(model.pending, try command()); XCTAssertEqual(model.phase, "unknown")
        let kept = try await journal.readGameCommand(key); XCTAssertEqual(kept, marker)
    }
    func testRoleChangeAndReturnCannotReviveOldViewerOrAdoptForeignRoleJournal() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), app = try root(wire, recovery: construction).makeSession(); try await login(app)
        let (journal, marker, key) = try await seed(construction, app: app)
        let original = try XCTUnwrap(app.playPlayer(scope: .activity(41))); await original.load()
        wire.role = "merchant"; await app.refreshOwnAccount()
        let merchant = try XCTUnwrap(app.playPlayer(scope: .activity(41))); await merchant.load()
        XCTAssertFalse(merchant === original)
        XCTAssertEqual(merchant.issue, .persistenceUnavailable); XCTAssertNil(merchant.pending)
        wire.role = "club"; await app.refreshOwnAccount()
        let club = try XCTUnwrap(app.playPlayer(scope: .activity(41))); await club.load()
        XCTAssertEqual(club.issue, .persistenceUnavailable); XCTAssertNil(club.pending)
        wire.role = "player"; await app.refreshOwnAccount()
        let returned = try XCTUnwrap(app.playPlayer(scope: .activity(41)))
        XCTAssertFalse(returned === original); XCTAssertFalse(original.hasCurrentProjection)
        await returned.load(); await original.retryExact(); await merchant.retryExact(); await club.retryExact()
        XCTAssertEqual(returned.pending, try command()); XCTAssertEqual(returned.phase, "unknown")
        let kept = try await journal.readGameCommand(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    func testDifferentAccountDoesNotAdoptOrReleaseOriginalOwnersPendingCommand() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), first = try root(wire, recovery: construction).makeSession(); try await login(first)
        let (journal, marker, key) = try await seed(construction, app: first)
        let original = try XCTUnwrap(first.playPlayer(scope: .activity(41))); await original.load(); await first.logout(); XCTAssertFalse(original.hasCurrentProjection)
        wire.accountID = 8
        let second = try root(wire, recovery: construction).makeSession(); try await login(second, accountID: 8)
        let other = try XCTUnwrap(second.playPlayer(scope: .activity(41))); await other.load()
        XCTAssertNil(other.pending); XCTAssertEqual(other.issue, .disabled)
        await original.retryExact(); await other.submit(try command("other-account"))
        let kept = try await journal.readGameCommand(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    func testDifferentRealmDoesNotAdoptOriginalJournal() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), first = try root(wire, recovery: construction).makeSession(); try await login(first)
        let (journal, marker, key) = try await seed(construction, app: first)
        let other = try root(wire, recovery: construction, realm: "isolated-synthetic").makeSession(); try await login(other)
        let model = try XCTUnwrap(other.playPlayer(scope: .activity(41))); await model.load()
        XCTAssertNil(model.pending); XCTAssertEqual(model.issue, .disabled)
        let kept = try await journal.readGameCommand(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.gameRequests.isEmpty)
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], role = "player", accountID = 7
        var gameRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/game/") == true } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url?.lastPathComponent {
            case "phone": return (Data("{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID)}}".utf8), 200)
            case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}".utf8), 200)
            case "logout": return (Data(#"{"code":200}"#.utf8), 200)
            default: XCTFail("Unapproved request reached normal-root recorder"); throw APIError.invalidRequest
            }
        }
    }
    private actor Anchors: ContentDraftAnchorStore {
        var values: [String: ContentDraftAnchorItem] = [:]
        func read(slot: String) throws -> ContentDraftAnchorItem? { values[slot] }
        func insert(slot: String, item: ContentDraftAnchorItem) throws -> Bool {
            guard values[slot] == nil else { return false }; values[slot] = item; return true
        }
        func exchange(slot: String, matchingTag: Data, item: ContentDraftAnchorItem) throws -> Bool {
            guard values[slot]?.tag == matchingTag else { return false }; values[slot] = item; return true
        }
    }
    private actor Blobs: ContentDraftCiphertextStore {
        var values: [String: Data] = [:], presence: Set<String> = [], unreadable = false
        func setUnreadable(_ value: Bool) { unreadable = value }
        func createPresence(slot: String) -> Bool { presence.insert(slot).inserted }
        func hasPresence(slot: String) -> Bool { presence.contains(slot) }
        func insert(name: String, bytes: Data) throws {
            guard values[name] == nil else { throw ContentDraftIssue.storageUnavailable }; values[name] = bytes
        }
        func readDurably(name: String, limit: Int) throws -> Data {
            guard !unreadable, let value = values[name], value.count <= limit else { throw ContentDraftIssue.storageUnavailable }; return value
        }
        func removeDurably(name: String) { values[name] = nil }
    }
}
