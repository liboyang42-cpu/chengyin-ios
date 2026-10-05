import XCTest
@testable import Questify

@MainActor final class ActivityListScopeRecoveryTests: XCTestCase {
    private func rows(_ ids: [Int]) throws -> [ActivitySummary] {
        try ids.map { try JSONDecoder().decode(ActivitySummary.self, from: Data("{\"id\":\($0),\"name\":\"Synthetic activity\"}".utf8)) }
    }
    func testAppliedQueryRawPagingAndReplacementViewerReset() async throws {
        let reader = Reader(), model = ActivityListModel(); reader.rows = try rows(Array(1...10))
        await model.load(reader: reader, reset: true, keyword: "applied")
        XCTAssertEqual(model.page, 1); XCTAssertTrue(model.hasMore)
        reader.rows = try rows([10, 11]); await model.load(reader: reader, reset: false, keyword: "unsubmitted")
        XCTAssertEqual(model.items.map(\.id), Array(1...11)); XCTAssertEqual(model.page, 2)
        XCTAssertEqual(reader.queries.map { $0.keyword }, ["applied", "applied"])
        reader.revision += 1; reader.rows = try rows([71])
        await model.load(reader: reader, reset: false, keyword: "")
        XCTAssertEqual(model.items.map(\.id), [71]); XCTAssertEqual(model.page, 1)
        XCTAssertEqual(reader.queries.last?.page, 1)
    }
    func testOldSuccessAnd401CannotReplaceLoadedNewViewerAfterABA() async throws {
        for unauthorized in [false, true] {
            let reader = Reader(), model = ActivityListModel(); reader.suspend = true
            let started = expectation(description: "Old model read"); reader.onPaused = { started.fulfill() }
            let old = Task { await model.load(reader: reader, reset: true, keyword: "old") }
            await fulfillment(of: [started], timeout: 2)
            guard reader.hasPending else { old.cancel(); return XCTFail("No suspended read") }
            reader.revision += 2; reader.suspend = false; reader.rows = try rows([72])
            await model.load(reader: reader, reset: true, keyword: "new")
            reader.finish(unauthorized ? .failure(APIError.unauthorized) : .success(try rows([71]))); await old.value
            XCTAssertEqual(model.items.map(\.id), [72]); XCTAssertFalse(model.failed); XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.identity, ActivityListReadIdentity(reader))
        }
    }
    func testDismissalCancelsOwnedReadWithoutDisplayingLate401() async throws {
        let reader = Reader(), model = ActivityListModel(), owner = SignedInContentDetailLoadOwner(); reader.suspend = true
        let started = expectation(description: "Owned read"); reader.onPaused = { started.fulfill() }
        let task = owner.start { await model.load(reader: reader, reset: true, keyword: "") }
        await fulfillment(of: [started], timeout: 2)
        guard reader.hasPending else { task.cancel(); return XCTFail("No suspended read") }
        owner.cancel(); model.cancelPending(); reader.finish(.failure(APIError.unauthorized)); await task.value
        XCTAssertTrue(model.items.isEmpty); XCTAssertFalse(model.failed); XCTAssertFalse(model.isLoading)
    }
    func testReaderInstanceAndUnavailableGrantCannotReuseOldCache() async throws {
        let first = Reader(), second = Reader(), model = ActivityListModel()
        first.rows = try rows([71]); second.rows = try rows([72])
        XCTAssertEqual(first.activityPresentationIdentity, second.activityPresentationIdentity)
        XCTAssertNotEqual(ActivityListReadIdentity(first), ActivityListReadIdentity(second))
        await model.load(reader: first, reset: true, keyword: "")
        await model.load(reader: second, reset: false, keyword: "")
        XCTAssertEqual(model.items.map(\.id), [72]); XCTAssertEqual(model.page, 1)
        second.activityListIsConfigured = false
        await model.load(reader: second, reset: false, keyword: "")
        XCTAssertEqual(second.queries.count, 1); XCTAssertTrue(model.items.isEmpty); XCTAssertFalse(model.failed)
    }
    @MainActor private final class Reader: ActivityReading {
        let isConfigured = true
        var activityListIsConfigured = true, suspend = false
        var revision = 1
        var activityPresentationIdentity: String { "viewer-\(revision)" }
        var rows: [ActivitySummary] = []
        var queries: [(page: Int, keyword: String)] = []
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<[ActivitySummary], Error>?
        var hasPending: Bool { pending != nil }
        func finish(_ value: Result<[ActivitySummary], Error>) { let c = pending; pending = nil; c?.resume(with: value) }
        func activities(page: Int, keyword: String) async throws -> [ActivitySummary] {
            queries.append((page, keyword))
            if suspend { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return rows
        }
        func activityDetail(id: Int) async throws -> ActivityDetailAccess { throw APIError.notConfigured }
    }
}

