import XCTest
@testable import Questify

@MainActor final class MerchantProjectBrowseCompositionTests: XCTestCase {
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player", allowed = true, status = 200
        var holdPath: String?, onHeld: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        var heldBody = Data()
        func resume(status: Int = 200) { let p = pending; pending = nil; p?.resume(returning: (heldBody, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.lastPathComponent
            if path == "phone" { return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8), 200) }
            if path == "userInfo" { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            let payload = path == "me"
                ? "{\"active\":true,\"merchant\":{\"id\":31},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":\(allowed ? "[\"merchant:project:manage\"]" : "[]")}"
                : #"{"rows":[{"id":70,"bizType":"topic","title":"Synthetic project"}],"total":1}"#
            let body = Data("{\"code\":200,\"data\":\(payload)}".utf8)
            if path == holdPath { holdPath = nil; heldBody = body; return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            return (body, status)
        }
    }
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://projects.example/native",
            approvedBaseURLs: [.china: ["https://projects.example/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.project.browse", realm: "synthetic", reads: [.homeAndSearch])
    }
    private func normal(_ wire: Wire, enabled: Bool = true, wrongAccount: Bool = false) throws -> AppSession {
        let suite = "projects-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppCompositionRoot(deployment: .reviewed(try deployment()), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, sessionDependencies: { context in
                .init(merchantProjectBrowseApproval: enabled ? try? .init(market: context.market, baseURL: context.baseURL,
                    namespace: context.session.namespace, accountID: wrongAccount ? 8 : context.session.accountID) : nil)
            }).makeSession()
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func context(_ d: ReviewedAppDeployment) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: try XCTUnwrap(d.regional.apiConfiguration).baseURL, role: "player",
              session: try .init(accountID: 7, epoch: 1, namespace: d.storageScope.service, token: "synthetic-7"))
    }
    private func approval(_ context: RuntimeDependencyContext) throws -> MerchantProjectBrowseApproval {
        try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID)
    }
    private func request(_ d: ReviewedAppDeployment, projects: Bool = false) throws -> URLRequest {
        let api = try XCTUnwrap(d.regional.apiConfiguration)
        var r = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(projects ? "api/project/my" : "api/merchant/access/me"),
            fields: projects ? ["type":"all", "state":"all", "ownerType":"all", "scope":"MERCHANT", "pageNum":"1", "pageSize":"200"] : [:],
            token: "synthetic-7", includesBody: projects, boundary: "00000000-0000-0000-0000-000000000001")
        r.httpShouldHandleCookies = false; return r
    }
    func testNormalReadOnlyEntryUsesTwoReadsThenExistingSnapshotSummary() async throws {
        let wire = Wire(), session = try normal(wire); await login(session); wire.requests = []
        let reader = try XCTUnwrap(session.merchantProjectBrowseReader)
        let access = try await reader.merchantAccess(), page = try await reader.merchantProjects(access: access)
        XCTAssertEqual(page.rows.count, 1); XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me", "my"])
        XCTAssertTrue(wire.requests.allSatisfy { !$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
        let context = MerchantProjectWorkspaceContext(reader: reader, service: nil)
        let snapshot = MerchantProjectWorkspaceSnapshot(page: page, access: access, context: context), presentation = MerchantProjectWorkspacePresentation()
        presentation.openSummary(project: page.rows[0], snapshot: snapshot, context: context, permit: presentation.permit(snapshot: snapshot))
        let selected = try XCTUnwrap(presentation.selection)
        XCTAssertTrue(presentation.selectionIsCurrent(selected, snapshot: snapshot, context: context))
        XCTAssertFalse(presentation.canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: true))
        presentation.closeSummary(id: selected.id); XCTAssertNil(presentation.selection); XCTAssertEqual(wire.requests.count, 2)
    }
    func testDefaultNilAndWrongAccountDoNotCreateReaderOrDispatch() async throws {
        XCTAssertNil(NativeRuntimeDependencies.dormant.merchantProjectBrowseApproval)
        for wrong in [false, true] {
            let wire = Wire(), session = try normal(wire, enabled: wrong, wrongAccount: wrong)
            await login(session); wire.requests = []; XCTAssertNil(session.merchantProjectBrowseReader); XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testServerPermissionAndCurrentAccessReceiptAreRequired() async throws {
        let wire = Wire(), session = try normal(wire); await login(session); wire.requests = []
        let reader = try XCTUnwrap(session.merchantProjectBrowseReader)
        wire.allowed = false; let denied = try await reader.merchantAccess()
        do { _ = try await reader.merchantProjects(access: denied); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        wire.allowed = true; let accepted = try await reader.merchantAccess()
        do { _ = try await reader.merchantProjects(access: denied); XCTFail() } catch {}
        _ = try await reader.merchantProjects(access: accepted)
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me", "me", "my"])
    }
    func testOtherMerchantSurfacesCannotBorrowBrowseReader() async throws {
        let wire = Wire(), session = try normal(wire); await login(session)
        let reader = try XCTUnwrap(session.merchantProjectBrowseReader), access = try await reader.merchantAccess(); wire.requests = []
        do { _ = try await reader.merchantDashboard(access: access); XCTFail() } catch {}
        do { _ = try await reader.merchantTodo(access: access); XCTFail() } catch {}
        do { _ = try await reader.merchantEvents(access: access); XCTFail() } catch {}
        do { _ = try await reader.merchantOrders(access: access, filter: .init()); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testScopedTransportRejectsOtherRoutesAndMalformedMerchantScope() async throws {
        let d = try deployment(), wire = Wire(), root = CompositionHTTPTransport(deployment: d, underlying: wire), c = try context(d)
        let viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        root.current = { viewer }; let child = root.scopedForMerchantProjectBrowse(approval: try approval(c), context: c, approved: { true })
        let access = try request(d), project = try request(d, projects: true)
        do { _ = try await root.send(access); XCTFail() } catch {}
        do { _ = try await root.send(project); XCTFail() } catch {}
        var bad: [URLRequest] = []
        for path in ["api/merchant/list", "api/merchant/orders", "api/merchant/dashboard", "api/merchant/events", "api/project/home"] {
            var r = access; r.url = c.baseURL.appendingPathComponent(path); bad.append(r)
        }
        for value in ["CLUB", "", "merchant"] {
            var r = project; r.httpBody = Data(String(data: project.httpBody!, encoding: .utf8)!.replacingOccurrences(of: "MERCHANT", with: value).utf8); bad.append(r)
        }
        for suffix in ["?scope=MERCHANT", "/", "#fragment"] { var r = project; r.url = URL(string: project.url!.absoluteString + suffix); bad.append(r) }
        for header in ["Authorization", "Proxy-Authorization", "Cookie", "Content-Type"] { var r = project; r.setValue("wrong", forHTTPHeaderField: header); bad.append(r) }
        var json = access; json.httpBody = Data("{}".utf8); bad.append(json)
        var cookie = project; cookie.httpShouldHandleCookies = true; bad.append(cookie)
        var stream = project; stream.httpBodyStream = InputStream(data: project.httpBody!); bad.append(stream)
        var get = access; get.httpMethod = "GET"; bad.append(get)
        for r in bad { do { _ = try await child.send(r); XCTFail() } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await child.replacingUnderlying(wire).send(access); _ = try await child.send(project)
        XCTAssertEqual(wire.requests.count, 2)
    }
    func testNilViewerCloneAndRevokedGrantRemainClosed() async throws {
        let d = try deployment(), wire = Wire(), root = CompositionHTTPTransport(deployment: d, underlying: wire), c = try context(d)
        var allowed = true
        let absent = root.scopedForMerchantProjectBrowse(approval: try approval(c), context: c, approved: { allowed })
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        let active = root.scopedForMerchantProjectBrowse(approval: try approval(c), context: c, approved: { allowed })
        let r = try request(d)
        do { _ = try await absent.send(r); XCTFail() } catch {}
        allowed = false
        do { _ = try await active.replacingUnderlying(wire).send(r); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRoleABAInvalidatesRetainedReaderAndLateProjectSuccessOr401() async throws {
        for status in [200, 401] {
            let wire = Wire(), session = try normal(wire); await login(session)
            let old = try XCTUnwrap(session.merchantProjectBrowseReader), access = try await old.merchantAccess()
            let started = expectation(description: "project held"); wire.holdPath = "my"; wire.onHeld = { started.fulfill() }
            let task = Task { try await old.merchantProjects(access: access) }
            await fulfillment(of: [started], timeout: 2)
            wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
            wire.resume(status: status)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(old.isConfigured); XCTAssertEqual(session.account?.id, 7)
            XCTAssertFalse(old === session.merchantProjectBrowseReader)
        }
    }
    func testSupersededAccess401DoesNotExpireNewAccess() async throws {
        let wire = Wire(), session = try normal(wire); await login(session)
        let reader = try XCTUnwrap(session.merchantProjectBrowseReader), started = expectation(description: "old access held")
        wire.holdPath = "me"; wire.onHeld = { started.fulfill() }
        let task = Task { try await reader.merchantAccess() }
        await fulfillment(of: [started], timeout: 2)
        let fresh = try await reader.merchantAccess(); wire.resume(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.account?.id, 7); _ = try await reader.merchantProjects(access: fresh)
    }
    func testCurrentAccess401ExpiresOnlyMatchingSession() async throws {
        let wire = Wire(), session = try normal(wire); await login(session); wire.status = 401
        let reader = try XCTUnwrap(session.merchantProjectBrowseReader)
        do { _ = try await reader.merchantAccess(); XCTFail() } catch {}
        XCTAssertNil(session.account)
    }
}
