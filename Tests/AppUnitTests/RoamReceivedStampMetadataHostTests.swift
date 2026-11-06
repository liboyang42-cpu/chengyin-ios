import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Synthetic original host + independent composition route. Never fetches an image or sends an exchange.
@MainActor final class RoamReceivedStampMetadataHostTests: XCTestCase {
    private let base = URL(string: "https://received-host.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil) throws -> AppCompositionRoot {
        let suite = "received-metadata-" + UUID().uuidString, vault = Vault()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.received.metadata", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, roamReceivedStampReadAccess: { grants?.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    private func scope(_ reader: RoamReceivedStampReader) throws -> RoamStampAlbumReadOnlyScope {
        .init(reader: reader, identity: try XCTUnwrap(reader.identity), isCurrent: { true })
    }
    func testRealSessionDefaultNilDoesNotBorrowAlbumOrImageAuthority() async throws {
        let wire = Wire(), session = try root(wire).makeSession(); await login(session); wire.requests = []
        let reader = session.roamReceivedStampReader
        XCTAssertNotNil(reader.identity); XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.album(page: 1, pageSize: 20); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
        let album = RoamStampAlbumView(reader: reader)
        XCTAssertFalse(album.allowsCapture); XCTAssertFalse(album.allowsRemoteImages)
        XCTAssertFalse(try scope(reader).allowsRemoteImages)
    }
    func testOriginalCompositionSendsOnlyIndependentReceivedMultipartRead() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let page = try await session.roamReceivedStampReader.album(page: 1, pageSize: 20)
        XCTAssertEqual(page.list.first?.kind, 1); XCTAssertEqual(page.total, 21)
        let request = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.url?.path, "/native/api/roam/stamp/received"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(RoamReceivedStampReadRoute(request: request, baseURL: base))
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testClonedTransportKeepsOnlyExactReadAndNoExchangeCreateOrAlbumAuthority() async throws {
        let wire = Wire(), transport = try root(wire, Grants()).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-received", viewerRevision: 1) }
        let clone = transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(RoamReceivedStampReadRoute.path),
            fields: ["pageNum": "1", "pageSize": "20"], token: "synthetic-received")
        _ = try await clone.send(request)
        for suffix in ["list", "exchange", "create", "received/", "received?pageNum=1", "received#other"] {
            var r = request; r.url = URL(string: base.absoluteString + "/api/roam/stamp/" + suffix)
            do { _ = try await clone.send(r); XCTFail(suffix) } catch {}
        }
        var r = request; r.httpMethod = "GET"
        do { _ = try await clone.send(r); XCTFail() } catch {}
        r = try AuthRequestBuilder.makeFormRequest(url: request.url!, fields: ["pageNum": "1", "pageSize": "20", "memberId": "81"], token: "synthetic-received")
        do { _ = try await clone.send(r); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testAlbumGrantCannotEnableReceivedRoute() async throws {
        let wire = Wire(), transport = try root(wire).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-received", viewerRevision: 1) }
        transport.roamAlbumMetadataReadAccess = { c in
            try? .init(context: c, approval: .init(baseURL: c.baseURL, namespace: c.session.namespace,
                accountID: c.session.accountID, paths: [RoamAlbumMetadataReadRoute.path]))
        }
        let r = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(RoamReceivedStampReadRoute.path),
            fields: ["pageNum": "1", "pageSize": "20"], token: "synthetic-received")
        do { _ = try await transport.send(r); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testSameAccountReplacementRetiresExistingAlbumOwnerAndScope() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
        let reader = session.roamReceivedStampReader, old = RoamAlbumReadOwner(reader: reader, scope: nil)
        let frozen = try scope(reader); XCTAssertTrue(frozen.isCurrent)
        grants.retained = nil; XCTAssertTrue(reader.isConfigured)
        XCTAssertNotEqual(old, RoamAlbumReadOwner(reader: reader, scope: nil)); XCTAssertFalse(frozen.isCurrent)
        do { _ = try await frozen.album(page: 1, pageSize: 20); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testLateOldOwner401CannotExpireNewAccount() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
        wire.hold = true; let task = Task { try await session.roamReceivedStampReader.album(page: 1, pageSize: 20) }
        try await eventually { wire.pending != nil }; _ = try XCTUnwrap(wire.pending)
        await session.logout(); wire.hold = false; wire.account = 82; grants.retained = nil; await login(session)
        wire.finish(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.account?.id, 82)
        wire.status = 401
        do { _ = try await session.roamReceivedStampReader.album(page: 1, pageSize: 20); XCTFail() } catch {}
        XCTAssertNil(session.account)
    }
    func testOriginalAlbumEntryOpensReceivedListThenAnonymousDetailWithoutAnotherRequest() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let local = Local(identity: session.roamReceivedStampReader.identity)
        let host = UIHostingController(rootView: NavigationStack { RoamStampAlbumView(reader: local) }
            .environment(\.roamReceivedStampReader, session.roamReceivedStampReader).environment(\.scenePhase, .active))
        let scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible(); host.loadViewIfNeeded()
        try await eventually { self.find("roam.receivedMetadata.open", in: scene.window) != nil }
        XCTAssertTrue(wire.requests.isEmpty)
        try await tap("roam.receivedMetadata.open", in: scene.window)
        try await eventually { self.find("roam.receivedMetadata.record", in: scene.window) != nil }
        XCTAssertEqual(wire.requests.count, 1)
        try await tap("roam.receivedMetadata.record", in: scene.window)
        try await eventually { self.find("roam.receivedMetadata.anonymous", in: scene.window) != nil }
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertTrue(wire.requests.allSatisfy { $0.url?.lastPathComponent == "received" })
    }
    func testDefaultNilHostedEntryStaysVisibleButCannotRead() async throws {
        let wire = Wire(), session = try root(wire).makeSession(); await login(session); wire.requests = []
        let host = UIHostingController(rootView: NavigationStack { RoamStampAlbumView(reader: Local(identity: session.roamReceivedStampReader.identity)) }
            .environment(\.roamReceivedStampReader, session.roamReceivedStampReader).environment(\.scenePhase, .active))
        let scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible(); host.loadViewIfNeeded()
        try await eventually { self.find("roam.receivedMetadata.open", in: scene.window) != nil }
        XCTAssertFalse(session.roamReceivedStampReader.isConfigured); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testBackgroundHidesRowsAndRequiresExplicitFreshScopeOnForeground() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let phase = ReceivedMetadataTestPhase()
        let host = UIHostingController(rootView: ReceivedMetadataTestPhaseHost(reader: session.roamReceivedStampReader, phase: phase))
        let scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible(); host.loadViewIfNeeded()
        try await eventually { self.find("roam.receivedMetadata.record", in: scene.window) != nil }
        let before = wire.requests.count; phase.value = .background
        try await eventually { self.find("roam.receivedMetadata.record", in: scene.window) == nil }
        phase.value = .active
        try await eventually { self.find("roam.receivedMetadata.reopen", in: scene.window) != nil }
        XCTAssertEqual(wire.requests.count, before)
        try await tap("roam.receivedMetadata.reopen", in: scene.window)
        try await eventually { wire.requests.count == before + 1 }
    }
    func testCoveredListKeepsMetadataScopeAndBackReadsOnlyFirstPage() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let reader = session.roamReceivedStampReader, frozen = try scope(reader)
        let page = RoamAlbumReadPresentation(reader: reader, scope: frozen)
        page.appear(foreground: true); try await eventually { !page.loading && page.pager.loaded }
        let oldMore = page.readAction(), oldRefresh = page.refreshAction(), rows = page.pager.stamps
        page.disappear(); oldMore(); await oldRefresh()
        XCTAssertTrue(frozen.isCurrent); XCTAssertEqual(page.pager.stamps, rows); XCTAssertEqual(wire.requests.count, 1)
        page.appear(foreground: true); oldMore(); await oldRefresh()
        try await eventually { !page.loading && wire.requests.count == 2 }
        XCTAssertEqual(wire.pages, [1, 1]); XCTAssertTrue(frozen.isCurrent)
    }
    func testLogicalOwnerReleaseAndExplicitRetirementAreOneWay() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session)
        let reader = session.roamReceivedStampReader, frozen = try scope(reader)
        var owner: RoamAlbumPageOwner? = RoamAlbumPageOwner(); frozen.bind(to: owner!)
        XCTAssertTrue(frozen.isCurrent); owner = nil; XCTAssertFalse(frozen.isCurrent)
        frozen.bind(to: RoamAlbumPageOwner()); XCTAssertFalse(frozen.isCurrent)
        let second = try scope(reader); second.retire(); XCTAssertFalse(second.isCurrent)
        let page = RoamAlbumReadPresentation(reader: reader, scope: second); wire.requests = []
        page.appear(foreground: true); page.setForeground(false); page.setForeground(true)
        for _ in 0..<10 { await Task.yield() }; XCTAssertTrue(wire.requests.isEmpty)
    }
    func testReceived403ClearsMetadataAndExplicitRefreshStartsPageOne() async throws {
        let wire = Wire(), session = try root(wire, Grants()).makeSession(); await login(session); wire.requests = []
        let reader = session.roamReceivedStampReader, page = RoamAlbumReadPresentation(reader: reader, scope: try scope(reader))
        page.appear(foreground: true); try await eventually { !page.loading && page.pager.loaded }
        wire.status = 403; page.readAction()(); try await eventually { !page.loading && page.pager.error != nil }
        XCTAssertTrue(page.pager.stamps.isEmpty); XCTAssertFalse(page.pager.hasMore); XCTAssertNotNil(session.account)
        wire.status = 200; await page.refreshAction()()
        XCTAssertEqual(wire.pages, [1, 2, 1]); XCTAssertNil(page.pager.error)
    }
    func testUnknownKindHasNoInventedLabel() {
        XCTAssertEqual(RoamReceivedStampKind.key(0), "freePhoto")
        XCTAssertEqual(RoamReceivedStampKind.key(1), "cancelledStamp")
        XCTAssertNil(RoamReceivedStampKind.key(nil)); XCTAssertNil(RoamReceivedStampKind.key(9))
    }
    private func eventually(_ condition:()->Bool)async throws {
        for _ in 0..<100 {if condition(){return};try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(condition())
    }
    private func tap(_ id:String,in window:UIWindow)async throws {
        try await eventually {self.find(id,in:window) != nil}
        let target=try XCTUnwrap(find(id,in:window))
        if let control=target as? UIControl {control.sendActions(for:.touchUpInside)}else{XCTAssertTrue(target.accessibilityActivate())}
    }
    private func find(_ id:String,in window:UIWindow)->NSObject? {
        var seen=Set<ObjectIdentifier>()
        func visit(_ node:NSObject)->NSObject? {
            guard seen.insert(ObjectIdentifier(node)).inserted else{return nil}
            if (node as? UIAccessibilityIdentification)?.accessibilityIdentifier == id{return node}
            if let elements=node.accessibilityElements {for case let child as NSObject in elements {if let found=visit(child){return found}}}
            if let view=node as? UIView {for child in view.subviews {if let found=visit(child){return found}}}
            let count=node.accessibilityElementCount()
            if count > 0 && count < 1000 {for index in 0..<count {if let child=node.accessibilityElement(at:index) as? NSObject,let found=visit(child){return found}}}
            return nil
        }
        return visit(window)
    }
    @MainActor private final class Grants {
        var retained: RoamReceivedStampReadAccess?
        func select(_ c: RuntimeDependencyContext) -> RoamReceivedStampReadAccess? {
            if retained == nil { retained = try? .init(context: c, approval: .init(baseURL: c.baseURL,
                namespace: c.session.namespace, accountID: c.session.accountID, paths: [RoamReceivedStampReadRoute.path])) }
            return retained
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], pages: [Int] = [], account = 81, status = 200, hold = false
        var pending: CheckedContinuation<(Data, Int), Error>?
        private var held = Data()
        func finish(status: Int) { let p = pending; pending = nil; p?.resume(returning: (held, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.lastPathComponent
            if path == "phone" { return (try JSONSerialization.data(withJSONObject: ["code": 200, "token": "synthetic-received", "data": ["id": account, "role": "player"]]), 200) }
            if path == "userInfo" { return (try JSONSerialization.data(withJSONObject: ["code": 200, "appUser": ["userId": account, "role": "player"]]), 200) }
            let route = try XCTUnwrap(RoamReceivedStampReadRoute(request: request, baseURL: URL(string: "https://received-host.example/native")!))
            pages.append(route.page)
            let row: [String: Any] = ["id": route.page, "kind": 1, "caption": "Received metadata", "checkState": 1,
                "picUrl": "https://unapproved.invalid/never-fetch.jpg", "createTime": "2026-11-01T10:00:00"]
            let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["list": [row], "total": 21, "pageNum": route.page, "pageSize": route.pageSize]])
            if hold { held = bytes; return try await withCheckedThrowingContinuation { pending = $0 } }
            return (bytes, status)
        }
    }
    @MainActor private final class Local: RoamExperienceReading {
        var identity: RoamExperienceIdentity?, isConfigured = false, isOfflineExample = false
        init(identity: RoamExperienceIdentity?) { self.identity = identity }
        func history() throws -> [RoamHistoryRecord] { [] }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
    }
}
@MainActor private final class ReceivedMetadataTestPhase: ObservableObject { @Published var value: ScenePhase = .active }
@MainActor private struct ReceivedMetadataTestPhaseHost: View {
    let reader: RoamReceivedStampReader
    @ObservedObject var phase: ReceivedMetadataTestPhase
    var body: some View { NavigationStack { RoamReceivedStampMetadataDestination(reader: reader) }.environment(\.scenePhase, phase.value) }
}
