import XCTest
@testable import Questify

/// Cross-family integration regressions. Synthetic recorder only; Apple execution is separate.
@MainActor final class IntegratedReadCompositionTests: XCTestCase {
    private typealias Identity = CompositionHTTPTransport.SessionIdentity
    private let base = URL(string: "https://example.test/native")!
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.5)!, label: "Manual A")
    private func deployment(grants: Set<ReviewedAppDeployment.ReadGrant> = [.manualMap, .playNodesAndRouteState],
                            details: Bool = true) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.integrated-reads", realm: "synthetic",
            reads: grants, contentDetails: details ? .activityAndTopic : nil)
    }
    private func makeRoot(_ wire: Wire, approvals: Approvals, grants: Set<ReviewedAppDeployment.ReadGrant> = [.manualMap, .playNodesAndRouteState],
                          details: Bool = true) throws -> (CompositionHTTPTransport, ManualMapAreaSelection) {
        let deployment = try deployment(grants: grants, details: details)
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: deployment.storageScope.service, token: "synthetic-7"))
        approvals.manual = try .init(context: context, expiresAt: .distantFuture)
        approvals.owner = try .init(grant: .init(context: context, ownerMemberID: 7, scope: .personal,
            routes: [.list, .restore], expiresAt: .distantFuture))
        approvals.play = .init(market: .china, endpoints: try .init(baseURL: base, namespace: deployment.storageScope.service,
            accountID: 7, paths: ["api/play/nodes", "api/play/route-state"]), play: [.reads], playReadApprovalID: UUID())
        let root = CompositionHTTPTransport(deployment: deployment, underlying: wire,
            ownerDraftReadApproval: { _ in approvals.ownerEnabled ? approvals.owner : nil },
            manualMapReadApproval: { _ in approvals.manualEnabled ? approvals.manual : nil })
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        root.playReadConfiguration = { _ in approvals.playEnabled ? approvals.play : nil }
        let selection = ManualMapAreaSelection(); selection.select(area)
        return (root, selection)
    }
    private func get(_ path: String, query: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: base.absoluteString + "/" + path + (query.map { "?" + $0 } ?? ""))!)
        request.httpMethod = "GET"; request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("synthetic-7", forHTTPHeaderField: "Authorization"); return request
    }
    private func form(_ path: String, fields: [String: String] = ["id": "21"]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields,
            token: "synthetic-7", boundary: "IntegratedReadBoundary")
    }
    private func familyRequests() throws -> [URLRequest] {
        [get("api/roam/pois", query: "lat=31.2&lng=121.5&radius=3000"),
         get("api/play/nodes", query: "activityId=21"), try form("api/activity/info")]
    }
    private func blocked(_ request: URLRequest, through transport: CompositionHTTPTransport, wire: Wire,
                         file: StaticString = #filePath, line: UInt = #line) async {
        let before = wire.requests.count
        do { _ = try await transport.send(request); XCTFail("Unexpected dispatch", file: file, line: line) } catch {}
        XCTAssertEqual(wire.requests.count, before, file: file, line: line)
    }
    func testBothCloneOrdersPreserveAllReadFamiliesAndExistingOwnerCallback() async throws {
        for scopeFirst in [false, true] {
            let old = Wire(), replacement = Wire(), approvals = Approvals(); approvals.ownerEnabled = true
            let (root, selection) = try makeRoot(old, approvals: approvals)
            let clone = scopeFirst ? root.scopedForManualMap(selection).replacingUnderlying(replacement)
                                   : root.replacingUnderlying(replacement).scopedForManualMap(selection)
            var requests = try familyRequests()
            requests += [get("api/play/route-state", query: "topicId=31"), try form("api/topic/info-to-user"), get("api/city/nodes/42")]
            var owner = get(ContentDraftRoute.list.path); owner.httpMethod = "POST"; owner.httpBody = Data("scope=".utf8)
            owner.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            requests.append(owner)
            for request in requests { _ = try await clone.send(request) }
            XCTAssertTrue(old.requests.isEmpty); XCTAssertEqual(replacement.requests.count, requests.count)
            approvals.ownerEnabled = false; await blocked(owner, through: clone, wire: replacement)
        }
    }
    func testEarlyClonesObserveMutablePlayInstallationRevocationAndReplacement() async throws {
        let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
        root.playReadConfiguration = { _ in nil }
        let clone = root.scopedForManualMap(selection).replacingUnderlying(wire)
        let request = get("api/play/nodes", query: "activityId=21")
        await blocked(request, through: clone, wire: wire)
        root.playReadConfiguration = { _ in approvals.play }
        _ = try await clone.send(request)
        root.playReadConfiguration = { _ in nil }
        await blocked(request, through: clone, wire: wire)
        root.playReadConfiguration = { _ in approvals.play }
        _ = try await clone.send(request)
        XCTAssertEqual(wire.requests.count, 2)
    }
    func testThreeDeploymentGrantsAreIndependentAcrossBothCloneOrders() async throws {
        for scopeFirst in [false, true] {
            for mask in 0..<8 {
                let wire = Wire(), approvals = Approvals()
                var grants: Set<ReviewedAppDeployment.ReadGrant> = []
                if mask & 1 != 0 { grants.insert(.manualMap) }
                if mask & 2 != 0 { grants.insert(.playNodesAndRouteState) }
                let (root, selection) = try makeRoot(wire, approvals: approvals, grants: grants, details: mask & 4 != 0)
                let clone = scopeFirst ? root.scopedForManualMap(selection).replacingUnderlying(wire)
                                       : root.replacingUnderlying(wire).scopedForManualMap(selection)
                for (index, request) in try familyRequests().enumerated() {
                    if mask & (1 << index) != 0 { _ = try await clone.send(request) }
                    else { await blocked(request, through: clone, wire: wire) }
                }
                XCTAssertEqual(wire.requests.count, mask.nonzeroBitCount)
            }
        }
    }
    func testRuntimeReadApprovalsDoNotAuthorizeSiblingFamilies() async throws {
        let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
        let clone = root.replacingUnderlying(wire).scopedForManualMap(selection), requests = try familyRequests()
        approvals.manualEnabled = false
        await blocked(requests[0], through: clone, wire: wire)
        _ = try await clone.send(requests[1]); _ = try await clone.send(requests[2])
        approvals.manualEnabled = true; approvals.playEnabled = false
        _ = try await clone.send(requests[0]); await blocked(requests[1], through: clone, wire: wire)
        _ = try await clone.send(requests[2]); XCTAssertEqual(wire.requests.count, 4)
    }
    func testQueryExceptionCannotLaunderCrossFamilyOrUnreviewedRoutes() async throws {
        let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
        let clone = root.scopedForManualMap(selection).replacingUnderlying(wire)
        var requests = [get("api/play/nodes", query: "lat=31.2&lng=121.5&radius=3000"),
            get("api/roam/pois", query: "activityId=21"), get("api/city/nodes/42", query: "activityId=21"),
            get("api/play/ending", query: "activityId=21"), get("api/play/nodes", query: "activityId=21&activityId=21"),
            get("api/roam/pois", query: "lat=31.2&lng=121.5&radius=3000&activityId=21"),
            get("api/template/topic-template/info", query: "activityId=21"), get("api/user/userInfo", query: "activityId=21")]
        var detail = try form("api/activity/info")
        detail.url = URL(string: detail.url!.absoluteString + "?activityId=21"); requests.append(detail)
        var play = get("api/play/nodes", query: "activityId=21"); play.httpBody = Data("id=21".utf8); requests.append(play)
        for request in requests { await blocked(request, through: clone, wire: wire) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAllThreeReadGrantsStillLeavePublicHomePrivateHomeAndWritesClosed() async throws {
        let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
        let clone = root.replacingUnderlying(wire).scopedForManualMap(selection)
        for path in ["api/activity/list", "api/template/topic-template/info", PrivateHomeService.path,
                     "api/play/answer", "api/play/run-session", "api/roam/reveal", "api/registration/create"] {
            await blocked(try form(path), through: clone, wire: wire)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGuestAndPartialIdentityCannotBorrowAnySignedInReadGrant() async throws {
        let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
        let clone = root.scopedForManualMap(selection).replacingUnderlying(wire)
        for identity in [Identity(epoch: 1, accountID: nil, role: nil, token: nil),
                         .init(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: "player", token: nil)] {
            root.current = { identity }
            for request in try familyRequests() { await blocked(request, through: clone, wire: wire) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testManualAreaReplacementDoesNotDisableSiblingDetailAndPlay() async throws {
        let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
        let clone = root.scopedForManualMap(selection).replacingUnderlying(wire), requests = try familyRequests()
        selection.select(nil)
        await blocked(requests[0], through: clone, wire: wire)
        _ = try await clone.send(requests[1]); _ = try await clone.send(requests[2])
        selection.select(area); _ = try await clone.send(requests[0]); XCTAssertEqual(wire.requests.count, 3)
    }
    func testSameViewerReissueCancelsCloneInflightSuccessHTTP401AndThrown401() async throws {
        for family in 0...1 {
            for response in 0...2 {
                let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
                let clone = root.scopedForManualMap(selection).replacingUnderlying(wire)
                let request = try familyRequests()[family]
                let started = expectation(description: "Family read suspended"); wire.onPaused = { started.fulfill() }; wire.pause = true
                let task = Task { try await clone.send(request) }
                await fulfillment(of: [started], timeout: 2)
                guard wire.hasPending else { task.cancel(); return XCTFail("Recorder was not reached") }
                if family == 0 {
                    approvals.manual = try .init(context: XCTUnwrap(approvals.manual).context, expiresAt: .distantFuture)
                } else {
                    let old = try XCTUnwrap(approvals.play)
                    approvals.play = .init(market: old.market, endpoints: old.endpoints, play: [.reads], playReadApprovalID: UUID())
                }
                wire.finish(response)
                do { _ = try await task.value; XCTFail("Retired issuance returned") } catch is CancellationError {} catch { XCTFail("\(error)") }
            }
        }
    }
    func testRootIdentityABAAndTaskCancellationFenceAllClonedFamilies() async throws {
        for cancellation in [false, true] {
            for request in try familyRequests() {
                let wire = Wire(), approvals = Approvals(), (root, selection) = try makeRoot(wire, approvals: approvals)
                let clone = root.replacingUnderlying(wire).scopedForManualMap(selection)
                let started = expectation(description: "Clone read suspended"); wire.onPaused = { started.fulfill() }; wire.pause = true
                let task = Task { try await clone.send(request) }
                await fulfillment(of: [started], timeout: 2)
                guard wire.hasPending else { task.cancel(); return XCTFail("Recorder was not reached") }
                if cancellation { task.cancel() }
                else { root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3) } }
                wire.finish(1)
                do { _ = try await task.value; XCTFail("Retired viewer returned") } catch is CancellationError {} catch { XCTFail("\(error)") }
            }
        }
    }
    @MainActor private final class Approvals {
        var manualEnabled = true, playEnabled = true, ownerEnabled = false
        var manual: ManualMapReadApproval?
        var owner: OwnerDraftReadApproval?
        var play: RuntimeDependencyConfiguration?
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], pause = false
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        var hasPending: Bool { pending != nil }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if pause { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(#"{"code":200}"#.utf8), 200)
        }
        func finish(_ response: Int) {
            let continuation = pending; pending = nil; pause = false
            if response == 2 { continuation?.resume(throwing: APIError.unauthorized) }
            else { continuation?.resume(returning: (Data((response == 1 ? #"{"code":401}"# : #"{"code":200}"#).utf8), response == 1 ? 401 : 200)) }
        }
    }
}
