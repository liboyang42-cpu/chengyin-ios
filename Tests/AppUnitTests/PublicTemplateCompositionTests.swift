import XCTest
@testable import Questify

/// Actual normal composition and real DiscoveryService requests, with no URLSession or vault.
@MainActor final class PublicTemplateCompositionTests: XCTestCase {
    /// Synthetic OTP exchange plus authoritative session read; never exercises a provider.
    private func signIn(_ session: AppSession, recorder: Wire, expectSuccess: Bool = true,
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

    private static let base = "https://example.test/native"
    private static let catalog = "/api/template/topic-template/list"
    private static let detail = "/api/template/topic-template/info"
    private typealias Identity = CompositionHTTPTransport.SessionIdentity
    private let guest = Identity(epoch: 0, accountID: nil, role: nil, token: nil)

    private func deployment(reads: Set<ReviewedAppDeployment.ReadGrant> = [.publicTopicTemplateCatalogAndDetail],
                            auth: Bool = false) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: Self.base, approvedBaseURLs: [.china: [Self.base]],
            verifiedCapabilities: auth ? [.domesticChinaPhone] : [],
            bundleIdentifier: "test.questify.public-catalog", realm: "synthetic", reads: reads)
    }
    private func makeSession(_ wire: Wire, reads: Set<ReviewedAppDeployment.ReadGrant> = [.publicTopicTemplateCatalogAndDetail],
                         auth: Bool = false) throws -> (AppSession, Vault) {
        let suite = "public-catalog-composition-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = Vault()
        let root = AppCompositionRoot(deployment: .reviewed(try deployment(reads: reads, auth: auth)),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        return (root.makeSession(), vault)
    }
    private func catalogRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: Self.base + Self.catalog)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return request
    }
    private func detailRequest(id: String = "801", token: String? = nil) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: URL(string: Self.base + Self.detail)!,
            fields: ["id": id], token: token, boundary: "public-template-test")
    }
    private func loadCatalog(_ loader: DiscoveryLoader<[DiscoveryTopicTemplate]>, session: AppSession) async {
        let request = session.publicTopicTemplateCatalogRequest()
        await loader.load(onUnauthorized: request.onUnauthorized, request.read)
    }
    private func assertBlocked(_ request: URLRequest, transport: CompositionHTTPTransport,
                               wire: Wire, file: StaticString = #filePath, line: UInt = #line) async {
        let before = wire.requests.count
        do { _ = try await transport.send(request); XCTFail("Unreviewed request dispatched", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError || error as? APIError == .notConfigured, file: file, line: line) }
        XCTAssertEqual(wire.requests.count, before, file: file, line: line)
    }

    func testNormalGuestSessionReadsOnlyCatalogAndPublicDetailWithoutAuthenticationGrant() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire)
        await session.bootstrap()
        let rows = try await session.discoveryTopicTemplates()
        XCTAssertEqual(rows.map(\.id), [801]); XCTAssertEqual(rows.first?.locationCount, 9)
        let detail = session.publicTopicTemplateCoordinator(id: 801)
        await detail.load()
        XCTAssertEqual(detail.value?.id, 801); XCTAssertEqual(detail.value?.locationCount, 9)
        XCTAssertNil(detail.value?.chapters.first?.recruitStatus)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native" + Self.catalog, "/native" + Self.detail])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(wire.requests.first?.httpBody, Data("{}".utf8))
        XCTAssertTrue(String(data: try XCTUnwrap(wire.requests.last?.httpBody), encoding: .utf8)!.contains("name=\"id\"\r\n\r\n801\r\n"))
    }
    func testAuthenticatedContextUsesCurrentTokenAndServerViewerFlagsOnly() async throws {
        let wire = Wire(); let (session, _) = try makeSession(wire, auth: true)
        wire.role = "merchant"
        await signIn(session, recorder: wire)
        XCTAssertEqual(session.account?.id, 7)
        _ = try await session.discoveryTopicTemplates()
        // A local merchant role does not grant recruitment when the server flags are false.
        let ordinary = try await session.discoveryTopicTemplateDetail(id: 801)
        XCTAssertNil(ordinary.chapters.first?.recruitStatus)
        wire.viewerIsMerchant = true
        let projected = try await session.discoveryTopicTemplateDetail(id: 801)
        XCTAssertNotNil(projected.chapters.first?.recruitStatus)
        XCTAssertTrue(wire.requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
    }
    func testMissingPublicGrantAndHomeGrantCannotDispatchPublicReads() async throws {
        let grantSets: [Set<ReviewedAppDeployment.ReadGrant>] = [[], [.homeAndSearch]]
        for grants in grantSets {
            let wire = Wire(); let (session, _) = try makeSession(wire, reads: grants, auth: true)
            do { _ = try await session.discoveryTopicTemplates(); XCTFail() } catch {}
            await session.publicTopicTemplateCoordinator(id: 801).load()
            XCTAssertTrue(wire.requests.isEmpty)
            await signIn(session, recorder: wire)
            let before = wire.requests.count
            do { _ = try await session.discoveryTopicTemplateDetail(id: 801); XCTFail() } catch {}
            do { _ = try await session.discoveryTopicTemplates(); XCTFail() } catch {}
            XCTAssertEqual(wire.requests.count, before)
        }
    }
    func testPublicGrantDoesNotImplyHomePrivateOrStandaloneGameReadsOrWrites() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        for path in ["/api/category/list", "/api/topic/list", "/api/topic/info", "/api/topic/node/info",
                     "/api/template/homeData", "/api/template/list", "/api/template/info", "/api/template/myinfo",
                     "/api/template/topic-template/use", "/api/template/topic-template/club-interest",
                     "/api/template/topic-template/publish", "/" + PrivateHomeService.path] {
            var request = catalogRequest(); request.url = URL(string: Self.base + path)
            await assertBlocked(request, transport: transport, wire: wire)
        }
    }
    func testPrivateHomeReadStillRequiresItsIndependentOwnerGrant() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { Identity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        var request = URLRequest(url: URL(string: Self.base + "/" + PrivateHomeService.path)!)
        request.httpMethod = "GET"; request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
        await assertBlocked(request, transport: transport, wire: wire)
    }
    func testWrongVerbPathQueryFragmentAndRealmMakeZeroDispatches() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        for original in [catalogRequest(), try detailRequest()] {
            for method in ["GET", "PUT", "DELETE", "PATCH", "HEAD"] {
                var request = original; request.httpMethod = method
                await assertBlocked(request, transport: transport, wire: wire)
            }
            let exact = original.url!.absoluteString
            for url in [exact + "/", exact + "?id=801", exact + "?", exact + "#x",
                        exact + "%3Fid=801", exact.replacingOccurrences(of: "topic-template", with: "%74opic-template"),
                        exact.replacingOccurrences(of: "/native/", with: "/other/"),
                        exact.replacingOccurrences(of: "example.test", with: "elsewhere.test"),
                        exact.replacingOccurrences(of: "https:", with: "http:")] {
                var request = original; request.url = try XCTUnwrap(URL(string: url))
                await assertBlocked(request, transport: transport, wire: wire)
            }
        }
    }
    func testUnexpectedCatalogBodyAndDetailFieldsAreRejected() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { self.guest }
        let catalogBodies: [Data?] = [nil, Data(), Data("[]".utf8), Data("{\"recommendedOnly\":1}".utf8), Data("{}\n".utf8)]
        for body in catalogBodies {
            var request = catalogRequest(); request.httpBody = body
            await assertBlocked(request, transport: transport, wire: wire)
        }
        for id in ["0", "-1", "01", "+1", " 1", "1\n", "801&id=802", "9223372036854775808"] {
            await assertBlocked(try detailRequest(id: id), transport: transport, wire: wire)
        }
        var extra = try AuthRequestBuilder.makeFormRequest(url: URL(string: Self.base + Self.detail)!,
            fields: ["id": "801", "scope": "merchant"], token: nil, boundary: "extra-field")
        await assertBlocked(extra, transport: transport, wire: wire)
        extra = try detailRequest()
        let original = try XCTUnwrap(String(data: try XCTUnwrap(extra.httpBody), encoding: .utf8))
        extra.httpBody = Data(original.replacingOccurrences(of: "--public-template-test--\r\n",
            with: "--public-template-test\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n802\r\n--public-template-test--\r\n").utf8)
        await assertBlocked(extra, transport: transport, wire: wire)
        for original in [catalogRequest(), try detailRequest()] {
            var request = original; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            await assertBlocked(request, transport: transport, wire: wire)
            request = original; request.httpBodyStream = InputStream(data: Data("{}".utf8))
            await assertBlocked(request, transport: transport, wire: wire)
        }
        var malformed = try detailRequest()
        malformed.setValue("multipart/form-data; boundary=wrong", forHTTPHeaderField: "Content-Type")
        await assertBlocked(malformed, transport: transport, wire: wire)
    }
    func testStaleCredentialsAndPartialGuestIdentityAreRejectedBeforeDispatch() async throws {
        let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        let member = Identity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        transport.current = { member }
        await assertBlocked(try detailRequest(), transport: transport, wire: wire)
        await assertBlocked(try detailRequest(token: "stale-7"), transport: transport, wire: wire)
        transport.current = { self.guest }
        await assertBlocked(try detailRequest(token: "synthetic-7"), transport: transport, wire: wire)
        for partial in [Identity(epoch: 0, accountID: nil, role: nil, token: "synthetic-7"),
                        Identity(epoch: 0, accountID: nil, role: "merchant", token: nil),
                        Identity(epoch: 0, accountID: 7, role: "player", token: nil)] {
            transport.current = { partial }
            var request = catalogRequest(); request.setValue(partial.token, forHTTPHeaderField: "Authorization")
            await assertBlocked(request, transport: transport, wire: wire)
        }
    }
    func testGuestCompletionCannotPopulateAuthenticatedContextAndLogoutClearsProjection() async throws {
        let wire = Wire(); let (session, _) = try makeSession(wire, auth: true)
        wire.pauseNextDetail = true
        let started = expectation(description: "Guest detail suspended")
        wire.onPaused = { started.fulfill() }
        let old = session.publicTopicTemplateCoordinator(id: 801)
        let read = Task { await old.load() }
        await fulfillment(of: [started], timeout: 2)
        await signIn(session, recorder: wire)
        wire.viewerIsMerchant = true
        let fresh = session.publicTopicTemplateCoordinator(id: 801)
        await fresh.load()
        wire.resume(status: 401)
        await read.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertTrue(old.isInvalidated); XCTAssertNil(old.value)
        XCTAssertNotNil(fresh.value?.chapters.first?.recruitStatus)
        await session.logout()
        XCTAssertTrue(fresh.isInvalidated); XCTAssertNil(fresh.value)
        wire.viewerIsMerchant = false
        let guest = session.publicTopicTemplateCoordinator(id: 801)
        await guest.load()
        XCTAssertEqual(guest.value?.id, 801); XCTAssertNil(guest.value?.chapters.first?.recruitStatus)
        XCTAssertNil(wire.requests.last?.value(forHTTPHeaderField: "Authorization"))
    }
    func testAccountRoleAndTokenABARejectLate401AndSuccess() async throws {
        // Return to the same account/role/token after an intervening identity: epoch must fence ABA.
        for status in [200, 401] {
            let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
            await signIn(session, recorder: wire)
            wire.pauseNextDetail = true
            let started = expectation(description: "Authenticated detail suspended")
            wire.onPaused = { started.fulfill() }
            let old = session.publicTopicTemplateCoordinator(id: 801)
            let read = Task { await old.load() }
            await fulfillment(of: [started], timeout: 2)
            wire.accountID = 8; wire.role = "merchant"; wire.token = "synthetic-8"
            await signIn(session, recorder: wire)
            wire.accountID = 7; wire.role = "player"; wire.token = "synthetic-7"
            await signIn(session, recorder: wire)
            let fresh = session.publicTopicTemplateCoordinator(id: 801)
            await fresh.load()
            wire.resume(status: status)
            await read.value
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
            XCTAssertTrue(old.isInvalidated); XCTAssertNil(old.value); XCTAssertNil(old.error)
            XCTAssertEqual(fresh.value?.id, 801); XCTAssertNil(fresh.error)
        }
    }
    func testCatalogLateUnauthorizedCannotExpireChangedSession() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        wire.pauseNextCatalog = true
        let started = expectation(description: "Catalog suspended")
        wire.onPaused = { started.fulfill() }
        let read = Task { try await session.discoveryTopicTemplates() }
        await fulfillment(of: [started], timeout: 2)
        wire.role = "merchant"; wire.token = "new-token"
        await signIn(session, recorder: wire)
        wire.resume(status: 401)
        do { _ = try await read.value; XCTFail("Old catalog response accepted") }
        catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "new-token")
    }
    func testRoleOnlyRefreshABAFencesCatalogSuccessAndUnauthorized() async throws {
        // Unlike login(), /userInfo refresh changes role without advancing the login gate.
        for status in [200, 401] {
            let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
            await signIn(session, recorder: wire)
            wire.pauseNextCatalog = true
            let started = expectation(description: "Catalog suspended before role refresh")
            wire.onPaused = { started.fulfill() }
            let read = Task { try await session.discoveryTopicTemplates() }
            await fulfillment(of: [started], timeout: 2)
            wire.role = "merchant"
            await session.refreshOwnAccount()
            XCTAssertEqual(session.account?.effectiveRole, "merchant")
            wire.role = "player"
            await session.refreshOwnAccount()
            XCTAssertEqual(session.account?.effectiveRole, "player")
            XCTAssertEqual(wire.requests.filter { $0.url?.path.hasSuffix("/api/login/phone") == true }.count, 1)
            XCTAssertEqual(wire.requests.filter { $0.url?.path.hasSuffix("/api/userInfo") == true }.count, 3)
            wire.resume(status: status)
            do { _ = try await read.value; XCTFail("Role-refresh ABA accepted old catalog completion") }
            catch is CancellationError {} catch { XCTFail("\(error)") }
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
            XCTAssertNil(session.errorKey)
            let fresh = try await session.discoveryTopicTemplates()
            XCTAssertEqual(fresh.map(\.id), [801])
        }
    }
    func testCurrentCatalogUnauthorizedStillExpiresNormalSession() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        wire.catalogStatus = 401
        do { _ = try await session.discoveryTopicTemplates(); XCTFail("Current unauthorized response accepted") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(session.errorKey, "auth.expired")
    }
    func testSupersededCatalogLoaderUnauthorizedCannotExpireSessionOrEraseNewSuccess() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        let loader = DiscoveryLoader<[DiscoveryTopicTemplate]>()
        wire.pauseNextCatalog = true
        let started = expectation(description: "Older loader catalog suspended")
        wire.onPaused = { started.fulfill() }
        let old = Task { await self.loadCatalog(loader, session: session) }
        await fulfillment(of: [started], timeout: 2)
        await loadCatalog(loader, session: session)
        XCTAssertEqual(loader.value?.map(\.id), [801]); XCTAssertFalse(loader.isLoading)
        wire.resume(status: 401)
        await old.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        XCTAssertEqual(loader.value?.map(\.id), [801]); XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading); XCTAssertNil(session.errorKey)
        // A current accepted failure still expires the session through the same loader.
        wire.catalogStatus = 401
        await loadCatalog(loader, session: session)
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(loader.error as? APIError, .unauthorized); XCTAssertFalse(loader.isLoading)
    }
    func testCanceledCatalogLoaderCannotExpireSessionAndReentryFinishes() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        let loader = DiscoveryLoader<[DiscoveryTopicTemplate]>()
        wire.pauseNextCatalog = true
        let started = expectation(description: "Canceled catalog loader suspended")
        wire.onPaused = { started.fulfill() }
        let old = Task { await self.loadCatalog(loader, session: session) }
        await fulfillment(of: [started], timeout: 2)
        old.cancel(); wire.resume(status: 401)
        await old.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        XCTAssertNil(loader.value); XCTAssertNil(loader.error); XCTAssertFalse(loader.isLoading)
        await loadCatalog(loader, session: session)
        XCTAssertEqual(loader.value?.map(\.id), [801]); XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading)
    }
    func testIndependentCatalogLoadersDoNotSupersedeEachOther() async throws {
        let wire = Wire(); let (session, _) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        let first = DiscoveryLoader<[DiscoveryTopicTemplate]>()
        let second = DiscoveryLoader<[DiscoveryTopicTemplate]>()
        wire.pauseNextCatalog = true
        let started = expectation(description: "First independent catalog loader suspended")
        wire.onPaused = { started.fulfill() }
        let old = Task { await self.loadCatalog(first, session: session) }
        await fulfillment(of: [started], timeout: 2)
        await loadCatalog(second, session: session)
        wire.resume(status: 200)
        await old.value
        XCTAssertEqual(first.value?.map(\.id), [801]); XCTAssertNil(first.error)
        XCTAssertEqual(second.value?.map(\.id), [801]); XCTAssertNil(second.error)
        XCTAssertFalse(first.isLoading); XCTAssertFalse(second.isLoading)
        XCTAssertEqual(session.account?.id, 7)
    }
    func testCatalogRequestCapturedBeforeRoleABARejectsDispatch() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        let request = session.publicTopicTemplateCatalogRequest()
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        let before = wire.requests.count
        let loader = DiscoveryLoader<[DiscoveryTopicTemplate]>()
        await loader.load(onUnauthorized: request.onUnauthorized, request.read)
        XCTAssertEqual(wire.requests.count, before)
        XCTAssertNil(loader.value); XCTAssertNil(loader.error); XCTAssertFalse(loader.isLoading)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
    }
    func testCurrentUnauthorizedExpiresNormalSessionAndSupersededDetailDoesNot() async throws {
        let wire = Wire(); let (session, vault) = try makeSession(wire, auth: true)
        await signIn(session, recorder: wire)
        wire.pauseNextDetail = true
        let started = expectation(description: "Superseded normal detail suspended")
        wire.onPaused = { started.fulfill() }
        let detail = session.publicTopicTemplateCoordinator(id: 801)
        let read = Task { await detail.load() }
        await fulfillment(of: [started], timeout: 2)
        await detail.load()
        wire.resume(status: 401)
        await read.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(detail.value?.id, 801)
        wire.detailStatus = 401
        await detail.load()
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertTrue(detail.isInvalidated); XCTAssertNil(detail.value)
    }

    func testUnconfiguredNormalSessionMakesZeroPublicReadCalls() async throws {
        let wire = Wire(), vault = Vault()
        let suite = "unconfigured-public-catalog-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let session = AppCompositionRoot(storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }).makeSession()
        do { _ = try await session.discoveryTopicTemplates(); XCTFail() } catch {}
        await session.publicTopicTemplateCoordinator(id: 801).load()
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEveryViewerIdentityComponentFencesLateSuccessAndThrownFailure() async throws {
        let original = Identity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        let changes = [Identity(epoch: 2, accountID: 7, role: "player", token: "synthetic-7"),
                       Identity(epoch: 1, accountID: 8, role: "player", token: "synthetic-7"),
                       Identity(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7"),
                       Identity(epoch: 1, accountID: 7, role: "player", token: "new-token"),
                       Identity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1), guest]
        for changed in changes {
            for fail in [false, true] {
                let wire = Wire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
                var identity = original
                transport.current = { identity }
                wire.pauseNextDetail = true
                let started = expectation(description: "Identity-bound transport suspended")
                wire.onPaused = { started.fulfill() }
                let request = try detailRequest(token: original.token)
                let read = Task { try await transport.send(request) }
                await fulfillment(of: [started], timeout: 2)
                identity = changed
                if fail { wire.resume(error: APIError.unauthorized) } else { wire.resume(status: 200) }
                do { _ = try await read.value; XCTFail("Changed identity accepted old completion") }
                catch is CancellationError {} catch { XCTFail("\(error)") }
            }
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var accountID = 7, role = "player", token = "synthetic-7", viewerIsMerchant = false
        var pauseNextDetail = false, pauseNextCatalog = false, detailStatus = 200, catalogStatus = 200
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var pendingCatalog = false
        func resume(error: Error) {
            let value = pending; pending = nil
            value?.resume(throwing: error)
        }
        func resume(status: Int) {
            let value = pending; pending = nil
            let json = pendingCatalog ? catalogJSON : detailJSON
            value?.resume(returning: (Data(json.utf8), status))
        }
        private let catalogJSON = #"{"code":200,"data":[{"id":801,"name":"Public route","locationCount":9}]}"#
        private var detailJSON: String {
            "{\"code\":200,\"data\":{\"id\":801,\"locationCount\":9,\"viewerIsMerchant\":\(viewerIsMerchant),\"chapters\":[{\"id\":21,\"recruitStatus\":{\"state\":\"OPEN\"}}]}}"
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            if (path.hasSuffix(PublicTemplateCompositionTests.detail) && pauseNextDetail)
                || (path.hasSuffix(PublicTemplateCompositionTests.catalog) && pauseNextCatalog) {
                pendingCatalog = path.hasSuffix(PublicTemplateCompositionTests.catalog)
                pauseNextDetail = false; pauseNextCatalog = false
                return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
            }
            if path.hasSuffix("/api/login/phone") {
                return (Data("{\"code\":200,\"token\":\"\(token)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}".utf8), 200)
            }
            if path.hasSuffix("/api/userInfo") {
                return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}".utf8), 200)
            }
            if path.hasSuffix(PublicTemplateCompositionTests.catalog) {
                return (Data(catalogJSON.utf8), catalogStatus)
            }
            if path.hasSuffix(PublicTemplateCompositionTests.detail) { return (Data(detailJSON.utf8), detailStatus) }
            return (Data(#"{"code":200}"#.utf8), 200)
        }
    }
}
