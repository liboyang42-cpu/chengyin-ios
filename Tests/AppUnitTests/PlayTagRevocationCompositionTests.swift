import XCTest
@testable import Questify

/// Normal AppSession factory, synthetic auth/storage, no tag/read network approval fabricated.
@MainActor final class PlayTagRevocationCompositionTests: XCTestCase {
    private let base = URL(string: "https://summary-recovery.example/native")!
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.questify.summary-recovery", realm: "synthetic")
    }
    private func root(_ wire: Wire, recovery: PlayRecoveryConstruction) throws -> AppCompositionRoot {
        let suite = "summary-recovery-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        return .init(deployment: .reviewed(try deployment()), storage: .init(defaults: defaults,
            tokenStore: { _ in vault }, playRecovery: recovery), makeTransport: { wire },
            sessionDependencies: { _ in .dormant })
    }
    private func login(_ app: AppSession) async throws {
        app.authChannels.cancel()
        await app.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(app.account?.id, 7)
        guard app.account?.id == 7 else { throw APIError.malformedResponse }
    }
    private func seed(_ construction: PlayRecoveryConstruction, app: AppSession) async throws -> (PlayDurableRecovery, PlayTagRevocationRecoverySnapshot, String) {
        let deployment = try deployment()
        let owner = try PlayExperienceSession(accountID: 7, epoch: app.sessionRevision,
            namespace: deployment.storageScope.service, token: "synthetic-7", role: "player")
        let key = PlayRunStorageKey.make(session: owner, scope: .topic(71))
        let journal = try construction.make(session: owner, scope: .topic(71),
            regionalConfiguration: deployment.regional, storageScope: deployment.storageScope)
        let intent = try PlayTagRevocationIntent(session: owner, topicID: 71, tagID: 81)
        return (journal, try await journal.recordTagRevocation(intent, key: key), key)
    }
    func testNormalRootReopenRestoresTagMarkerWithoutGrantingAnyRequest() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), first = try root(wire, recovery: construction).makeSession(); try await login(first)
        let (journal, marker, key) = try await seed(construction, app: first)
        let model = try XCTUnwrap(first.playOperatingSummary(topicID: 71))
        XCTAssertTrue(model === first.playOperatingSummary(topicID: 71))
        await model.load(); XCTAssertEqual(model.unresolvedTagIDs, [81]); XCTAssertEqual(model.issue, .disabled)
        await first.logout()
        let reopened = try root(wire, recovery: construction).makeSession(); try await login(reopened)
        let restored = try XCTUnwrap(reopened.playOperatingSummary(topicID: 71)); XCTAssertFalse(restored === model)
        await restored.load(); await restored.revoke(tagID: 81); await model.revoke(tagID: 81)
        XCTAssertEqual(restored.unresolvedTagIDs, [81]); XCTAssertEqual(restored.issue, .disabled)
        let kept = try await journal.readTagRevocation(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.playRequests.isEmpty)
    }
    func testNormalRootUnavailableStorageShowsFailureWithoutMemoryFallback() async throws {
        let wire = Wire(), app = try root(wire, recovery: .unavailable).makeSession(); try await login(app)
        let model = try XCTUnwrap(app.playOperatingSummary(topicID: 71))
        await model.load(); await model.revoke(tagID: 81)
        XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertNil(model.summary)
        XCTAssertTrue(wire.playRequests.isEmpty)
    }
    func testRoleChangeCannotReadOrClearPlayerTagMarker() async throws {
        let construction = PlayRecoveryConstruction.synthetic(anchors: Anchors(), ciphertexts: Blobs())
        let wire = Wire(), app = try root(wire, recovery: construction).makeSession(); try await login(app)
        let (journal, marker, key) = try await seed(construction, app: app)
        let original = try XCTUnwrap(app.playOperatingSummary(topicID: 71)); await original.load()
        wire.role = "merchant"; await app.refreshOwnAccount()
        let other = try XCTUnwrap(app.playOperatingSummary(topicID: 71)); await other.load()
        XCTAssertEqual(other.issue, .persistenceUnavailable); XCTAssertNil(other.summary)
        await original.revoke(tagID: 81); await other.revoke(tagID: 81)
        wire.role = "player"; await app.refreshOwnAccount()
        let returned = try XCTUnwrap(app.playOperatingSummary(topicID: 71)); await returned.load()
        XCTAssertFalse(returned === original); XCTAssertEqual(returned.unresolvedTagIDs, [81])
        let kept = try await journal.readTagRevocation(key); XCTAssertEqual(kept, marker)
        XCTAssertTrue(wire.playRequests.isEmpty)
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], role = "player"
        var playRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/play/") == true } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url?.lastPathComponent {
            case "phone": return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7}}"#.utf8), 200)
            case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
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
        var values: [String: Data] = [:], presence: Set<String> = []
        func createPresence(slot: String) -> Bool { presence.insert(slot).inserted }
        func hasPresence(slot: String) -> Bool { presence.contains(slot) }
        func insert(name: String, bytes: Data) throws {
            guard values[name] == nil else { throw ContentDraftIssue.storageUnavailable }; values[name] = bytes
        }
        func readDurably(name: String, limit: Int) throws -> Data {
            guard let value = values[name], value.count <= limit else { throw ContentDraftIssue.storageUnavailable }; return value
        }
        func removeDurably(name: String) { values[name] = nil }
    }
}