@MainActor final class ActivityNormalReadRecoveryTests: XCTestCase {
    private func session(_ wire: Wire, _ vault: Vault, approved: Bool = true) throws -> AppSession {
        let base = "https://example.com/native", suite = "activity-scope-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base, approvedBaseURLs: [.china: [base]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.questify.activity", realm: "synthetic",
            reads: approved ? [.homeAndSearch] : [])
        return AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }).makeSession()
    }
    private func signIn(_ session: AppSession) async {
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    func testGuestLoginRoleABAAndLogoutKeepPublicListAuthority() async throws {
        let wire = Wire(), vault = Vault(), session = try session(wire, vault)
        let guest = ActivityListReadIdentity(session); XCTAssertTrue(session.activityListIsConfigured)
        _ = try await session.activities(page: 1, keyword: "")
        XCTAssertNil(wire.requests.last?.value(forHTTPHeaderField: "Authorization"))
        await signIn(session); let player = ActivityListReadIdentity(session); XCTAssertNotEqual(player, guest)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNotEqual(ActivityListReadIdentity(session), player)
        _ = try await session.activities(page: 1, keyword: "")
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        await session.logout(); XCTAssertTrue(session.activityListIsConfigured)
        XCTAssertNotEqual(ActivityListReadIdentity(session), guest)
        _ = try await session.activities(page: 1, keyword: "")
        XCTAssertNil(wire.requests.last?.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(vault.token)
    }
    func testAuthenticationAndMountedServiceDoNotCreateListGrant() async throws {
        let wire = Wire(), vault = Vault(), session = try session(wire, vault, approved: false), model = ActivityListModel()
        await signIn(session); XCTAssertTrue(session.isConfigured); XCTAssertFalse(session.activityListIsConfigured)
        XCTAssertEqual(session.activityListUnavailableMessageKey, "readConfiguration.activityListReadNotApproved")
        let before = wire.requests.count
        await model.load(reader: session, reset: true, keyword: "")
        do { _ = try await session.activities(page: 1, keyword: ""); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testRoleABAOwnerExitAndCancellationRejectLateSuccessAndBoth401Forms() async throws {
        for transition in ["role", "roleABA", "logout", "cancel"] {
            for result in 0...2 {
                let wire = Wire(), vault = Vault(), session = try session(wire, vault)
                await signIn(session); wire.suspend = true
                let started = expectation(description: "Old activity \(transition) \(result)"); wire.onPaused = { started.fulfill() }
                let task = Task { try await session.activities(page: 1, keyword: "") }
                await fulfillment(of: [started], timeout: 2)
                guard wire.hasPending else { task.cancel(); return XCTFail("No suspended read") }
                if transition == "cancel" { task.cancel() }
                else if transition == "logout" { await session.logout() }
                else { wire.role = "merchant"; await session.refreshOwnAccount(); if transition == "roleABA" { wire.role = "player"; await session.refreshOwnAccount() } }
                wire.finish(result)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertNotEqual(session.errorKey, "auth.expired")
                if transition == "logout" { XCTAssertNil(session.account); XCTAssertNil(vault.token) }
                else { XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.token, "synthetic-7") }
            }
        }
    }
    func testCurrentHTTPAndEnvelope401StillExpireCurrentOwner() async throws {
        for result in 1...2 {
            let wire = Wire(), vault = Vault(), session = try session(wire, vault)
            await signIn(session); wire.result = result
            do { _ = try await session.activities(page: 1, keyword: ""); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertNil(session.account); XCTAssertNil(vault.token); XCTAssertEqual(session.errorKey, "auth.expired")
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", suspend = false, result = 0
        var requests: [URLRequest] = []
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        var hasPending: Bool { pending != nil }
        func response(_ result: Int) -> (Data, Int) {
            (Data((result == 2 ? #"{"code":401}"# : #"{"code":200,"data":{"rows":[{"id":21,"name":"Synthetic activity"}]}}"#).utf8), result == 1 ? 401 : 200)
        }
        func finish(_ result: Int) { let c = pending; pending = nil; c?.resume(returning: response(result)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url?.path ?? "", json: String
            if path.hasSuffix("/phone") { json = #"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"# }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/activity/list") {
                if suspend { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
                return response(result)
            } else { json = #"{"code":200,"data":[]}"# }
            return (Data(json.utf8), 200)
        }
    }
}
