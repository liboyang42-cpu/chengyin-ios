import XCTest
@testable import Questify

/// Exercises AppSession's real RoamService/SearchMapService and normal composition.
/// All transport/storage/device factories are synthetic; no URLSession or provider is used.
@MainActor final class ManualMapCompositionTests: XCTestCase {
    private static let base = "https://example.test/native"
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.5)!, label: "Manual A")
    private let otherArea = RoamSearchArea(coordinate: RoamCoordinate(latitude: 32.1, longitude: 120.4)!, label: "Manual B")
    private func deployment(_ grants: Set<ReviewedAppDeployment.ReadGrant> = [.manualMap]) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: Self.base, approvedBaseURLs: [.china: [Self.base]],
                  verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.manual-map", realm: "fixture", reads: grants)
    }
    private func makeSession(_ wire: Wire, approvals: Approvals, grants: Set<ReviewedAppDeployment.ReadGrant> = [.manualMap]) throws -> (AppSession, Vault) {
        let suite = "manual-map-" + UUID().uuidString, vault = Vault()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let root = AppCompositionRoot(deployment: .reviewed(try deployment(grants)),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire },
            manualMapReadApproval: { approvals.approval($0) })
        let device = DeviceSpy(onCall: { wire.locationCalls += 1 })
        return (AppSession(composition: root, runtimeDependencies: .init(location: device),
            roamLiveDependencies: .init(makeLocation: { wire.locationFactoryCalls += 1; return device })), vault)
    }
    private func signIn(_ session: AppSession) async {
        if session.account != nil { await session.logout() }
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testActualCompositionBothReadersManualAreaListToCorrelatedDetailAndFallback() async throws {
        let wire = Wire(), approvals = Approvals()
        let (session, _) = try makeSession(wire, approvals: approvals)
        await signIn(session); wire.requests = []
        session.roamArea = area
        let places = try await session.roamReader.roamPlaces(radiusM: 3000)
        XCTAssertEqual(places.map(\.id), [42])
        let roamNodes = try await session.roamReader.roamRouteNodes(radiusM: 2000)
        XCTAssertEqual(roamNodes.map(\.id), [91])
        let roamDetail = try await session.roamReader.roamNodeDetail(id: places[0].id)
        XCTAssertEqual(roamDetail.id, 42)
        let city = try await session.searchMapReader.citySearch(.init(filter: .init(keyword: "tea", categoryID: 2), area: otherArea, tag: "cafe", cityRole: "host"))
        XCTAssertEqual(city.nodes.map(\.id), [42]); XCTAssertEqual(city.activityFailure, .unavailable)
        let detail = try await session.searchMapReader.cityNode(id: city.nodes[0].id)
        XCTAssertEqual(detail.poiID, 42)
        let nearby = try await session.searchMapReader.nearby(area: otherArea)
        XCTAssertEqual(nearby.nodes.map(\.id), [91]); XCTAssertTrue(nearby.cityFailed)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/roam/pois", "/native/api/map/nearby", "/native/api/city/nodes/42", "/native/api/city/nodes", "/native/api/city/nodes/42", "/native/api/map/nearby"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
        XCTAssertEqual(wire.deviceOrProviderCalls, 0)
        // Independent browser centers must not leak into one another.
        XCTAssertEqual(session.roamReader.searchArea, area)
        XCTAssertEqual(URLComponents(url: wire.requests[3].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "lat" })?.value, "32.1")
    }
    func testMissingGrantMissingApprovalGuestAndNoAreaMakeZeroMapDispatches() async throws {
        let grantSets: [Set<ReviewedAppDeployment.ReadGrant>] = [[], [.homeAndSearch], [.manualMap]]
        for grants in grantSets {
            let wire = Wire(), approvals = Approvals(); approvals.enabled = false
            let (session, _) = try makeSession(wire, approvals: approvals, grants: grants)
            session.roamArea = area
            do { _ = try await session.roamReader.roamPlaces(radiusM: 3000); XCTFail() } catch {}
            await signIn(session); wire.requests = []
            do { _ = try await session.roamReader.roamPlaces(radiusM: 3000); XCTFail() } catch {}
            XCTAssertTrue(wire.requests.isEmpty)
        }
        let wire = Wire(), approvals = Approvals(), pair = try makeSession(wire, approvals: approvals)
        await signIn(pair.0); wire.requests = []
        do { _ = try await pair.0.roamReader.roamNodeDetail(id: 42); XCTFail() } catch {}
        do { _ = try await pair.0.searchMapReader.cityNode(id: 42); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testUnsupportedLayersAndAllWritesRemainClosed() async throws {
        let wire = Wire(), approvals = Approvals(), pair = try makeSession(wire, approvals: approvals)
        await signIn(pair.0); pair.0.roamArea = area; wire.requests = []
        do { _ = try await pair.0.roamReader.roamEvents(radiusM: 3000); XCTFail() } catch {}
        do { _ = try await pair.0.roamReader.roamPlayers(radiusM: 3000); XCTFail() } catch {}
        do { _ = try await pair.0.roamReader.roamExploreDay(); XCTFail() } catch {}
        do { _ = try await pair.0.roamReader.roamMerchantDetail(id: 42); XCTFail() } catch {}
        do { _ = try await pair.0.searchMapReader.merchant(id: 42); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        let (root, transport, _) = try directTransport(wire, approvals: approvals)
        for path in ["api/roam/reveal", "api/roam/finish", "api/roam/presence", "api/city/nodes/42/complete", "api/city/nodes/42/favorite", "api/city/nodes/favorites", "api/city/nodes/merchant/42", "api/merchant/public-detail", "api/map/reverse-geocode", "api/common/activity_clear"] {
            var request = URLRequest(url: URL(string: Self.base + "/" + path)!); request.httpMethod = "POST"
            request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
            await blocked(request, transport: transport, wire: wire)
        }
        withExtendedLifetime(root) {}
        XCTAssertEqual(wire.deviceOrProviderCalls, 0)
    }
    func testExactQueryAndMultipartRejectDuplicatesExtraScopeWrongMethodAndMalformedValues() async throws {
        let wire = Wire(), approvals = Approvals()
        let (root, transport, _) = try directTransport(wire, approvals: approvals)
        let valid = query("api/roam/pois", ["lat":"31.2", "lng":"121.5", "radius":"3000"])
        _ = try await transport.send(valid)
        var requests: [URLRequest] = []
        for method in ["POST", "PUT", "PATCH", "DELETE", "HEAD"] { var v = valid; v.httpMethod = method; requests.append(v) }
        for suffix in ["&lat=31.2", "&accountId=7", "&scope=merchant", "#fragment", "&", "%26radius=9"] {
            var v = valid; v.url = URL(string: valid.url!.absoluteString + suffix); requests.append(v)
        }
        for (key, value) in [("lat","NaN"),("lng","181.0"),("lat","32.1"),("radius","0"),("radius","20001"),("radius","03000"),("radius","3000.0")] {
            var fields = ["lat":"31.2", "lng":"121.5", "radius":"3000"]; fields[key] = value
            requests.append(query("api/roam/pois", fields))
        }
        for path in ["api/city/nodes/0", "api/city/nodes/-1", "api/city/nodes/042", "api/city/nodes/42/", "api/city/nodes/%34%32"] { requests.append(query(path, [:])) }
        for extra in [["status":"1"], ["auditStatus":"1"], ["scope":"merchant"]] {
            var fields = nearbyFields; fields.merge(extra) { _, new in new }
            requests.append(try form(fields))
        }
        var malformed = try form(nearbyFields)
        malformed.setValue("multipart/form-data; boundary=wrong", forHTTPHeaderField: "Content-Type"); requests.append(malformed)
        var duplicate = try form(nearbyFields)
        let text = String(data: duplicate.httpBody!, encoding: .utf8)!
        duplicate.httpBody = Data(text.replacingOccurrences(of: "--map-test--\r\n", with: "--map-test\r\nContent-Disposition: form-data; name=\"latitude\"\r\n\r\n31.2\r\n--map-test--\r\n").utf8); requests.append(duplicate)
        var bodyGET = valid; bodyGET.httpBody = Data(); requests.append(bodyGET)
        var stream = valid; stream.httpBodyStream = InputStream(data: Data()); requests.append(stream)
        for request in requests { await blocked(request, transport: transport, wire: wire) }
        // Canonical native Double nearby radius and documented filter names are accepted.
        _ = try await transport.send(form(nearbyFields))
        _ = try await transport.send(query("api/city/nodes", ["lat":"31.2", "lng":"121.5", "radius":"20000", "keyword":"tea", "categoryId":"2", "tag":"cafe", "cityRole":"host"]))
        for fields in [["sort_type":"1"], ["category_id":"2"], ["cityRole":String(repeating: "x", count: 257)], ["categoryId":"0"], ["keyword":"\n"]] {
            var base = ["lat":"31.2", "lng":"121.5", "radius":"20000"]; base.merge(fields) { _, new in new }
            await blocked(query("api/city/nodes", base), transport: transport, wire: wire)
        }
        withExtendedLifetime(root) {}
    }
    func testIncompleteIdentityStaleTokenWrongRealmAndUnscopedTransportDoNotDispatch() async throws {
        let wire = Wire(), approvals = Approvals()
        let (root, transport, _) = try directTransport(wire, approvals: approvals)
        let request = query("api/roam/pois", ["lat":"31.2", "lng":"121.5", "radius":"3000"])
        await blocked(request, transport: root, wire: wire)
        for identity in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: nil, role: nil, token: nil),
                         .init(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: "", token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: "player", token: nil),
                         .init(epoch: 1, accountID: 0, role: "player", token: "synthetic-7")] {
            root.current = { identity }
            await blocked(request, transport: transport, wire: wire)
        }
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        var stale = request; stale.setValue("stale-7", forHTTPHeaderField: "Authorization")
        await blocked(stale, transport: transport, wire: wire)
        for url in [request.url!.absoluteString.replacingOccurrences(of: "example.test", with: "elsewhere.test"),
                    request.url!.absoluteString.replacingOccurrences(of: "/native/", with: "/other/"),
                    request.url!.absoluteString.replacingOccurrences(of: "https:", with: "http:")] {
            var wrong = request; wrong.url = URL(string: url)
            await blocked(wrong, transport: transport, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAreaABAAndApprovalRevocationRejectLateSuccessAnd401WithoutExpiringSession() async throws {
        for status in [200, 401] {
            for reader in ["roam", "search"] {
                for revoke in [false, true] {
                    let wire = Wire(), approvals = Approvals(), (session, vault) = try makeSession(wire, approvals: approvals)
                    await signIn(session); session.roamArea = area
                    session.searchMapReader.selectManualArea(area)
                    wire.pausePath = reader == "roam" ? "/api/roam/pois" : "/api/city/nodes"
                    let started = expectation(description: "Manual read suspended"); wire.onPaused = { started.fulfill() }
                    let task = Task { () throws -> Void in
                        if reader == "roam" { _ = try await session.roamReader.roamPlaces(radiusM: 3000) }
                        else { _ = try await session.searchMapReader.citySearch(.init(filter: .init(), area: self.area)) }
                    }
                    await fulfillment(of: [started], timeout: 2)
                    if revoke { approvals.enabled = false }
                    else if reader == "roam" { session.roamArea = otherArea; session.roamArea = area }
                    else { session.searchMapReader.selectManualArea(otherArea); session.searchMapReader.selectManualArea(area) }
                    wire.resume(status: status)
                    do { try await task.value; XCTFail("Retired map read was accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
                    XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7"); XCTAssertNil(session.errorKey)
                }
            }
        }
    }
    func testAccountAndRoleRefreshABAFenceBothReaders() async throws {
        for status in [200, 401] {
            for reader in ["roam", "search"] {
                let wire = Wire(), approvals = Approvals(), (session, vault) = try makeSession(wire, approvals: approvals)
                await signIn(session); session.roamArea = area; session.searchMapReader.selectManualArea(area)
                wire.pausePath = "/api/city/nodes/42"
                let started = expectation(description: "Detail suspended"); wire.onPaused = { started.fulfill() }
                let task = Task { () throws -> Void in
                    if reader == "roam" { _ = try await session.roamReader.roamNodeDetail(id: 42) }
                    else { _ = try await session.searchMapReader.cityNode(id: 42) }
                }
                await fulfillment(of: [started], timeout: 2)
                wire.role = "merchant"; await session.refreshOwnAccount()
                wire.role = "player"; await session.refreshOwnAccount()
                wire.resume(status: status)
                do { try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
                XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7"); XCTAssertNil(session.errorKey)
            }
        }
    }
    func testAccountTokenABACancelsRetainedSearchAndRoamDetails() async throws {
        for status in [200, 401] {
            for roam in [true, false] {
                let wire = Wire(), approvals = Approvals(), (session, vault) = try makeSession(wire, approvals: approvals)
                await signIn(session); session.roamArea = area; session.searchMapReader.selectManualArea(area)
                wire.pausePath = "/api/city/nodes/42"
                let started = expectation(description: "Account detail suspended"); wire.onPaused = { started.fulfill() }
                let task = Task { () throws -> Void in
                    if roam { _ = try await session.roamReader.roamNodeDetail(id: 42) }
                    else { _ = try await session.searchMapReader.cityNode(id: 42) }
                }
                await fulfillment(of: [started], timeout: 2)
                wire.accountID = 8; await signIn(session)
                wire.accountID = 7; await signIn(session)
                session.roamArea = area; session.searchMapReader.selectManualArea(area)
                wire.resume(status: status)
                do { try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
                XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7"); XCTAssertNil(session.errorKey)
                let fresh = try await session.searchMapReader.cityNode(id: 42)
                XCTAssertEqual(fresh.poiID, 42)
            }
        }
    }
    func testWrongResponseNodeIDAndCurrentUnauthorizedAreNotAccepted() async throws {
        for roam in [false, true] {
            let wire = Wire(), approvals = Approvals(), (session, vault) = try makeSession(wire, approvals: approvals)
            await signIn(session); session.roamArea = area; session.searchMapReader.selectManualArea(area)
            wire.nodeID = 43
            do {
                if roam { _ = try await session.roamReader.roamNodeDetail(id: 42) }
                else { _ = try await session.searchMapReader.cityNode(id: 42) }
                XCTFail()
            } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            wire.status = 401
            do {
                if roam { _ = try await session.roamReader.roamNodeDetail(id: 42) }
                else { _ = try await session.searchMapReader.cityNode(id: 42) }
                XCTFail()
            } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertNil(session.account); XCTAssertNil(vault.value); XCTAssertEqual(session.errorKey, "auth.expired")
        }
    }
    func testEncodedTraversalAmbiguousQueriesAndNumericBoundsDoNotDispatch() async throws {
        let wire = Wire(), approvals = Approvals()
        let (root, transport, _) = try directTransport(wire, approvals: approvals)
        for path in ["api/city/nodes/42/../43", "api/city/nodes/%2e%2e/42", "api/city/nodes/%252e%252e/42",
                     "api/city/nodes/42%2F..%2F43", "api/city/nodes//42", "api/city/nodes/9223372036854775808",
                     "api/city/nodes/+42", "api/city/nodes/42?", "api/city/nodes/42?scope=merchant"] {
            await blocked(query(path, [:]), transport: transport, wire: wire)
        }
        let valid = query("api/city/nodes", ["lat":"31.2", "lng":"121.5", "radius":"20000", "keyword":"A+B"])
        XCTAssertTrue(try XCTUnwrap(valid.url).absoluteString.contains("keyword=A%2BB"))
        _ = try await transport.send(valid)
        for text in [valid.url!.absoluteString.replacingOccurrences(of: "%2B", with: "+"),
                     valid.url!.absoluteString.replacingOccurrences(of: "lat=", with: "%6Cat="),
                     valid.url!.absoluteString + "&%6Cat=31.2",
                     valid.url!.absoluteString.replacingOccurrences(of: "example.test", with: "user@example.test"),
                     valid.url!.absoluteString.replacingOccurrences(of: "example.test", with: "example.test:443")] {
            var request = valid; request.url = URL(string: text)
            await blocked(request, transport: transport, wire: wire)
        }
        for (key, value) in [("latitude", "NaN"), ("longitude", "Infinity"), ("latitude", "31.20"),
                             ("radius", "0"), ("radius", "20001"), ("radius", "2e3"), ("radius", "+2000"),
                             ("radius", "02000"), ("radius", "2000.00"), ("limit", "0"), ("limit", "101"), ("limit", "050")] {
            var fields = nearbyFields; fields[key] = value
            await blocked(try form(fields), transport: transport, wire: wire)
        }
        for value in ["  tea", "tea  ", "a\u{0000}b", String(repeating: "中", count: 86)] {
            await blocked(query("api/city/nodes", ["lat":"31.2", "lng":"121.5", "radius":"20000", "keyword":value]), transport: transport, wire: wire)
        }
        withExtendedLifetime(root) {}
    }
    func testBothReaderFinalBoundariesRejectApprovalRevocationAndReissueBeforeDecodeReturns() async throws {
        // Plain recorder intentionally has no composition response fence. This isolates the
        // reader's post-service/decode authority check rather than retesting transport checks.
        for (status, businessCode) in [(200, 200), (401, 200), (200, 401)] {
            for roam in [false, true] {
                for revoke in [false, true] {
                    let wire = Wire(); wire.status = status; wire.businessCode = businessCode
                    let configuration = try XCTUnwrap(try deployment().regional.apiConfiguration)
                    var revision: UUID? = UUID(), unauthorized = 0
                    wire.onDelivery = { revision = revoke ? nil : UUID() }
                    let roamReader = RoamSessionReader(service: RoamService(configuration: configuration, transport: wire),
                        currentSession: { try? .init(accountID: 7, epoch: 1, token: "synthetic-7", role: "player", manualMapApprovalRevision: revision) },
                        searchArea: { self.area }, onUnauthorized: { _ in unauthorized += 1 })
                    let searchReader = SearchMapSessionReader(service: SearchMapService(configuration: configuration, transport: wire),
                        currentContext: { try! .init(accountID: 7, epoch: 1, token: "synthetic-7", role: "player", manualMapApprovalRevision: revision) },
                        onUnauthorized: { _ in unauthorized += 1 })
                    do {
                        if roam { _ = try await roamReader.roamNodeDetail(id: 42) }
                        else { _ = try await searchReader.cityNode(id: 42) }
                        XCTFail("Retired approval survived the final reader boundary")
                    } catch is CancellationError {} catch { XCTFail("\(error)") }
                    XCTAssertEqual(unauthorized, 0)
                }
            }
        }
    }
    func testNormalCompositionApprovalReissueChangesRetainedReaderLifetimes() async throws {
        let wire = Wire(), approvals = Approvals(), (session, _) = try makeSession(wire, approvals: approvals)
        await signIn(session); session.roamArea = area; session.searchMapReader.selectManualArea(area)
        let roamIdentity = session.roamReader.identity, scope = session.searchMapReader.scope
        approvals.retained = nil
        XCTAssertNotEqual(session.roamReader.identity, roamIdentity)
        XCTAssertNotEqual(session.searchMapReader.scope, scope)
        let nextIdentity = session.roamReader.identity, nextScope = session.searchMapReader.scope
        approvals.enabled = false
        XCTAssertNotEqual(session.roamReader.identity, nextIdentity)
        XCTAssertNotEqual(session.searchMapReader.scope, nextScope)
        wire.requests = []
        do { _ = try await session.roamReader.roamPlaces(radiusM: 3000); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOwnedCancellationDropsLate401WithoutExpiringCurrentSession() async throws {
        for roam in [false, true] {
            for supersede in [false, true] {
                let wire = Wire(), approvals = Approvals(), (session, vault) = try makeSession(wire, approvals: approvals)
                await signIn(session); session.roamArea = area; session.searchMapReader.selectManualArea(area)
                wire.pausePath = "/api/city/nodes/42"
                let started = expectation(description: "Owned map detail suspended"); wire.onPaused = { started.fulfill() }
                let owner = ManualMapReadTaskOwner()
                var cancelled = false, replacementRan = false
                let task = Task {
                    await owner.run {
                        do {
                            if roam { _ = try await session.roamReader.roamNodeDetail(id: 42) }
                            else { _ = try await session.searchMapReader.cityNode(id: 42) }
                            XCTFail("Retired UI read completed")
                        } catch is CancellationError { cancelled = true } catch { XCTFail("\(error)") }
                    }
                }
                await fulfillment(of: [started], timeout: 2)
                if supersede { await owner.run { replacementRan = true } }
                else { owner.cancel() }
                wire.resume(status: 401); await task.value
                XCTAssertTrue(cancelled); XCTAssertEqual(replacementRan, supersede)
                XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
                XCTAssertNil(session.errorKey); XCTAssertEqual(wire.deviceOrProviderCalls, 0)
            }
        }
    }
    func testRetiredOwnerCompletionCannotClearReplacementTask() async throws {
        let owner = ManualMapReadTaskOwner()
        let firstStarted = expectation(description: "First owner task"), secondStarted = expectation(description: "Second owner task")
        var first: CheckedContinuation<Void, Never>?, second: CheckedContinuation<Void, Never>?
        var firstCancelled = false, secondCancelled = false
        let old = Task { await owner.run {
            await withCheckedContinuation { first = $0; firstStarted.fulfill() }
            firstCancelled = Task.isCancelled
        } }
        await fulfillment(of: [firstStarted], timeout: 2)
        let fresh = Task { await owner.run {
            await withCheckedContinuation { second = $0; secondStarted.fulfill() }
            secondCancelled = Task.isCancelled
        } }
        await fulfillment(of: [secondStarted], timeout: 2)
        old.cancel(); first?.resume(); await old.value
        owner.cancel(); second?.resume(); await fresh.value
        XCTAssertTrue(firstCancelled); XCTAssertTrue(secondCancelled)
    }
    func testOwnedReadPropagatesParentCancellation() async throws {
        let owner = ManualMapReadTaskOwner(), started = expectation(description: "Parent-owned read started")
        var pending: CheckedContinuation<Void, Never>?, cancelled = false
        let parent = Task { await owner.run {
            await withCheckedContinuation { pending = $0; started.fulfill() }
            cancelled = Task.isCancelled
        } }
        await fulfillment(of: [started], timeout: 2)
        parent.cancel(); pending?.resume(); await parent.value
        XCTAssertTrue(cancelled)
    }
    func testManualApprovalExactAuthorityExpiryAndMissingIssuanceFailClosed() async throws {
        let wire = Wire(), approvals = Approvals()
        let (root, transport, _) = try directTransport(wire, approvals: approvals)
        let request = query("api/roam/pois", ["lat":"31.2", "lng":"121.5", "radius":"3000"])
        _ = try await transport.send(request)
        let original = try XCTUnwrap(approvals.retained), context = original.context
        XCTAssertFalse(original.matches(context, now: original.expiresAt))
        XCTAssertThrowsError(try ManualMapReadApproval(context: context, expiresAt: Date().addingTimeInterval(-1)))
        approvals.reissueForContext = false
        let variants = [
            RuntimeDependencyContext(market: .china, baseURL: context.baseURL, role: "merchant", session: context.session),
            RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://elsewhere.test/native")!, role: context.role, session: context.session),
            RuntimeDependencyContext(market: .china, baseURL: context.baseURL, role: context.role,
                session: try .init(accountID: 8, epoch: 1, namespace: context.session.namespace, token: "synthetic-7")),
            RuntimeDependencyContext(market: .china, baseURL: context.baseURL, role: context.role,
                session: try .init(accountID: 7, epoch: 2, namespace: context.session.namespace, token: "synthetic-7")),
            RuntimeDependencyContext(market: .china, baseURL: context.baseURL, role: context.role,
                session: try .init(accountID: 7, epoch: 1, namespace: context.session.namespace + ".other", token: "synthetic-7")),
            RuntimeDependencyContext(market: .china, baseURL: context.baseURL, role: context.role,
                session: try .init(accountID: 7, epoch: 1, namespace: context.session.namespace, token: "other-token"))
        ]
        for variant in variants {
            approvals.retained = try .init(context: variant, expiresAt: Date().addingTimeInterval(3600))
            await blocked(request, transport: transport, wire: wire)
        }
        approvals.retained = nil
        await blocked(request, transport: transport, wire: wire)
        withExtendedLifetime(root) {}
    }
    func testGuestPublicCityLayerAndLiteralPlusFilterPreserveFallbackAndExactWire() async throws {
        let wire = Wire(), approvals = Approvals(), (session, _) = try makeSession(wire, approvals: approvals, grants: [.homeAndSearch, .manualMap])
        let guest = try await session.searchMapReader.citySearch(.init(filter: .init(), area: area))
        XCTAssertNil(guest.activityFailure); XCTAssertEqual(guest.nodeFailure, .unauthorized)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/activity/list"])
        XCTAssertNil(session.account); XCTAssertNil(session.errorKey)
        await signIn(session); wire.requests = []
        _ = try await session.searchMapReader.citySearch(.init(filter: .init(keyword: "A+B"), area: area))
        let cityRequest = try XCTUnwrap(wire.requests.first { $0.url?.path == "/native/api/city/nodes" })
        XCTAssertTrue(try XCTUnwrap(cityRequest.url).absoluteString.contains("keyword=A%2BB"))
        let fields = URLComponents(url: cityRequest.url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(fields?.first { $0.name == "keyword" }?.value, "A+B")
        XCTAssertEqual(wire.deviceOrProviderCalls, 0)
    }
    func testReplacingTransportPreservesManualAreaApprovalAndCurrentIdentityCallbacks() async throws {
        let firstWire = Wire(), replacementWire = Wire(), approvals = Approvals()
        let (root, _, selection) = try directTransport(firstWire, approvals: approvals)
        // The intermediate scoped clone is temporary; its identity source must survive.
        let replacement = root.scopedForManualMap(selection).replacingUnderlying(replacementWire)
        let request = query("api/roam/pois", ["lat":"31.2", "lng":"121.5", "radius":"3000"])
        _ = try await replacement.send(request)
        XCTAssertTrue(firstWire.requests.isEmpty); XCTAssertEqual(replacementWire.requests.count, 1)
        approvals.enabled = false
        await blocked(request, transport: replacement, wire: replacementWire)
        approvals.enabled = true; selection.select(otherArea)
        await blocked(request, transport: replacement, wire: replacementWire)
        selection.select(area)
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "replacement-token") }
        await blocked(request, transport: replacement, wire: replacementWire)
        withExtendedLifetime(root) {}
    }
    func testInactiveOwnerRejectsQueuedAndButtonWorkUntilReactivated() async {
        let owner = ManualMapReadTaskOwner()
        var calls = 0
        owner.deactivate()
        owner.start { calls += 1 }
        await owner.run { calls += 1 }
        XCTAssertEqual(calls, 0)
        owner.activate()
        await owner.run { calls += 1 }
        XCTAssertEqual(calls, 1)
    }
    private var nearbyFields: [String:String] { ["longitude":"121.5", "latitude":"31.2", "radius":"2000.0", "limit":"50"] }
    private func form(_ fields: [String:String]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: URL(string: Self.base + "/api/map/nearby")!, fields: fields, token: "synthetic-7", boundary: "map-test")
    }
    private func query(_ path: String, _ fields: [String:String]) -> URLRequest {
        var url = URLComponents(string: Self.base + "/" + path)!
        if !fields.isEmpty {
            url.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: url.url!); request.httpMethod = "GET"
        request.setValue("synthetic-7", forHTTPHeaderField: "Authorization"); return request
    }
    private func directTransport(_ wire: Wire, approvals: Approvals) throws -> (CompositionHTTPTransport, CompositionHTTPTransport, ManualMapAreaSelection) {
        let root = CompositionHTTPTransport(deployment: try deployment(), underlying: wire, manualMapReadApproval: { approvals.approval($0) })
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        let selection = ManualMapAreaSelection(); selection.select(area)
        return (root, root.scopedForManualMap(selection), selection)
    }
    private func blocked(_ request: URLRequest, transport: CompositionHTTPTransport, wire: Wire, file: StaticString = #filePath, line: UInt = #line) async {
        let count = wire.requests.count
        do { _ = try await transport.send(request); XCTFail("Unexpected dispatch", file: file, line: line) } catch {}
        XCTAssertEqual(wire.requests.count, count, file: file, line: line)
    }
    @MainActor private final class Approvals {
        var enabled = true, reissueForContext = true
        var retained: ManualMapReadApproval?
        func approval(_ context: RuntimeDependencyContext) -> ManualMapReadApproval? {
            guard enabled else { return nil }
            if reissueForContext, retained?.matches(context) != true { retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(3600)) }
            return retained
        }
    }
    @MainActor private final class DeviceSpy: RoamDeviceLocationProviding {
        let onCall: () -> Void
        init(onCall: @escaping () -> Void) { self.onCall = onCall }
        func currentFix() async throws -> RoamDeviceFix { onCall(); throw APIError.notConfigured }
        func stop() { onCall() }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], role = "player", accountID = 7, nodeID = 42, status = 200, businessCode = 200
        var locationFactoryCalls = 0, locationCalls = 0
        var pausePath: String?, onPaused: (() -> Void)?, onDelivery: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var pendingData = Data()
        var deviceOrProviderCalls: Int { locationFactoryCalls + locationCalls + requests.filter { $0.url!.path.contains("reverse-geocode") || $0.url!.path.contains("presence") }.count }
        func resume(status: Int) { let value = pending; pending = nil; value?.resume(returning: (pendingData, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            let json: String
            if path.hasSuffix("/api/login/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/api/userInfo") { json = "{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/api/activity/list") { json = #"{"code":200,"data":{"rows":[]}}"# }
            else if path.hasSuffix("/api/roam/pois") { json = #"{"code":200,"data":[{"id":42,"name":"POI","type":2,"lat":31.2,"lng":121.5}]}"# }
            else if path.hasSuffix("/api/map/nearby") { json = #"{"code":200,"data":[{"id":91,"addressName":"Route node","latitude":31.2,"longitude":121.5}]}"# }
            else if path.hasSuffix("/api/city/nodes") { json = #"{"code":200,"data":[{"poiId":42,"name":"Node","lat":31.2,"lng":121.5}]}"# }
            else if path.hasSuffix("/api/city/nodes/42") { json = "{\"code\":200,\"data\":{\"poiId\":\(nodeID),\"name\":\"Node\",\"lat\":31.2,\"lng\":121.5}}" }
            else { json = #"{"code":200}"# }
            let bytes = Data(json.replacingOccurrences(of: "\"code\":200", with: "\"code\":\(businessCode)").utf8)
            if let pausePath, path.hasSuffix(pausePath) {
                self.pausePath = nil; pendingData = bytes
                return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
            }
            onDelivery?()
            return (bytes, path.contains("/api/login/") || path.hasSuffix("/api/userInfo") || path.hasSuffix("/api/logout") ? 200 : status)
        }
    }
}
