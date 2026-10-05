import XCTest
@testable import Questify

@MainActor final class PublicTemplateDetailAppTests: XCTestCase {
    /// Synthetic OTP exchange plus authoritative session read; never exercises a provider.
    private func signIn(_ session: AppSession, recorder: AuthWire, expectSuccess: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) async {
        if session.account != nil { await session.logout() }
        session.authChannels.cancel()
        let before = recorder.requests.count
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        guard expectSuccess else { return }
        XCTAssertNotNil(session.account, "Synthetic login must succeed before feature assertions", file: file, line: line)
        XCTAssertTrue(session.authChannels.state.signedIn, file: file, line: line)
        XCTAssertEqual(recorder.requests.dropFirst(before).map { $0.url?.path },
            ["/native/api/login/phone", "/native/api/userInfo"], file: file, line: line)
    }

    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data("{\"code\":200,\"data\":\(PublicTopicTemplateFixtures.content())}".utf8), 200)
        }
    }
    func testNormalSessionDetailRemainsDormantWithoutReviewedDeployment() async throws {
        let wire = Wire()
        let session = AppSession(runtimeDependencies: .init(transport: wire))
        let detail = session.publicTopicTemplateCoordinator(id: 801)
        await detail.load()
        XCTAssertNil(detail.value)
        XCTAssertNotNil(detail.error)
        XCTAssertTrue(wire.requests.isEmpty)
    }

    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class AuthWire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let json = request.url?.lastPathComponent == "phone"
                ? #"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#
                : request.url?.lastPathComponent == "userInfo"
                    ? #"{"code":200,"appUser":{"userId":7,"role":"player"}}"#
                    : #"{"code":200}"#
            return (Data(json.utf8), 200)
        }
    }
    private func authenticatedSession() async throws -> (AppSession, Vault, UserDefaults, String) {
        let suite = "public-template-session-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault(), wire = AuthWire()
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://example.test/native",
            approvedBaseURLs: [.china: ["https://example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.public-template", realm: "synthetic", reads: [])
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        let session = root.makeSession()
        await signIn(session, recorder: wire)
        XCTAssertEqual(session.account?.id, 7)
        XCTAssertEqual(wire.requests.count, 2)
        return (session, vault, defaults, deployment.storageScope.restoreBlockedKey)
    }
    private func payload(_ name: String = "Fresh") throws -> PublicTopicTemplateDetail {
        try JSONDecoder().decode(PublicTopicTemplateDetail.self,
            from: Data("{\"id\":801,\"name\":\"\(name)\"}".utf8))
    }
    func testSupersededUnauthorizedCannotExpireSessionOrEraseFreshDetail() async throws {
        let (session, vault, defaults, tombstone) = try await authenticatedSession()
        let started = expectation(description: "Older detail read suspended")
        var pending: CheckedContinuation<PublicTopicTemplateDetail, Error>?
        var calls = 0
        let fresh = try payload()
        let detail = session.makePublicTopicTemplateCoordinator(id: 801) { _ in
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
            }
            return fresh
        }
        let old = Task { await detail.load() }
        await fulfillment(of: [started], timeout: 2)
        await detail.load()
        pending?.resume(throwing: APIError.unauthorized)
        await old.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        XCTAssertEqual(detail.value?.name, "Fresh"); XCTAssertNil(detail.error)
        XCTAssertFalse(detail.isInvalidated); XCTAssertFalse(defaults.bool(forKey: tombstone))
    }
    func testDismissedUnauthorizedCannotExpireSessionAndReopenStillLoads() async throws {
        let (session, vault, _, _) = try await authenticatedSession()
        let started = expectation(description: "Dismissed detail read suspended")
        var pending: CheckedContinuation<PublicTopicTemplateDetail, Error>?
        var calls = 0
        let fresh = try payload()
        let detail = session.makePublicTopicTemplateCoordinator(id: 801) { _ in
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
            }
            return fresh
        }
        let old = Task { await detail.load() }
        await fulfillment(of: [started], timeout: 2)
        detail.clear()
        pending?.resume(throwing: APIError.unauthorized)
        await old.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        XCTAssertNil(detail.value); XCTAssertNil(detail.error); XCTAssertFalse(detail.isInvalidated)
        await detail.load()
        XCTAssertEqual(detail.value?.name, "Fresh")
    }
    func testCanceledUnauthorizedCannotExpireSession() async throws {
        let (session, vault, _, _) = try await authenticatedSession()
        let started = expectation(description: "Canceled detail read suspended")
        var pending: CheckedContinuation<PublicTopicTemplateDetail, Error>?
        let detail = session.makePublicTopicTemplateCoordinator(id: 801) { _ in
            try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        let old = Task { await detail.load() }
        await fulfillment(of: [started], timeout: 2)
        old.cancel()
        pending?.resume(throwing: APIError.unauthorized)
        await old.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        XCTAssertNil(detail.value); XCTAssertNil(detail.error); XCTAssertFalse(detail.isInvalidated)
    }
    func testCurrentUnauthorizedStillExpiresSessionAndInvalidatesProjection() async throws {
        let (session, vault, defaults, tombstone) = try await authenticatedSession()
        let detail = session.makePublicTopicTemplateCoordinator(id: 801) { _ in throw APIError.unauthorized }
        await detail.load()
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertTrue(defaults.bool(forKey: tombstone)); XCTAssertTrue(detail.isInvalidated)
        XCTAssertNil(detail.value); XCTAssertNil(detail.error); XCTAssertFalse(detail.isLoading)
    }
}
