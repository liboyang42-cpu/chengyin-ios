import XCTest
@testable import Questify

/// Normal factory regressions with explicit synthetic grants, isolated storage, and no live requests.
@MainActor final class CityAcquisitionNormalEntryTests: XCTestCase {
    private let base = URL(string: "https://city-acquisition.example/native")!
    private func defaults() throws -> UserDefaults {
        let suite = "city-acquisition-root-" + UUID().uuidString, values = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { values.removePersistentDomain(forName: suite) }; return values
    }
    private func root(_ wire: Wire, values: UserDefaults, grants: Grants? = nil) throws -> AppCompositionRoot {
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.city-acquisition", realm: "synthetic")
        let vault = Vault()
        var root = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: values, tokenStore: { _ in vault }),
            makeTransport: { wire }, sessionDependencies: { _ in .dormant })
        if let grants { root.cityAcquisitionApproval = { grants.selected($0) } }
        return root
    }
    private func login(_ app: AppSession) async throws {
        app.authChannels.cancel(); await app.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(app.account?.id, 7)
        guard app.account?.id == 7 else { throw APIError.malformedResponse }
    }
    private func journal(_ values: UserDefaults, _ lease: CityAcquisitionApproval) -> (CityAcquisitionIdentityJournal, OperationPendingRecord, String) {
        let context = lease.context
        let owner = "city-acquisition:\(context.session.namespace):\(context.baseURL.absoluteString):\(context.session.accountID)", target = lease.regionID
        let record = OperationPendingRecord(ownerKey: owner, targetKey: target)
        let key = "questify.operations.pending.v1." + Data("\(owner.utf8.count):\(owner):\(target)".utf8).base64EncodedString()
        return (.init(defaults: values, ownerKey: owner, targetKey: target), record, key)
    }
    func testNormalFactoryDefaultOffMakesNoAcquisitionRequest() async throws {
        let wire = Wire(), app = try root(wire, values: defaults()).makeSession(); try await login(app)
        let model = app.makeCityAcquisitionController(); await model.open(activity: model.activityID)
        XCTAssertFalse(model.current); XCTAssertFalse(model.canWrite); XCTAssertNil(model.snapshot); XCTAssertTrue(wire.cityRequests.isEmpty)
    }
    func testReadOnlyGrantReadsPersonalTitlesWithoutBoardGrantOrWritePermission() async throws {
        let wire = Wire(), grants = Grants()
        let app = try root(wire, values: defaults(), grants: grants).makeSession(); try await login(app)
        let model = app.makeCityAcquisitionController(); await model.open(activity: model.activityID)
        XCTAssertEqual(model.snapshot?.status, "JOIN_REQUIRED"); XCTAssertFalse(model.canWrite)
        XCTAssertEqual(wire.cityRequests.count, 2); XCTAssertTrue(wire.posts.isEmpty)
        XCTAssertTrue(wire.cityRequests.allSatisfy { $0.url?.path.contains("/acquisition/") == true })
    }
    func testUnknownSurvivesNewRootAndOnlyReadsOriginalUUID() async throws {
        let values = try defaults(), wire = Wire(), grants = Grants()
        let app = try root(wire, values: values, grants: grants).makeSession(); try await login(app)
        let model = app.makeCityAcquisitionController(), lease = try XCTUnwrap(grants.lease)
        let (store, original, _) = journal(values, lease); try store.write(original)
        await model.open(activity: model.activityID); XCTAssertEqual(model.pendingRequestID, original.operationID)
        await app.logout(); XCTAssertFalse(model.current)
        let next = try root(wire, values: values, grants: Grants()).makeSession(); try await login(next)
        let restored = next.makeCityAcquisitionController(); await restored.open(activity: restored.activityID)
        XCTAssertEqual(restored.pendingRequestID, original.operationID); XCTAssertFalse(restored.canWrite); XCTAssertTrue(wire.posts.isEmpty)
        XCTAssertTrue(wire.cityRequests.allSatisfy { $0.url?.lastPathComponent == original.operationID.uuidString && $0.httpMethod == "GET" })
    }
    func testKnownOriginalMarkerIsReauthorizedAfterFreshFactoryNotTreatedAsSuccess() async throws {
        let values = try defaults(), wire = Wire(), grants = Grants()
        let app = try root(wire, values: values, grants: grants).makeSession(); try await login(app)
        _ = app.makeCityAcquisitionController()
        let (store, original, _) = journal(values, try XCTUnwrap(grants.lease))
        try store.write(original); try store.clear(original)
        let model = app.makeCityAcquisitionController(); XCTAssertNil(model.receipt)
        wire.rejection = true; await model.open(activity: model.activityID)
        XCTAssertNil(model.pendingRequestID); XCTAssertEqual(model.originalRequestID, original.operationID)
        XCTAssertEqual(model.receipt?.requestId, original.operationID.uuidString); XCTAssertEqual(model.receipt?.succeeded, false)
        XCTAssertEqual(model.receipt?.errorCode, "POINT_ALREADY_OWNED"); XCTAssertTrue(wire.posts.isEmpty)
        XCTAssertEqual(try store.original(ownerKey: original.ownerKey, targetKey: original.targetKey), original)
    }
    func testUnknownMetadataAtOriginalPendingKeyFailsClosedWithoutNetwork() async throws {
        let values = try defaults(), wire = Wire(), grants = Grants()
        let app = try root(wire, values: values, grants: grants).makeSession(); try await login(app)
        let model = app.makeCityAcquisitionController()
        let (_, record, storageKey) = journal(values, try XCTUnwrap(grants.lease))
        let raw = try JSONSerialization.data(withJSONObject: ["operationID": record.operationID.uuidString, "ownerKey": record.ownerKey,
            "targetKey": record.targetKey, "acknowledgedSteps": 0, "futureMetadata": NSNull()])
        values.set(raw, forKey: storageKey); await model.open(activity: model.activityID)
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.canWrite); XCTAssertTrue(wire.cityRequests.isEmpty)
        XCTAssertEqual(values.data(forKey: storageKey), raw)
    }
    func testGrantRevocationImmediatelyHidesFactsAndStopsFurtherReads() async throws {
        let wire = Wire(), grants = Grants()
        let app = try root(wire, values: defaults(), grants: grants).makeSession(); try await login(app)
        let model = app.makeCityAcquisitionController(); await model.open(activity: model.activityID)
        XCTAssertNotNil(model.snapshot); let count = wire.cityRequests.count
        try XCTUnwrap(grants.lease).revoke(); XCTAssertFalse(model.current); XCTAssertNil(model.snapshot)
        await model.open(activity: model.activityID); XCTAssertEqual(wire.cityRequests.count, count)
    }
    func testRoleABACannotReactivateOldAcquisitionFactory() async throws {
        let wire = Wire(), grants = Grants()
        let app = try root(wire, values: defaults(), grants: grants).makeSession(); try await login(app)
        let model = app.makeCityAcquisitionController(); await model.open(activity: model.activityID)
        wire.role = "merchant"; await app.refreshOwnAccount(); wire.role = "player"; await app.refreshOwnAccount()
        XCTAssertFalse(model.current); XCTAssertNil(model.snapshot)
        let next = app.makeCityAcquisitionController(); await next.open(activity: next.activityID)
        XCTAssertTrue(next.current); XCTAssertNotNil(next.snapshot); XCTAssertTrue(wire.posts.isEmpty)
    }
    @MainActor private final class Grants {
        var lease: CityAcquisitionApproval?
        func selected(_ context: RuntimeDependencyContext) -> CityAcquisitionApproval? {
            if let lease { return lease }
            lease = try? .init(context: context, regionID: "city-1", allowsWrite: false, expiresAt: Date().addingTimeInterval(600)); return lease
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role = "player", rejection = false
        var requests: [URLRequest] = []
        var cityRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/city-game/") == true } }
        var posts: [URLRequest] { cityRequests.filter { $0.httpMethod == "POST" } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.contains("/api/city-game/") != true {
                switch request.url?.lastPathComponent {
                case "phone": return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7}}"#.utf8), 200)
                case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
                case "logout": return (Data(#"{"code":200}"#.utf8), 200)
                default: XCTFail("Unexpected synthetic root request"); throw APIError.invalidRequest
                }
            }
            guard request.httpMethod == "GET", request.url?.path.contains("/acquisition/") == true else { XCTFail("Unexpected operation"); throw APIError.invalidRequest }
            var envelope: [String: Any] = ["code": 200]
            var status = 200
            if request.url?.path.contains("/request/") == true {
                status = rejection ? 409 : 202; envelope["code"] = status
                envelope["data"] = ["requestId": request.url!.lastPathComponent, "requestStatus": rejection ? "COMPLETE" : "UNKNOWN"]
                if rejection { envelope["errorCode"] = "POINT_ALREADY_OWNED" }
            } else if request.url?.path.hasSuffix("/titles") == true {
                envelope["data"] = ["contract": "CITY_ACQUISITION_V1", "memberId": 7, "regionId": "city-1", "titles": []]
            } else {
                envelope["data"] = ["contract": "CITY_ACQUISITION_V1", "memberId": 7, "regionId": "city-1", "status": "JOIN_REQUIRED",
                    "writeApproved": false, "candidates": [], "ownership": [], "ownTitles": []]
            }
            return (try JSONSerialization.data(withJSONObject: envelope), status)
        }
    }
}
