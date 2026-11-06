import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Real private read service with synthetic payloads. Handoff assertions inspect bytes only, never files or system sharing.
@MainActor final class RoamPrivateGrantScopeHostTests: XCTestCase {
    func testQueuedPrivateReadAndSettlementCannotUseReplacementGrant() async throws {
        let r = try PrivateGrantHostRig(), page = RoamPrivatePageOwner(tools: r.reader)
        let first = RoamPrivatePageScope(r.reader); XCTAssertTrue(page.appear(foreground: true))
        var reads = 0, writes = 0
        page.read { reads += 1 }; page.settle(write: false, { writes += 1 }, refresh: {})
        try r.replaceGrant()
        XCTAssertNotEqual(first, RoamPrivatePageScope(r.reader)); XCTAssertFalse(page.isPresented)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(reads, 0); XCTAssertEqual(writes, 0); XCTAssertTrue(r.wire.requests.isEmpty)
        XCTAssertFalse(page.activate(foreground: true))
        let fresh = RoamPrivatePageOwner(tools: r.reader); XCTAssertTrue(fresh.appear(foreground: true))
        fresh.read { reads += 1 }; try await eventually { reads == 1 }
    }
    func testGrantRevocationInvalidatesExistingPrivateOwnerWithoutChangingIdentity() throws {
        let r = try PrivateGrantHostRig(), page = RoamPrivatePageOwner(tools: r.reader)
        let identity = r.reader.identity; XCTAssertTrue(page.appear(foreground: true)); r.access?.revoke()
        XCTAssertEqual(identity, r.reader.identity); XCTAssertFalse(page.acceptsInput)
        try r.replaceGrant(); XCTAssertFalse(page.isPresented); XCTAssertFalse(page.activate(foreground: true))
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testIssuedSettlementStillFinishesWithoutPublishingIntoReplacementPage() async throws {
        let r = try PrivateGrantHostRig(), page = RoamPrivatePageOwner(tools: r.reader)
        _ = page.appear(foreground: true)
        var gate: CheckedContinuation<Void, Never>?, cancelled = false, completed = 0, refreshed = 0
        page.settle(write: false, { await withCheckedContinuation { gate = $0 }; cancelled = Task.isCancelled },
            refresh: { refreshed += 1 }, finished: { _ in completed += 1 })
        try await eventually { gate != nil }; try r.replaceGrant(); page.retire(leaving: true)
        XCTAssertTrue(page.settlementInFlight); gate?.resume(); gate = nil
        try await eventually { !page.settlementInFlight }
        XCTAssertFalse(cancelled); XCTAssertEqual(completed, 0); XCTAssertEqual(refreshed, 0)
    }
    func testExportQueuedPrepareCannotRunOrResumeUnderReplacementScope() async throws {
        let r = try PrivateGrantHostRig(), owner = RoamExportReadPresentation(tools: r.reader)
        owner.appear(foreground: true); let range = owner.model.presets[0]
        owner.prepare(startDate: range.startDate, endDate: range.endDateExclusive); try r.replaceGrant()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(owner.active); XCTAssertTrue(r.wire.requests.isEmpty)
        owner.resume(foreground: true); XCTAssertFalse(owner.active)
        let fresh = RoamExportReadPresentation(tools: r.reader); fresh.appear(foreground: true)
        XCTAssertTrue(fresh.active); XCTAssertTrue(r.wire.requests.isEmpty)
        fresh.prepare(startDate: range.startDate, endDate: range.endDateExclusive)
        try await eventually { fresh.model.phase == .prepared }
        XCTAssertEqual(r.wire.requests.count, 1)
    }
    func testCompletedExportLastMomentGateRejectsSameIdentityNewGrant() async throws {
        let r = try PrivateGrantHostRig(), owner = RoamExportReadPresentation(tools: r.reader)
        owner.appear(foreground: true); try await complete(owner)
        let file = try XCTUnwrap(owner.model.file), lease = try XCTUnwrap(owner.model.deliveryLease)
        owner.deliveryContext.bind(clock: { r.reader.now }, identity: { [weak owner] in owner?.deliveryIdentity }, foreground: { true })
        XCTAssertNotNil(RoamExportHandoff.contents(file: file, lease: lease, context: owner.deliveryContext))
        let identity = r.reader.identity; try r.replaceGrant()
        XCTAssertEqual(identity, r.reader.identity); XCTAssertFalse(owner.active); XCTAssertNil(owner.deliveryIdentity)
        XCTAssertNil(RoamExportHandoff.contents(file: file, lease: lease, context: owner.deliveryContext))
        owner.deliveryContext.publish(); owner.resume(foreground: true)
        XCTAssertTrue(lease.isRevoked); XCTAssertFalse(owner.active)
        owner.model.renewDelivery(); XCTAssertNil(owner.model.shareableFile)
        XCTAssertEqual(r.wire.requests.count, 2)
    }
    func testIssuedExportChunkCannotMintFileAfterApprovalChanges() async throws {
        let r = try PrivateGrantHostRig(), owner = RoamExportReadPresentation(tools: r.reader)
        owner.appear(foreground: true); let range = owner.model.presets[0]
        await owner.model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        r.wire.holdPage = true; owner.readNext(); try await eventually { r.wire.pending != nil }
        try r.replaceGrant(); r.wire.finish()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(owner.model.file); XCTAssertNil(owner.model.deliveryLease); XCTAssertFalse(owner.active)
        owner.resume(foreground: true); owner.readNext()
        for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(r.wire.requests.count, 2)
    }
    func testOriginalCapsuleEntryDropsOpenedBodyOnSameAccountGrantChange() async throws {
        let r = try PrivateGrantHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        let host = UIHostingController(rootView: PrivateGrantHostHarness(rig: r, export: false))
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible(); host.loadViewIfNeeded()
        try await tap("roam.capsule.open", in: scene.window)
        try await tap("roam.capsule.row.open", in: scene.window)
        try await eventually { self.find("roam.capsule.body", in: scene.window) != nil }
        XCTAssertEqual(r.wire.requests.filter { $0.url?.lastPathComponent == "detail" }.count, 1)
        try r.replaceGrant()
        try await eventually { self.find("roam.capsule.body", in: scene.window) == nil && r.wire.requests.filter { $0.url?.lastPathComponent == "list" }.count == 2 }
        XCTAssertEqual(r.wire.requests.filter { $0.url?.lastPathComponent == "detail" }.count, 1)
        XCTAssertTrue(r.wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testHostedExportReplacementDropsOldFileAndRequiresExplicitNewPreparation() async throws {
        let r = try PrivateGrantHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        let host = UIHostingController(rootView: PrivateGrantHostHarness(rig: r, export: true))
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible(); host.loadViewIfNeeded()
        try await tap("roam.export.prepare", in: scene.window); try await tap("roam.export.readNext", in: scene.window)
        try await eventually { self.find("roam.export.file", in: scene.window) != nil }
        let count = r.wire.requests.count; try r.replaceGrant()
        try await eventually { self.find("roam.export.file", in: scene.window) == nil && self.find("roam.export.prepare", in: scene.window) != nil }
        XCTAssertEqual(r.wire.requests.count, count)
        try await tap("roam.export.prepare", in: scene.window)
        try await eventually { r.wire.requests.count == count + 1 }
    }
    func testNonSessionConformerKeepsOriginalIdentityAndDisabledPresentationContract() {
        let fixture = RoamPrivateToolsFixture()
        XCTAssertNil(RoamPrivatePageScope(fixture).readScope)
        let owner = RoamExportReadPresentation(tools: fixture); owner.appear(foreground: true)
        XCTAssertTrue(owner.active); owner.suspend(); owner.resume(foreground: true); XCTAssertTrue(owner.active)
    }
    func testWeakDeliveryOwnerNeverKeepsDepartedExportAlive() throws {
        let r = try PrivateGrantHostRig()
        var owner: RoamExportReadPresentation? = .init(tools: r.reader)
        let context = try XCTUnwrap(owner?.deliveryContext)
        weak var weakOwner = owner
        context.bind(clock: { r.reader.now }, identity: { [weak weakOwner] in weakOwner?.deliveryIdentity }, foreground: { true })
        owner = nil
        XCTAssertNil(weakOwner); XCTAssertNil(context.snapshot().identity)
    }
    private func complete(_ owner: RoamExportReadPresentation) async throws {
        let range = owner.model.presets[0]
        await owner.model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        XCTAssertEqual(owner.model.phase, .prepared); await owner.model.readNext(); XCTAssertEqual(owner.model.phase, .complete)
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
}
@MainActor private struct PrivateGrantHostHarness: View {
    @ObservedObject var rig: PrivateGrantHostRig
    let export: Bool
    var body: some View {
        NavigationStack {
            if export { RoamExplorationExportView(tools: rig.reader) }
            else { List { RoamPassportPrivateLinks(tools: rig.reader) } }
        }.environment(\.scenePhase, .active)
    }
}
@MainActor private final class PrivateGrantHostRig: ObservableObject {
    static let base = URL(string: "https://private-grant.example/native")!
    let wire = PrivateGrantHostWire()
    let context: RuntimeDependencyContext
    @Published var access: RoamPrivateToolsAccess?
    lazy var reader = RoamPrivateToolsSessionReader(service: try! .init(configuration: .init(baseURL: Self.base), transport: wire),
        current: { [weak self] in self?.context }, access: { [weak self] _ in self?.access }, journal: nil)
    init() throws {
        context = .init(market: .china, baseURL: Self.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "private-grant", token: "synthetic-private"))
        try replaceGrant()
    }
    func replaceGrant() throws {
        access = try .init(context: context, approval: .init(baseURL: Self.base, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: RoamPrivateToolsRoute.reads))
    }
}
@MainActor private final class PrivateGrantHostWire: HTTPTransport {
    var requests: [URLRequest] = [], holdPage = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    private var held = Data(), snapshot: [String: Any] = [:]
    private let cursor = "c" + String(repeating: "0", count: 47)
    func finish() { let p = pending; pending = nil; p?.resume(returning: (held, 200)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let path = request.url!.path
        let capsule: [String: Any] = ["id": "40", "state": "OPEN", "body": "Synthetic private capsule"]
        var data: [String: Any]
        switch path {
        case "/native/api/capsules/list": data = ["items": [["id": "40", "state": "OPEN"]], "hasMore": false, "nextBeforeId": NSNull()]
        case "/native/api/capsules/detail": data = capsule
        case "/native/api/exploration-goals/list": data = ["items": [], "hasMore": false, "nextBeforeId": NSNull()]
        case "/native/api/personal-exploration-export/prepare":
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            let now = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
            snapshot = ["format": "chengyin-exploration-export-v1", "timeZone": "Asia/Shanghai", "snapshotId": String(repeating: "a", count: 64),
                "startDate": body["startDate"]!, "endDateExclusive": body["endDateExclusive"]!, "pageSize": body["pageSize"]!,
                "asOfMs": now, "expiresAtMs": now + 86_400_000, "upperRecordId": "1", "expectedRows": 1]
            data = snapshot; data["cursor"] = cursor
        case "/native/api/personal-exploration-export/page":
            data = snapshot; data["cursor"] = cursor; data["offset"] = 0
            let start = try XCTUnwrap(snapshot["startDate"] as? String)
            data["items"] = [["recordId": "1", "completedAt": start + "T12:00:00.000+08:00", "routeAvailability": "UNAVAILABLE"]]
            data["complete"] = true; data["state"] = "COMPLETE"; data["nextCursor"] = NSNull(); data["emittedRows"] = 1
        default: XCTFail("Unexpected route, especially a business writer: \(path)"); throw APIError.notConfigured
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": data])
        if path.hasSuffix("/page"), holdPage { held = bytes; return try await withCheckedThrowingContinuation { pending = $0 } }
        return (bytes, 200)
    }
}
