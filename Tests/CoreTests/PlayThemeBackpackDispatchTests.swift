import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Offline route/permit tests. Never constructs the OS factory or grants a system seal.
@MainActor final class PlayThemeBackpackDispatchTests: XCTestCase {
    private let base = URL(string: "https://fixture.example/")!
    private func session(account: Int = 11, epoch: UInt64 = 1, namespace: String = "fixture-backpack",
                         role: String = "player", token: String = "fixture-token") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role)
    }
    private func read(_ suffix: String = "api/play/theme/state?activityId=0&topicId=7") -> URLRequest {
        var request = URLRequest(url: URL(string: suffix, relativeTo: base)!.absoluteURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("fixture-token", forHTTPHeaderField: "Authorization")
        return request
    }
    private func validate(_ request: URLRequest, scope: PlaySessionScope = .topic(7), topicID: Int = 7) throws {
        try PlayThemeBackpackReadRoute.validate(request, baseURL: base, session: session(), scope: scope, topicID: topicID)
    }
    private struct Harness {
        let session: PlayExperienceSession
        let store: PlayThemeBackpackRecoveryStore
        let snapshot: PlayThemeBackpackRecoverySnapshot
        let request: URLRequest
    }
    private func harness(completed: Bool = false, contentID: String = "tea") async throws -> Harness {
        let owner = try session()
        let store = try PlayThemeBackpackRecoveryStore(session: owner, scope: .topic(7), topicID: 7,
            anchors: BackpackRecoveryTestAnchors(), ciphertexts: BackpackRecoveryTestCiphertexts())
        let command = try PlayThemeBackpackCommand(sessionID: 41, version: 3,
            operation: completed ? .receive : .use, contentID: contentID,
            discardOwned: completed ? [] : nil, actionID: "bag_exact")
        let intent = try PlayThemeBackpackIntent(session: owner, scope: .topic(7), topicID: 7,
            command: command, requiresCompletedReceive: completed)
        let prepared = try await store.prepare(intent)
        let dispatching = try await store.transition(prepared, to: .dispatching)
        var request = URLRequest(url: base.appendingPathComponent("api/play/theme/action"))
        request.httpMethod = "POST"; request.httpBody = intent.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("fixture-token", forHTTPHeaderField: "Authorization")
        return .init(session: owner, store: store, snapshot: dispatching, request: request)
    }
    private func permit(_ h: Harness, current: @escaping () throws -> Void = {}) -> PlayThemeBackpackDispatchPermit {
        .init(session: h.session, snapshot: h.snapshot, recovery: h.store, baseURL: base, checkCurrent: current)
    }
    private func rejected(_ expected: PlayExperienceError? = nil, _ operation: () async throws -> Void,
                          file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected rejection", file: file, line: line) }
        catch { if let expected { XCTAssertEqual(error as? PlayExperienceError, expected, file: file, line: line) } }
    }

    func testCanonicalSelfPlayReadIncludesExplicitZero() throws {
        XCTAssertNoThrow(try validate(read()))
        XCTAssertNoThrow(try validate(read("api/play/theme/state?activityId=0&sessionId=41&topicId=7")))
    }
    func testCanonicalActivityReadMatchesBothTopicAndActivity() throws {
        XCTAssertNoThrow(try validate(read("api/play/theme/state?activityId=9&topicId=7"), scope: .activity(9)))
        XCTAssertNoThrow(try validate(read("api/play/theme/state?activityId=9&sessionId=41&topicId=7"), scope: .activity(9)))
        XCTAssertThrowsError(try validate(read(), scope: .activity(9)))
        XCTAssertThrowsError(try validate(read("api/play/theme/state?activityId=9&topicId=7")))
        XCTAssertThrowsError(try validate(read(), scope: .topic(8)))
        XCTAssertThrowsError(try validate(read(), topicID: 8))
        XCTAssertThrowsError(try validate(read(), scope: .activity(0)))
    }
    func testReadRejectsMissingDuplicateExtraAndNoncanonicalQuery() throws {
        for query in ["topicId=7", "activityId=0", "activityId=0&topicId=7&topicId=7",
                      "activityId=0&topicId=7&extra=1", "activityId=0&topicId=7&sessionId=0",
                      "activityId=0&topicId=7&sessionId=-1", "activityId=0&topicId=7&sessionId=041",
                      "activityId=0&topicId=7&sessionId=+41", "activityId=0&topicId=7&sessionId=1.0",
                      "activityId=0&topicId=7&sessionId", "activityId=0&topicId=7&sessionId=",
                      "activityId=00&topicId=7", "activityId=0&topicId=07", "topicId=7&activityId=0",
                      "activityId=0&%74opicId=7", "activityId=0&topicId=%37",
                      "activityId=0&sessionId=999999999999999999999999&topicId=7"] {
            XCTAssertThrowsError(try validate(read("api/play/theme/state?" + query)), query)
        }
    }
    func testReadRejectsForeignOriginPathCredentialsAndFragment() throws {
        for suffix in ["https://other.example/api/play/theme/state?activityId=0&topicId=7",
                       "https://fixture.example:444/api/play/theme/state?activityId=0&topicId=7",
                       "https://user@fixture.example/api/play/theme/state?activityId=0&topicId=7",
                       "api/play/theme/action?activityId=0&topicId=7",
                       "api/play/theme/state/?activityId=0&topicId=7",
                       "api/play/theme/%73tate?activityId=0&topicId=7",
                       "api/play/theme/state?activityId=0&topicId=7#fragment"] {
            XCTAssertThrowsError(try validate(read(suffix)), suffix)
        }
    }
    func testReadRejectsMethodBodyStreamAndHeaderChanges() throws {
        var request = read(); request.httpMethod = "POST"; XCTAssertThrowsError(try validate(request))
        request = read(); request.httpBody = Data(); XCTAssertThrowsError(try validate(request))
        request = read(); request.httpBodyStream = InputStream(data: Data("x".utf8)); XCTAssertThrowsError(try validate(request))
        request = read(); request.setValue(nil, forHTTPHeaderField: "Accept"); XCTAssertThrowsError(try validate(request))
        request = read(); request.setValue("other-token", forHTTPHeaderField: "Authorization"); XCTAssertThrowsError(try validate(request))
        request = read(); request.setValue(nil, forHTTPHeaderField: "Authorization"); XCTAssertThrowsError(try validate(request))
    }
    func testReadAuthorizationIsComparedWithSuppliedSession() throws {
        let changed = try session(token: "other-token")
        XCTAssertThrowsError(try PlayThemeBackpackReadRoute.validate(read(), baseURL: base, session: changed, scope: .topic(7), topicID: 7))
    }
    func testPermitPropertiesComeOnlyFromOriginalIntent() async throws {
        let h = try await harness(completed: true)
        let ticket = permit(h)
        XCTAssertEqual(ticket.session, h.session); XCTAssertEqual(ticket.scope, .topic(7))
        XCTAssertEqual(ticket.topicID, 7); XCTAssertTrue(ticket.requiresCompletedReceive)
        let active = try await harness(); XCTAssertFalse(permit(active).requiresCompletedReceive)
    }
    func testInjectedStoreNeverConfersProductionDispatchAuthority() async throws {
        let h = try await harness(), ticket = permit(h)
        await rejected(.persistenceUnavailable) { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session) }
        let stored = try await h.store.read(); XCTAssertEqual(stored, h.snapshot)
        XCTAssertFalse(h.store.permitsSystemDispatch(to: base))
    }
    func testFailedConsumeIsOneUseAndDoesNotRecheckOrWriteOnSecondCall() async throws {
        let h = try await harness(); var checks = 0
        let ticket = permit(h, current: { checks += 1; throw PlayExperienceError.staleSession })
        await rejected(.staleSession) { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session) }
        XCTAssertEqual(checks, 1)
        await rejected(.invalidAction) { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session) }
        XCTAssertEqual(checks, 1)
        let stored = try await h.store.read(); XCTAssertEqual(stored, h.snapshot)
    }
    func testPublicCurrentCheckStillRejectsLateResponseAfterConsumeFailed() async throws {
        let h = try await harness(); var current = true
        let ticket = permit(h, current: { if !current { throw PlayExperienceError.staleSession } })
        XCTAssertNoThrow(try ticket.checkCurrent())
        await rejected(.persistenceUnavailable) { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session) }
        current = false; XCTAssertThrowsError(try ticket.checkCurrent())
    }
    func testPermitRejectsAccountRoleEpochNamespaceAndTokenSubstitution() async throws {
        let h = try await harness()
        let owners = [try session(account: 12), try session(epoch: 2), try session(namespace: "other"),
                      try session(role: "merchant"), try session(token: "other-token")]
        for owner in owners {
            let ticket = permit(h)
            await rejected(.invalidAction) { try await ticket.consume(request: h.request, baseURL: self.base, session: owner) }
        }
        let stored = try await h.store.read(); XCTAssertEqual(stored, h.snapshot)
    }
    func testPermitRejectsChangedEndpointAndRequestBodyBeforeStorage() async throws {
        let h = try await harness()
        let ticket = permit(h)
        await rejected(.invalidAction) { try await ticket.consume(request: h.request, baseURL: URL(string: "https://other.example/")!, session: h.session) }
        var changed = h.request; changed.httpBody = Data("{}".utf8)
        let second = permit(h)
        await rejected(.invalidAction) { try await second.consume(request: changed, baseURL: self.base, session: h.session) }
        changed = h.request; changed.httpBody = h.request.httpBody! + Data(" ".utf8)
        let third = permit(h)
        await rejected(.invalidAction) { try await third.consume(request: changed, baseURL: self.base, session: h.session) }
    }
    func testPermitRejectsQueryFragmentMethodStreamAndWrongHeaders() async throws {
        let h = try await harness()
        var invalid: [URLRequest] = []
        var r = h.request; r.url = URL(string: "https://fixture.example/api/play/theme/action?topicId=7")!; invalid.append(r)
        r = h.request; r.url = URL(string: "https://fixture.example/api/play/theme/action#x")!; invalid.append(r)
        r = h.request; r.url = URL(string: "https://fixture.example/api/play/theme/state")!; invalid.append(r)
        r = h.request; r.httpMethod = "GET"; invalid.append(r)
        r = h.request; r.httpBodyStream = InputStream(data: h.request.httpBody!); invalid.append(r)
        for name in ["Accept", "Content-Type", "Authorization"] { r = h.request; r.setValue("wrong", forHTTPHeaderField: name); invalid.append(r) }
        for request in invalid {
            let ticket = permit(h)
            await rejected(.invalidAction) { try await ticket.consume(request: request, baseURL: self.base, session: h.session) }
        }
    }
    func testCanonicalEquivalentUnicodeCannotReplaceOriginalBody() async throws {
        let h = try await harness(contentID: "e\u{301}")
        let other = try PlayThemeBackpackCommand(sessionID: 41, version: 3, operation: .use,
            contentID: "é", discardOwned: nil, actionID: "bag_exact")
        var changed = h.request; changed.httpBody = try other.encodedBody()
        XCTAssertNotEqual(changed.httpBody, h.request.httpBody)
        let ticket = permit(h)
        await rejected(.invalidAction) { try await ticket.consume(request: changed, baseURL: self.base, session: h.session) }
    }
    func testASecondPermitCannotTurnSyntheticStorageIntoProduction() async throws {
        let h = try await harness()
        for _ in 0..<2 {
            let ticket = permit(h)
            await rejected(.persistenceUnavailable) { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session) }
        }
        let stored = try await h.store.read(); XCTAssertEqual(stored, h.snapshot)
    }
    func testCancelledPermitCannotDispatchAndCancellationDoesNotClearJournal() async throws {
        let h = try await harness(), ticket = permit(h)
        let work = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session); return false }
            catch { return error is CancellationError }
        }
        let cancelled = await work.value; XCTAssertTrue(cancelled)
        let stored = try await h.store.read(); XCTAssertEqual(stored, h.snapshot)
        await rejected(.invalidAction) { try await ticket.consume(request: h.request, baseURL: self.base, session: h.session) }
    }
}
