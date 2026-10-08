import XCTest
@testable import Questify

/// Synthetic HTTP uses only the actual player projection; no provider or principal objects.
@MainActor final class CityPlayerReadCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func root(_ wire: Wire, _ grants: Grants, _ vault: Vault? = nil) throws -> AppCompositionRoot {
        let vault = vault ?? Vault()
        let suite = "city-read-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.city-read", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, cityPlayerReadApproval: { grants.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testNormalRootReadsBoardOwnMembershipAndVisiblePointsOnly() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let reader = session.makeCityPlayerReader(); await reader.load()
        guard case .available(let value) = reader.state else { return XCTFail() }
        XCTAssertEqual(value.membership, .joined); XCTAssertEqual(value.participation?.participationId, "participation-1")
        XCTAssertEqual(value.points?.map(\.pointId), ["point-1"]); XCTAssertEqual(value.points?.first?.mine, true)
        XCTAssertEqual(wire.requests.compactMap { CityReadRoute(request: $0, baseURL: base)?.view }, [.current, .participation, .points])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && !$0.url!.absoluteString.contains("memberId") && !$0.url!.absoluteString.contains("epoch") })
    }
    func testUnavailableUnpublishedAndVerifiedEmptyAreDistinct() async throws {
        for mode in ["providerAbsent", "unpublished", "empty", "pointsUnavailable", "participationUnavailable"] {
            let wire = Wire(); wire.mode = mode
            let session = try root(wire, Grants()).makeSession(); await login(session)
            let reader = session.makeCityPlayerReader(); await reader.load()
            switch mode {
            case "providerAbsent": XCTAssertEqual(reader.state, .unavailable)
            case "unpublished": XCTAssertEqual(reader.state, .notPublished)
            default:
                guard case .available(let snapshot) = reader.state else { XCTFail(mode); continue }
                if mode == "empty" { XCTAssertEqual(snapshot.points, []) }
                else { XCTAssertNil(snapshot.points) }
                if mode == "participationUnavailable" { XCTAssertEqual(snapshot.membership, .unavailable); XCTAssertNil(snapshot.participation) }
            }
        }
    }
    func testMalformedMismatchedAndUnauthorizedProjectionsNeverBecomeEmptyOrOwned() async throws {
        for mode in ["wrongRegion", "wrongBoard", "wrongScope", "wrongContract", "incomplete", "duplicate", "badCoordinate", "badRevision", "notJoinedMine", "missingParticipation", "snapshotChanged", "unknownStatus", "idNewline", "hashNewline", "pointNewline", "participationNewline"] {
            let wire = Wire(); wire.mode = mode
            let session = try root(wire, Grants()).makeSession(); await login(session)
            let reader = session.makeCityPlayerReader(); await reader.load(); XCTAssertEqual(reader.state, .unavailable, mode)
        }
    }
    func testDefaultOffGuestAndRevokedReadersNeverDispatch() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let session = try root(wire, grants).makeSession(); await session.makeCityPlayerReader().load(); XCTAssertTrue(wire.requests.isEmpty)
        await login(session); wire.requests = []
        await session.makeCityPlayerReader().load(); XCTAssertTrue(wire.requests.isEmpty)
        grants.enabled = true; let reader = session.makeCityPlayerReader(); await reader.load()
        grants.retained?.revoke(); XCTAssertEqual(reader.state, .unavailable)
        let count = wire.requests.count; await reader.load(); XCTAssertEqual(wire.requests.count, count)
        grants.retained = nil; _ = session.cityPlayerReadIdentity
        await reader.load(); XCTAssertEqual(wire.requests.count, count)
        await session.makeCityPlayerReader().load(); XCTAssertGreaterThan(wire.requests.count, count)
    }
    func testLateSuccessErrorAnd401AfterIdentityLeaseOrCancellationNeverApply() async throws {
        for transition in ["owner", "roleABA", "sessionABA", "revoke", "reissue", "expire", "cancel", "close"] {
            for code in [200, 401, 402, 403, 404, 405, 406, -1] {
                let wire = Wire(), grants = Grants(), vault = Vault(), session = try root(wire, grants, vault).makeSession(); await login(session)
                let reader = session.makeCityPlayerReader(), paused = expectation(description: "city suspended")
                wire.pause = true; wire.onPaused = { paused.fulfill() }
                let task = Task { await reader.load() }; await fulfillment(of: [paused], timeout: 2)
                switch transition {
                case "owner": await session.logout(); wire.account = 8; await login(session)
                case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
                case "sessionABA": await session.logout(); await login(session)
                case "revoke": grants.retained?.revoke()
                case "reissue": grants.retained?.revoke(); grants.retained = nil; _ = session.cityPlayerReadIdentity
                case "expire": let lease = try XCTUnwrap(grants.retained); lease.expireIfNeeded(now: lease.expiresAt)
                case "close": reader.cancel()
                default: task.cancel()
                }
                wire.finish(code: code); await task.value
                XCTAssertEqual(reader.state, .unavailable, transition); XCTAssertEqual(session.account?.id, wire.account)
                XCTAssertEqual(vault.value, "synthetic-\(wire.account)")
            }
        }
    }
    func testCurrent401ExpiresOnlyCurrentSession() async throws {
        for mode in ["unauthorized", "generic401", "empty401", "thrownUnauthorized", "thrownHTTP401", "business401"] {
            let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault).makeSession(); await login(session)
            wire.mode = mode; await session.makeCityPlayerReader().load(); XCTAssertNil(session.account, mode); XCTAssertNil(vault.value, mode)
        }
    }
    func testInvalidBasesAndWholeInputIDsRejectWithoutTrapping() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
        _ = session.makeCityPlayerReader(); let context = try XCTUnwrap(grants.retained?.context)
        let route = try CityReadRoute(view: .current, regionID: "city-1")
        for raw in ["http://example.test", "https://user:password@example.test", "https://example.test?regionId=x", "https://example.test#fragment", "file:///tmp/city", "/relative", "https://host.invalid"] {
            let url = try XCTUnwrap(URL(string: raw))
            let changed = RuntimeDependencyContext(market: context.market, baseURL: url, role: context.role, session: context.session)
            XCTAssertThrowsError(try CityPlayerReadApproval(context: changed, regionID: "city-1", expiresAt: Date().addingTimeInterval(60)), raw)
            XCTAssertThrowsError(try route.request(baseURL: url, token: "synthetic-7"), raw)
        }
        for invalid in ["city-1\n", "city-1\r", "city-1\r\n", "city-1\u{2028}"] {
            XCTAssertThrowsError(try CityReadRoute(view: .current, regionID: invalid))
            XCTAssertThrowsError(try CityPlayerReadApproval(context: context, regionID: invalid, expiresAt: Date().addingTimeInterval(60)))
            var request = try route.request(baseURL: base, token: "synthetic-7")
            var parts = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            parts.queryItems = [URLQueryItem(name: "regionId", value: invalid)]; request.url = parts.url
            XCTAssertNil(CityReadRoute(request: request, baseURL: base))
        }
    }
    func testOuterTransportClonesRetainExactRegionAndRejectAdjacentWritesAndOverrides() async throws {
        let wire = Wire(), grants = Grants(), transport = try root(wire, grants).transport()
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        let clone = transport.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        let valid = try CityReadRoute(view: .current, regionID: "city-1").request(baseURL: base, token: "synthetic-7")
        _ = try await clone.send(valid); let count = wire.requests.count
        var requests = [URLRequest]()
        for suffix in ["&memberId=7", "&regionId=city-1", "&sessionEpoch=1", "#fragment"] { var request = valid; request.url = URL(string: valid.url!.absoluteString + suffix); requests.append(request) }
        for method in ["POST", "PUT", "DELETE"] { var request = valid; request.httpMethod = method; requests.append(request) }
        for replacement in ["join", "leave", "capture", "toll", "claim", "receipt", "current/"] { var request = valid; request.url = URL(string: valid.url!.absoluteString.replacingOccurrences(of: "/current?", with: "/\(replacement)?")); requests.append(request) }
        for region in ["city-2"] { requests.append(try CityReadRoute(view: .current, regionID: region).request(baseURL: base, token: "synthetic-7")) }
        var request = valid; request.setValue("wrong-token", forHTTPHeaderField: "Authorization"); requests.append(request)
        request = valid; request.url = URL(string: valid.url!.absoluteString.replacingOccurrences(of: "example.test", with: "evil.test")); requests.append(request)
        request = valid; request.httpBody = Data("{}".utf8); requests.append(request)
        for request in requests { do { _ = try await clone.send(request); XCTFail("unexpected dispatch") } catch {} }
        XCTAssertEqual(wire.requests.count, count)
        grants.retained?.revoke(); do { _ = try await clone.send(valid); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, count)
    }
    func testPointSelectionRechecksAccountRoleSessionAndLeaseBeforeCardOrTap() async throws {
        for transition in ["owner", "roleABA", "sessionABA", "revoke", "reissue", "expire", "close"] {
            let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
            let reader = session.makeCityPlayerReader(); await reader.load()
            let rendered = try XCTUnwrap(reader.pointMapContext)
            let selected = try XCTUnwrap(CityPointSelection(pointID: "point-1", rendered: rendered, current: reader.pointMapContext))
            XCTAssertEqual(selected.point(in: reader.pointMapContext)?.pointId, "point-1")
            switch transition {
            case "owner": await session.logout(); wire.account = 8; await login(session)
            case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
            case "sessionABA": await session.logout(); await login(session)
            case "revoke": grants.retained?.revoke()
            case "reissue": grants.retained?.revoke(); grants.retained = nil; _ = session.cityPlayerReadIdentity
            case "expire": let lease = try XCTUnwrap(grants.retained); lease.expireIfNeeded(now: lease.expiresAt)
            default: reader.cancel()
            }
            let count = wire.requests.count
            XCTAssertNil(reader.pointMapContext, transition)
            XCTAssertNil(selected.point(in: reader.pointMapContext), transition)
            XCTAssertNil(CityPointSelection(pointID: "point-1", rendered: rendered, current: reader.pointMapContext), transition)
            XCTAssertEqual(wire.requests.count, count, "selection must not dispatch")
        }
    }
    func testPointSelectionRefreshLoadingAndUnavailableStatesDropOldProjection() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        let reader = session.makeCityPlayerReader(); await reader.load()
        let first = try XCTUnwrap(reader.pointMapContext)
        let selected = try XCTUnwrap(CityPointSelection(pointID: "point-1", rendered: first, current: first))
        await reader.load()
        let refreshed = try XCTUnwrap(reader.pointMapContext)
        XCTAssertEqual(first.snapshot, refreshed.snapshot); XCTAssertNotEqual(first.readID, refreshed.readID)
        XCTAssertNil(selected.point(in: refreshed))
        XCTAssertNil(CityPointSelection(pointID: "point-1", rendered: first, current: refreshed))
        let paused = expectation(description: "refresh loading")
        wire.pause = true; wire.onPaused = { paused.fulfill() }
        let task = Task { await reader.load() }; await fulfillment(of: [paused], timeout: 2)
        XCTAssertEqual(reader.state, .loading); XCTAssertNil(reader.pointMapContext)
        XCTAssertNil(selected.point(in: reader.pointMapContext))
        reader.cancel(); wire.pause = false; wire.finish(code: 200); await task.value
        XCTAssertNil(reader.pointMapContext)
        for mode in ["providerAbsent", "unpublished", "pointsUnavailable", "participationUnavailable", "duplicate"] {
            wire.mode = mode; await reader.load(); XCTAssertNil(reader.pointMapContext, mode)
            XCTAssertNil(CityPointSelection(pointID: "point-1", rendered: first, current: reader.pointMapContext), mode)
        }
        wire.mode = "empty"; await reader.load()
        XCTAssertEqual(reader.pointMapContext?.points, [])
        XCTAssertNil(selected.point(in: reader.pointMapContext))
    }
    func testPointSelectionAcrossDifferentReadersNeverReusesIdenticalSnapshot() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        let firstReader = session.makeCityPlayerReader(), nextReader = session.makeCityPlayerReader()
        await firstReader.load(); await nextReader.load()
        let first = try XCTUnwrap(firstReader.pointMapContext), next = try XCTUnwrap(nextReader.pointMapContext)
        XCTAssertEqual(first.snapshot, next.snapshot); XCTAssertNotEqual(first.readID, next.readID)
        XCTAssertNil(CityPointSelection(pointID: "point-1", rendered: first, current: next))
    }
    func testOneSnapshotRecoveryKeepsNormalRootScopeAndRereadsEveryProjection() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        wire.requests = []; wire.mode = "snapshotChangedOnce"
        let reader = session.makeCityPlayerReader(); await reader.load()
        guard case .available(let value) = reader.state else { return XCTFail("recovery unavailable") }
        XCTAssertEqual(value.board.revision, 2)
        XCTAssertEqual(wire.requests.compactMap { CityReadRoute(request: $0, baseURL: base)?.view },
                       [.current, .participation, .current, .participation, .points])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        for request in wire.requests.suffix(2) {
            let items = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first { $0.name == "revision" }?.value, "2")
            XCTAssertEqual(items.first { $0.name == "regionId" }?.value, "city-1")
        }
    }
    func testRepeatedSnapshotChangeStopsAfterOneRecoveryThroughNormalRoot() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        wire.requests = []; wire.mode = "snapshotChanged"
        let reader = session.makeCityPlayerReader(); await reader.load()
        XCTAssertEqual(reader.state, .unavailable)
        XCTAssertEqual(wire.requests.compactMap { CityReadRoute(request: $0, baseURL: base)?.view },
                       [.current, .participation, .current, .participation])
    }
    @MainActor private final class Grants {
        var enabled = true; var retained: CityPlayerReadApproval?
        func select(_ context: RuntimeDependencyContext) -> CityPlayerReadApproval? {
            guard enabled else { return nil }
            if retained == nil || !ContentDraftContextFence.matches(retained?.context, context) {
                retained?.revoke(); retained = try? .init(context: context, regionID: "city-1", expiresAt: Date().addingTimeInterval(600))
            }
            return retained
        }
    }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], account = 7, role = "player", mode = "available", pause = false, onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?, pendingData = Data()
        var changedOnce = false
        func finish(code: Int) {
            let saved = pending; pending = nil
            if code == -1 { saved?.resume(throwing: APIError.httpStatus(503)); return }
            if code == 402 { saved?.resume(returning: (Data(#"{"code":401,"msg":"Unauthorized"}"#.utf8), 401)); return }
            if code == 403 { saved?.resume(returning: (Data(), 401)); return }
            if code == 404 { saved?.resume(throwing: APIError.unauthorized); return }
            if code == 405 { saved?.resume(throwing: APIError.httpStatus(401)); return }
            if code == 406 { saved?.resume(returning: (Data(#"{"code":401,"msg":"Unauthorized"}"#.utf8), 200)); return }
            saved?.resume(returning: code == 200 ? (pendingData, 200) : (Data(#"{"code":401,"errorCode":"AUTH_REQUIRED"}"#.utf8), 401))
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}".utf8), 200) }
            guard path.contains("/city-game/") else { return (Data(#"{"code":200}"#.utf8), 200) }
            func error(_ status: Int, _ code: String) throws -> (Data, Int) { (try JSONSerialization.data(withJSONObject: ["code": status, "errorCode": code]), status) }
            if mode == "providerAbsent" { return try error(503, "CITY_READ_UNAVAILABLE") }
            if mode == "unauthorized" { return try error(401, "AUTH_REQUIRED") }
            if mode == "generic401" { return (Data(#"{"code":401,"msg":"Unauthorized"}"#.utf8), 401) }
            if mode == "empty401" { return (Data(), 401) }
            if mode == "thrownUnauthorized" { throw APIError.unauthorized }
            if mode == "thrownHTTP401" { throw APIError.httpStatus(401) }
            if mode == "business401" { return (Data(#"{"code":401,"msg":"Unauthorized"}"#.utf8), 200) }
            if mode == "snapshotChangedOnce", !changedOnce, !path.hasSuffix("/current") {
                changedOnce = true; return try error(409, "CITY_SNAPSHOT_CHANGED")
            }
            if mode == "snapshotChanged", !path.hasSuffix("/current") { return try error(409, "CITY_SNAPSHOT_CHANGED") }
            if mode == "participationUnavailable", path.hasSuffix("/participation") { return try error(503, "CITY_PARTICIPATION_UNAVAILABLE") }
            if mode == "pointsUnavailable", path.hasSuffix("/points") { return try error(503, "CITY_POINTS_UNAVAILABLE") }
            var board: [String: Any] = ["gameId":"game-1", "boardId":"board-1", "regionId":"city-1", "seasonId":"season-1", "rulesReleaseId":"release-1", "rulesHash":String(repeating:"a",count:64), "lifecycle":"OPEN", "title":"Synthetic official city", "revision":1]
            if changedOnce { board["revision"] = 2 }
            if mode == "wrongRegion" { board["regionId"] = "city-2" }
            if mode == "wrongBoard", !path.hasSuffix("/current") { board["boardId"] = "board-2" }
            if mode == "idNewline" { board["boardId"] = "board-1\n" }
            if mode == "hashNewline" { board["rulesHash"] = String(repeating: "a", count: 64) + "\n" }
            if mode == "badRevision" { board["revision"] = -1 }
            var payload: [String: Any] = ["contract":"CITY_PLAYER_READ_V1", "scope":"CITY", "status":"AVAILABLE", "board":board]
            let membership = mode == "notJoinedMine" ? "NOT_JOINED" : "JOINED"
            if path.hasSuffix("/current") { payload["participationStatus"] = membership; payload["pointsStatus"] = "AVAILABLE" }
            if path.hasSuffix("/participation") {
                payload["participationStatus"] = membership
                if membership == "JOINED", mode != "missingParticipation" { payload["participation"] = ["participationId":mode == "participationNewline" ? "participation-1\n" : "participation-1", "membershipVersion":1] }
            }
            if path.hasSuffix("/points") {
                let point: [String: Any] = ["pointId":mode == "pointNewline" ? "point-1\n" : "point-1", "title":"Visible location", "latitude":mode == "badCoordinate" ? 91 : 31, "longitude":121, "mine":true]
                payload["points"] = mode == "empty" ? [] : mode == "duplicate" ? [point,point] : [point]
                payload["complete"] = mode != "incomplete"
            }
            if mode == "unpublished" { payload = ["contract":"CITY_PLAYER_READ_V1", "scope":"CITY", "status":"NO_CURRENT_BOARD", "regionId":"city-1"] }
            if mode == "wrongScope" { payload["scope"] = "THEME" }
            if mode == "wrongContract" { payload["contract"] = "OTHER" }
            if mode == "unknownStatus" { payload["status"] = "UNKNOWN" }
            let data = try JSONSerialization.data(withJSONObject: ["code":200, "data":payload])
            if pause { pendingData = data; return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (data, 200)
        }
    }
}
