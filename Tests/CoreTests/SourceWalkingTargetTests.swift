import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class SourceWalkingTargetTests: XCTestCase {
    private func owner() throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.com/")!, role: "member",
              session: try .init(accountID: 7, epoch: 1, namespace: "fixture-cn", token: "synthetic"))
    }
    func testUnreviewedEvidenceKeysCannotConvertSuccessfulDetailIntoAuthority() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        transport.body = #"{"code":200,"data":{"poiId":7,"name":"Stop","lat":1,"lng":1,"status":1,"navigationEvidence":{"namespace":"roam_poi","targetId":7,"latitude":1,"longitude":1,"coordinateDatum":"WGS84","countryRegion":"US","publicVisibility":"CURRENT_PUBLIC","authorityRevision":"unreviewed","navigationIssuedAt":1791014400000,"navigationExpiresAt":1791014520000}}}"#
        let context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { context })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner, current: { owner })
        do { _ = try await authorizer.authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingTargetReadFailure, .missingEvidence(["publicVisibility", "coordinateDatum", "countryRegion", "authorityRevision", "navigationIssuedAt", "navigationExpiresAt"])) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testRemovedCityAndMissingGeometryRemainUnavailable() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        let context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { context })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner, current: { owner })
        for body in [#"{"code":410}"#, #"{"code":200,"data":{"poiId":7,"name":"Stop","status":1}}"#] {
            transport.body = body
            do { _ = try await authorizer.authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
            catch { XCTAssertEqual(error as? WalkingNavigationFailure, .targetUnavailable) }
        }
    }
    func testPreviewCancelledDuringAuthorizationRejectsLateTargetBeforeProvider() async throws {
        let reference = try WalkingTargetReference(kind: .cityNode, id: 7)
        let targets = try PreviewTargets(reference), provider = PreviewRecorder()
        targets.suspend = true
        let planner = AuthorizedWalkingPreviewPlanner(reference: reference, targets: targets, planner: provider, current: { true })
        let request = previewRequest(targets)
        let task = Task { try await planner.preview(request) }
        for _ in 0..<100 { if targets.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(targets.pending)
        planner.cancel(); pending.resume(returning: targets.value)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(provider.calls, 0); XCTAssertEqual(provider.cancels, 1)
        targets.suspend = false
        let reopenedProvider = PreviewRecorder()
        let reopened = AuthorizedWalkingPreviewPlanner(reference: reference, targets: targets, planner: reopenedProvider, current: { true })
        _ = try await reopened.preview(request)
        XCTAssertEqual(targets.calls, 2); XCTAssertEqual(reopenedProvider.calls, 1)
    }
    func testPreviewDropsSuspendedRouteAfterCancellationOrContextChange() async throws {
        for cancel in [true, false] {
            let reference = try WalkingTargetReference(kind: .cityNode, id: 7)
            let targets = try PreviewTargets(reference), provider = PreviewRecorder()
            var current = true
            provider.suspend = true
            let planner = AuthorizedWalkingPreviewPlanner(reference: reference, targets: targets, planner: provider, current: { current })
            let request = previewRequest(targets)
            let task = Task { try await planner.preview(request) }
            for _ in 0..<100 { if provider.pending != nil { break }; await Task.yield() }
            let pending = try XCTUnwrap(provider.pending)
            if cancel { planner.cancel() } else { current = false }
            pending.resume(returning: try provider.route(request))
            do { _ = try await task.value; XCTFail() }
            catch {
                if cancel { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual(error as? WalkingNavigationFailure, .staleContext) }
            }
            XCTAssertEqual(provider.calls, 1)
        }
    }
    func testPreviewRechecksExpiryAfterSuspendedProviderReturns() async throws {
        let reference = try WalkingTargetReference(kind: .cityNode, id: 7)
        let targets = try PreviewTargets(reference), provider = PreviewRecorder()
        var now = targets.value.expiresAt.addingTimeInterval(-120)
        provider.suspend = true
        let planner = AuthorizedWalkingPreviewPlanner(reference: reference, targets: targets, planner: provider, current: { true }, now: { now })
        let request = previewRequest(targets)
        let task = Task { try await planner.preview(request) }
        for _ in 0..<100 { if provider.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(provider.pending)
        now = targets.value.expiresAt
        pending.resume(returning: try provider.route(request))
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .targetUnavailable) }
        XCTAssertEqual(provider.calls, 1)
    }
    private func previewRequest(_ targets: PreviewTargets) -> SearchRouteRequest {
        .init(origin: .init(latitude: 1, longitude: 1)!, destination: targets.value.coordinate.point, mode: .walking, datum: .wgs84, region: "US")
    }
    func testFreshCityReadDoesNotInventMissingProvenance() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        let context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { context })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner, current: { owner })
        for _ in 0..<2 {
            do { _ = try await authorizer.authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
            catch { XCTAssertEqual(error as? WalkingTargetReadFailure, .missingEvidence(["publicVisibility", "coordinateDatum", "countryRegion", "authorityRevision", "navigationIssuedAt", "navigationExpiresAt"])) }
        }
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/city/nodes/7", "/api/city/nodes/7"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testHistoricalRemovedAndUnknownStatusCannotAuthorize() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        let context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { context })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner, current: { owner })
        for status in ["0", "2", "null"] {
            transport.body = "{\"code\":200,\"data\":{\"poiId\":7,\"name\":\"Stop\",\"lat\":1,\"lng\":1,\"status\":\(status)}}"
            do { _ = try await authorizer.authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
            catch { XCTAssertEqual(error as? WalkingNavigationFailure, .targetUnavailable) }
        }
    }
    func testAccountRealmChangeDuringReadCannotPublish() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        var current: RuntimeDependencyContext? = owner
        let context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { context })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner, current: { current })
        transport.onRead = { current = nil }
        do { _ = try await authorizer.authorize(.init(kind: .cityNode, id: 7)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .staleContext) }
        XCTAssertEqual(transport.requests.count, 1)
        do { _ = try await authorizer.authorize(.init(kind: .cityNode, id: 7)); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testNearbyUsesRegistrationIdentityAndNeverCityDetail() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        transport.body = #"{"code":200,"data":[{"id":7,"nodeId":91,"topicId":22,"addressName":"Stop","latitude":"1","longitude":"1"}]}"#
        let context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic")
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { context })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner,
            nearbyArea: .init(coordinate: .init(latitude: 1, longitude: 1)!, label: "Synthetic"), current: { owner })
        do { _ = try await authorizer.authorize(.init(kind: .nearbyNode, id: 7)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingTargetReadFailure, .missingEvidence(["playerNavigationVisibility", "locked", "coordinateDatum", "countryRegion", "authorityRevision", "navigationExpiresAt"])) }
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/map/nearby")
        XCTAssertEqual(transport.requests.first?.httpMethod, "POST")
        do { _ = try await authorizer.authorize(.init(kind: .nearbyNode, id: 91)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .targetUnavailable) }
        XCTAssertFalse(transport.requests.contains { $0.url?.path.contains("city/nodes") == true })
    }
    func testStoryIdentityNeverFallsThroughToCityEndpoint() async throws {
        let owner = try owner(), transport = WalkingReadRecorder()
        let reader = SearchMapSessionReader(service: .init(configuration: try .init(baseURL: owner.baseURL), transport: transport), currentContext: { .init(guestEpoch: 1) })
        let authorizer = SourceWalkingTargetAuthorizer(reader: reader, owner: owner, current: { owner })
        do { _ = try await authorizer.authorize(.init(kind: .storyNode, id: 7, missionID: 2)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingTargetReadFailure, .unsupportedKind) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testPreviewRevalidatesRejectsMismatchAndCancelThenReopen() async throws {
        let reference = try WalkingTargetReference(kind: .cityNode, id: 7)
        let targets = try PreviewTargets(reference), provider = PreviewRecorder()
        func make() -> AuthorizedWalkingPreviewPlanner {
            .init(reference: reference, targets: targets, planner: provider, current: { true })
        }
        let request = SearchRouteRequest(origin: .init(latitude: 1, longitude: 1)!, destination: targets.value.coordinate.point, mode: .walking, datum: .wgs84, region: "US")
        let first = make()
        _ = try await first.preview(request)
        first.cancel()
        do { _ = try await first.preview(request); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await make().preview(request)
        XCTAssertEqual(targets.calls, 2); XCTAssertEqual(provider.calls, 2)
        let mismatch = SearchRouteRequest(origin: request.origin, destination: request.origin, mode: .walking, datum: .wgs84, region: "US")
        do { _ = try await make().preview(mismatch); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .coordinateUnsupported) }
        XCTAssertEqual(provider.calls, 2)
        targets.locked = true
        do { _ = try await make().preview(request); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .targetUnavailable) }
        XCTAssertEqual(provider.calls, 2)
        targets.locked = false; provider.noRoute = true
        do { _ = try await make().preview(request); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .noRoute) }
    }
}
@MainActor private final class WalkingReadRecorder: HTTPTransport {
    var requests: [URLRequest] = []
    var body = #"{"code":200,"data":{"poiId":7,"name":"Stop","lat":1,"lng":1,"status":1}}"#
    var onRead: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onRead?(); return (Data(body.utf8), 200)
    }
}
@MainActor private final class PreviewTargets: WalkingTargetAuthorizing {
    let value: AuthorizedWalkingTarget
    var calls = 0, locked = false, suspend = false
    var pending: CheckedContinuation<AuthorizedWalkingTarget, Error>?
    init(_ reference: WalkingTargetReference) throws {
        value = try .init(reference: reference, title: "Synthetic", coordinate: .init(point: .init(latitude: 1.001, longitude: 1.001)!, datum: .wgs84, region: "US"), authorityRevision: "fixture", expiresAt: Date().addingTimeInterval(120))
    }
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        calls += 1
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        if locked { throw WalkingNavigationFailure.targetUnavailable }; return value
    }
}
@MainActor private final class PreviewRecorder: SearchRoutePlanning {
    var calls = 0, cancels = 0, noRoute = false, suspend = false
    var pending: CheckedContinuation<SearchRoutePreview, Error>?
    func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview {
        calls += 1
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return try route(request)
    }
    func cancel() { cancels += 1 }
    func route(_ request: SearchRouteRequest) throws -> SearchRoutePreview {
        if noRoute { return .straightLine(request) }
        return try .init(coordinates: [request.origin, request.destination], distanceMeters: 200, etaSeconds: 120,
                         steps: [.init(instruction: "Synthetic walk", distanceMeters: 200)], isStraightLine: false, datum: .wgs84,
                         provider: .init(identifier: "fixture", attribution: "Synthetic", fetchedAt: Date()))
    }
}
