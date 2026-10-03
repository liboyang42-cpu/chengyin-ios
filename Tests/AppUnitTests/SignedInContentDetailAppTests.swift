import XCTest
@testable import Questify

@MainActor final class SignedInContentDetailAppTests: XCTestCase {
    private func deployment(approved: Bool = true) throws -> ReviewedAppDeployment {
        try ReviewedAppDeployment(market: .china, baseURL: "https://example.test/native",
            approvedBaseURLs: [.china: ["https://example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.details", realm: "synthetic", reads: [.homeAndSearch],
            contentDetails: approved ? .activityAndTopic : nil)
    }
    private func root(_ wire: Wire, vault: Vault, approved: Bool = true) throws -> AppCompositionRoot {
        let suite = "signed-in-details-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppCompositionRoot(deployment: .reviewed(try deployment(approved: approved)),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    private func signIn(_ session: AppSession, wire: Wire) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, wire.accountID)
        XCTAssertTrue(session.authChannels.state.signedIn)
    }
    func testNormalHomeAndActivitiesUseSeparateSignedInDetailApproval() async throws {
        let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault).makeSession()
        await signIn(session, wire: wire)
        let home = try await session.homeFeedReader.section(.recommended)
        XCTAssertEqual(home.count, 1)
        let activities = try await session.activities(page: 1, keyword: "")
        XCTAssertEqual(activities.map(\.id), [21])
        let topic = try await session.topicReader.topicDetail(id: 31)
        XCTAssertEqual(topic.id, 31); XCTAssertEqual(topic.activities?.map(\.id), [21])
        guard case .allowed(let activity) = try await session.activityDetail(id: XCTUnwrap(topic.activities?.first?.id)) else { return XCTFail() }
        XCTAssertEqual(activity.summary.id, 21)
        let details = wire.requests.filter { $0.url?.path.hasSuffix("/info") == true || $0.url?.path.hasSuffix("/info-to-user") == true }
        XCTAssertEqual(details.count, 2)
        for request in details {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
            let route = try XCTUnwrap(SignedInContentDetailReadRoute(url: XCTUnwrap(request.url), baseURL: URL(string: "https://example.test/native")!))
            XCTAssertTrue(route.accepts(request))
        }
        XCTAssertFalse(session.playExperience(for: .activity(21))?.available ?? false)
        XCTAssertNil(session.registrationWaitlistService(activityID: 21))
    }
    func testGuestAndHomeOnlyApprovalNeverDispatchDetails() async throws {
        for approved in [false, true] {
            let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault, approved: approved).makeSession()
            do { _ = try await session.activityDetail(id: 21); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            do { _ = try await session.topicReader.topicDetail(id: 31); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertTrue(wire.requests.isEmpty)
        }
        let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault, approved: false).makeSession()
        await signIn(session, wire: wire)
        let before = wire.requests.count
        do { _ = try await session.activityDetail(id: 21); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await session.topicReader.topicDetail(id: 31); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testMalformedShapesPartialIdentitiesAndOtherPathsNeverReachWire() async throws {
        let wire = Wire(), transport = try root(wire, vault: Vault()).transport()
        let identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1)
        transport.current = { identity }
        let base = URL(string: "https://example.test/native")!
        for route in SignedInContentDetailReadRoute.allCases {
            var malformed: [URLRequest] = []
            let exact = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(route.path), fields: ["id":"21"], token: "synthetic-7", boundary: "DetailBoundary")
            for fields in [[:], ["id":"01"], ["id":"0"], ["id":"21", "scope":""], ["id":"21", "memberId":"7"]] {
                malformed.append(try AuthRequestBuilder.makeFormRequest(url: exact.url!, fields: fields, token: "synthetic-7"))
            }
            let raw = try XCTUnwrap(String(data: XCTUnwrap(exact.httpBody), encoding: .utf8))
            let duplicate = "--DetailBoundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n21\r\n"
            var changed = exact
            for body in [raw + "\r\n", duplicate + raw, raw.replacingOccurrences(of: "\r\n", with: "\n")] {
                changed = exact; changed.httpBody = Data(body.utf8); malformed.append(changed)
            }
            changed = exact; changed.httpBody = nil; malformed.append(changed)
            changed = exact; changed.setValue("multipart/form-data; boundary=DetailBoundary; x=1", forHTTPHeaderField: "Content-Type"); malformed.append(changed)
            changed = exact; changed.url = URL(string: "https://other.test/native/" + route.path); malformed.append(changed)
            changed = exact; changed.url = URL(string: exact.url!.absoluteString + "/"); malformed.append(changed)
            changed = exact; changed.httpMethod = "GET"; malformed.append(changed)
            changed = exact; changed.url = URL(string: exact.url!.absoluteString + "?id=21"); malformed.append(changed)
            changed = exact; changed.url = URL(string: exact.url!.absoluteString + "#x"); malformed.append(changed)
            changed = exact; changed.httpBody = Data(#"{"id":21}"#.utf8); changed.setValue("application/json", forHTTPHeaderField: "Content-Type"); malformed.append(changed)
            changed = exact; changed.setValue("old-token", forHTTPHeaderField: "Authorization"); malformed.append(changed)
            changed = exact; changed.httpBodyStream = InputStream(data: Data()); malformed.append(changed)
            for request in malformed { do { _ = try await transport.send(request); XCTFail() } catch {} }
            for partial in [
                CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: nil, role: nil, token: nil),
                .init(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
                .init(epoch: 1, accountID: 7, role: "", token: "synthetic-7"),
                .init(epoch: 1, accountID: 7, role: " ", token: "synthetic-7"),
                .init(epoch: 1, accountID: 7, role: "admin", token: "synthetic-7"),
                .init(epoch: 1, accountID: 0, role: "player", token: "synthetic-7"),
                .init(epoch: 1, accountID: 7, role: "player", token: nil)
            ] {
                transport.current = { partial }
                do { _ = try await transport.send(exact); XCTFail() } catch {}
            }
            transport.current = { identity }
        }
        for path in ["api/registration/create", "api/activity/update", "api/topic/info", "api/play/nodes", "api/activity/edit-detail", "api/topic/edit-detail", "api/template/topic-template/list", "api/template/topic-template/info", PrivateHomeService.path] {
            let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: ["id":"21"], token: "synthetic-7")
            do { _ = try await transport.send(request); XCTFail() } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalCompositionPreservesGateAndRejectsMismatchedActivity() async throws {
        let wire = Wire(), session = try root(wire, vault: Vault()).makeSession()
        await signIn(session, wire: wire)
        wire.detailJSON = #"{"code":200,"data":{"gate":true,"clubId":9,"message":"Join first","activityName":"Shelf"}}"#
        let gate = try await session.activityDetail(id: 21)
        XCTAssertEqual(gate, .clubRequired(clubID: 9, message: "Join first"))
        wire.detailJSON = #"{"code":200,"data":{"id":22,"name":"Wrong"}}"#
        do { _ = try await session.activityDetail(id: 21); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(session.account?.id, 7)
    }
    func testOwnerSwitchRoleABAAndSessionABARejectLateSuccessAnd401() async throws {
        for route in SignedInContentDetailReadRoute.allCases {
            for transition in ["owner", "roleABA", "sessionABA"] {
                for unauthorized in [false, true] {
                    let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault).makeSession()
                    await signIn(session, wire: wire)
                    wire.pause = route
                    let started = expectation(description: "Suspended detail \(route) \(transition)"); wire.onPaused = { started.fulfill() }
                    let request = Task { try await self.detail(route, session: session) }
                    await fulfillment(of: [started], timeout: 2)
                    if transition == "roleABA" {
                        let firstRevision = session.contentDetailRevision
                        let firstScope = session.topicReader.scope
                        wire.role = "merchant"; await session.refreshOwnAccount()
                        wire.role = "player"; await session.refreshOwnAccount()
                        XCTAssertGreaterThan(session.contentDetailRevision, firstRevision)
                        XCTAssertNotEqual(session.topicReader.scope, firstScope)
                    } else {
                        await session.logout()
                        if transition == "owner" { wire.accountID = 8 }
                        await signIn(session, wire: wire)
                    }
                    wire.finish(unauthorized: unauthorized)
                    do { try await request.value; XCTFail("Late detail crossed \(transition)") }
                    catch { XCTAssertTrue(error is CancellationError, "\(error)") }
                    XCTAssertEqual(session.account?.id, wire.accountID)
                    XCTAssertEqual(vault.value, "synthetic-\(wire.accountID)")
                    XCTAssertNotEqual(session.errorKey, "auth.expired")
                }
            }
        }
    }
    func testCurrentHTTPAndEnvelope401ExpireButCanceled401DoesNot() async throws {
        for route in SignedInContentDetailReadRoute.allCases {
            for http in [false, true] {
                let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault).makeSession()
                await signIn(session, wire: wire)
                wire.detailJSON = #"{"code":401}"#; wire.detailStatus = http ? 401 : 200
                do { try await detail(route, session: session); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
                XCTAssertNil(session.account); XCTAssertNil(vault.value); XCTAssertEqual(session.errorKey, "auth.expired")
            }
            let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault).makeSession()
            await signIn(session, wire: wire)
            wire.pause = route
            let started = expectation(description: "Cancelable detail"); wire.onPaused = { started.fulfill() }
            let task = Task { try await self.detail(route, session: session) }
            await fulfillment(of: [started], timeout: 2)
            task.cancel(); wire.finish(unauthorized: true)
            do { try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        }
    }
    func testCurrent403IsAnErrorWithoutExpiringTheSignedInSession() async throws {
        for route in SignedInContentDetailReadRoute.allCases {
            for http in [false, true] {
                let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault).makeSession()
                await signIn(session, wire: wire)
                wire.detailJSON = #"{"code":403}"#; wire.detailStatus = http ? 403 : 200
                do { try await detail(route, session: session); XCTFail("Forbidden detail accepted") }
                catch { XCTAssertEqual(error as? APIError, http ? .httpStatus(403) : .businessCode(403)) }
                XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
                XCTAssertNotEqual(session.errorKey, "auth.expired")
            }
        }
    }
    func testViewOwnedDismissalAndReplacementDropLate401InTheSameSession() async throws {
        for route in SignedInContentDetailReadRoute.allCases {
            for replacement in [false, true] {
                for http in [false, true] {
                    let wire = Wire(), vault = Vault(), session = try root(wire, vault: vault).makeSession()
                    await signIn(session, wire: wire)
                    let loads = SignedInContentDetailLoadOwner()
                    wire.pause = route
                    let started = expectation(description: "Owned normal detail"); wire.onPaused = { started.fulfill() }
                    var canceled = false
                    let stale = loads.start {
                        do { try await self.detail(route, session: session); XCTFail("Late detail accepted") }
                        catch { canceled = error is CancellationError }
                    }
                    await fulfillment(of: [started], timeout: 2)
                    if replacement {
                        wire.pause = nil
                        await loads.run {
                            do { try await self.detail(route, session: session) }
                            catch { XCTFail("Replacement failed: \(error)") }
                        }
                    } else { loads.cancel() }
                    wire.finish(unauthorized: true, status: http ? 401 : 200)
                    await stale.value
                    XCTAssertTrue(canceled)
                    XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
                    XCTAssertNotEqual(session.errorKey, "auth.expired")
                }
            }
        }
    }
    func testRestoredSessionUsesAuthoritativeAccountBeforeDetailDispatch() async throws {
        let wire = Wire(), vault = Vault()
        vault.value = "synthetic-7"
        let session = try root(wire, vault: vault).makeSession()
        await session.bootstrap()
        XCTAssertEqual(session.account?.id, 7)
        XCTAssertEqual(wire.requests.first?.url?.lastPathComponent, "userInfo")
        XCTAssertFalse(wire.requests.contains { $0.url?.lastPathComponent == "phone" })
        for route in SignedInContentDetailReadRoute.allCases { try await detail(route, session: session) }
    }
    func testTopicShelfOmittedEmptyAndMalformedStayDistinctInNormalComposition() async throws {
        let wire = Wire(), session = try root(wire, vault: Vault()).makeSession()
        await signIn(session, wire: wire)
        wire.detailJSON = #"{"code":200,"data":{"id":31,"name":"Topic"}}"#
        let unknown = try await session.topicReader.topicDetail(id: 31)
        XCTAssertNil(unknown.activities)
        wire.detailJSON = #"{"code":200,"data":{"id":31,"name":"Topic","activityList":[]}}"#
        let empty = try await session.topicReader.topicDetail(id: 31)
        XCTAssertEqual(empty.activities, [])
        wire.detailJSON = #"{"code":200,"data":{"id":31,"name":"Topic","activityList":[{"id":21,"name":"One"},{"id":21,"name":"Duplicate"}]}}"#
        do { _ = try await session.topicReader.topicDetail(id: 31); XCTFail("Malformed shelf accepted") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(session.account?.id, 7)
    }
    private func detail(_ route: SignedInContentDetailReadRoute, session: AppSession) async throws {
        switch route {
        case .activity: _ = try await session.activityDetail(id: 21)
        case .topic: _ = try await session.topicReader.topicDetail(id: 31)
        }
    }
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var accountID = 7, role = "player", detailStatus = 200
        var detailJSON: String?
        var pause: SignedInContentDetailReadRoute?
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var pendingJSON = "{}"
        func finish(unauthorized: Bool, status: Int = 200) {
            let continuation = pending; pending = nil
            continuation?.resume(returning: (Data((unauthorized ? #"{"code":401}"# : pendingJSON).utf8), status))
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            let json: String
            if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":\(accountID),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/activity/info") { json = detailJSON ?? #"{"code":200,"data":{"id":21,"name":"Activity detail"}}"# }
            else if path.hasSuffix("/topic/info-to-user") { json = detailJSON ?? #"{"code":200,"data":{"id":31,"name":"Topic detail","activityList":[{"id":21,"name":"Available walk"}]}}"# }
            else if path.hasSuffix("/topic/list") { json = #"{"code":200,"data":{"rows":[{"id":31,"name":"Topic card"}]}}"# }
            else if path.hasSuffix("/activity/list") { json = #"{"code":200,"data":{"rows":[{"id":21,"name":"Activity card"}]}}"# }
            else { json = #"{"code":200,"data":[]}"# }
            if let pause, path.hasSuffix(pause.path) {
                pendingJSON = json
                return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
            }
            return (Data(json.utf8), path.hasSuffix("/info") || path.hasSuffix("/info-to-user") ? detailStatus : 200)
        }
    }
}
