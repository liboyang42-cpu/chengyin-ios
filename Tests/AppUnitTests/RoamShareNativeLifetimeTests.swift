import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Real SwiftUI share pages/host removal, original save model, and a memory-only writer.
/// Never calls the PhotoKit adapter or presents an activity controller.
@MainActor final class RoamShareNativeLifetimeTests: XCTestCase {
    func testPermissionInactiveCoverDoesNotInvalidateHistorySave() async throws {
        let r = try ShareLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await openAndPrepare(r, in: scene.window)
        try await tap("roam.share.savePhotos", in: scene.window)
        try await eventually { r.writer.permission != nil }
        let owner = try lifetime(in: scene.window)
        r.phase = .inactive; try await settle(); XCTAssertTrue(owner.isActive)
        r.writer.authorize(); try await eventually { r.writer.writes == 1 }
        r.writer.finish(); try await eventually { !r.model.inFlight }
        r.phase = .active; try await settle()
        XCTAssertEqual(r.model.state.phase, .saved); XCTAssertEqual(r.writer.permissionCalls, 1)
        XCTAssertEqual(r.writer.writes, 1); XCTAssertTrue(owner.isActive)
    }
    func testMedalPermissionCoverRetainsOriginalImageAndRealReceipt() async throws {
        let r = try ShareLifetimeRig(medal: true), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await openAndPrepare(r, in: scene.window)
        try await tap("roam.medalShare.savePhotos", in: scene.window); try await eventually { r.writer.permission != nil }
        let owner = try lifetime(in: scene.window); r.phase = .inactive; try await settle()
        r.writer.authorize(); try await eventually { r.writer.writes == 1 }
        let image = try XCTUnwrap(r.writer.image); r.writer.finish(); try await eventually { !r.model.inFlight }
        r.phase = .active; try await settle()
        XCTAssertTrue(owner.isActive); XCTAssertEqual(r.model.state.phase, .saved)
        XCTAssertTrue(r.writer.image === image); XCTAssertEqual(r.writer.writes, 1)
    }
    func testFullScreenCoverThenTrueAncestorDismissDuringPermissionNeverWrites() async throws {
        let r = try ShareLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await openAndPrepare(r, in: scene.window)
        try await tap("roam.share.savePhotos", in: scene.window); try await eventually { r.writer.permission != nil }
        let owner = try lifetime(in: scene.window)
        let host = try XCTUnwrap(scene.window.rootViewController?.presentedViewController)
        let cover = UIHostingController(rootView: Text("Synthetic cover")); cover.modalPresentationStyle = .fullScreen
        let covered = expectation(description: "Native full-screen cover")
        host.present(cover, animated: false) { covered.fulfill() }; await fulfillment(of: [covered], timeout: 2)
        XCTAssertTrue(owner.isActive, "Coverage alone must preserve the original save")
        r.presented = false; try await eventually { !owner.isActive }
        XCTAssertTrue(r.model.inFlight, "An unresolved permission callback still owns the original flight")
        r.writer.authorize(); try await eventually { !r.model.inFlight }
        XCTAssertEqual(r.writer.writes, 0); XCTAssertNotEqual(r.model.state.phase, .saved)
    }
    func testTrueLeaveDuringSubmittedMedalWriteKeepsLockAndRejectsLateSavedUI() async throws {
        let r = try ShareLifetimeRig(medal: true), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.writer.status = .authorized; mount(r, window: scene.window); try await openAndPrepare(r, in: scene.window)
        try await tap("roam.medalShare.savePhotos", in: scene.window); try await eventually { r.writer.write != nil }
        let owner = try lifetime(in: scene.window); r.presented = false
        try await eventually { !owner.isActive }
        XCTAssertTrue(r.model.inFlight)
        r.model.save(UIImage(), selection: .init(record: r.record, includeRoute: true), isCurrent: { true })
        XCTAssertEqual(r.writer.writes, 1, "Retirement must not clear an already submitted write lock")
        r.writer.finish(); try await eventually { !r.model.inFlight }
        XCTAssertNotEqual(r.model.state.phase, .saved); XCTAssertNil(r.model.state.selection)
    }
    func testActualAlbumGuideCoverAndBackReuseSavedReceiptWithoutAnotherWrite() async throws {
        let r = try ShareLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.writer.status = .authorized; mount(r, window: scene.window); try await openAndPrepare(r, in: scene.window)
        try await tap("roam.albumGuide.open.moments", in: scene.window); try await eventually { r.writer.write != nil }
        let owner = try lifetime(in: scene.window); r.writer.finish()
        try await eventually { self.find("roam.albumGuide.saved", in: scene.window) != nil }
        XCTAssertTrue(owner.isActive); XCTAssertEqual(r.model.state.phase, .saved)
        try await tap("roam.albumGuide.done", in: scene.window)
        try await eventually { self.find("roam.albumGuide.saved", in: scene.window) == nil }
        try await tap("roam.albumGuide.open.xiaohongshu", in: scene.window)
        try await eventually { self.find("roam.albumGuide.saved", in: scene.window) != nil }
        XCTAssertTrue(owner.isActive); XCTAssertEqual(r.writer.writes, 1)
        r.presented = false; try await eventually { !owner.isActive }
    }
    func testRecordChangeDuringPermissionStillFailsOriginalSourceCheck() async throws {
        let r = try ShareLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await openAndPrepare(r, in: scene.window)
        try await tap("roam.share.savePhotos", in: scene.window); try await eventually { r.writer.permission != nil }
        r.reader.records = []; r.writer.authorize(); try await eventually { !r.model.inFlight }
        XCTAssertEqual(r.writer.writes, 0); XCTAssertEqual(r.model.state.phase, .sourceChanged)
    }
    func testRetiredNativeLifetimeRejectsSystemRequestAtLastControllerBoundary() throws {
        let r = try ShareLifetimeRig(), owner = RoamSharePresentationLifetime(photoSave: r.model)
        owner.appear()
        let request = try XCTUnwrap(RoamHistorySystemShareRequest(image: UIImage(), selection: .init(record: r.record, includeRoute: false),
            owner: .init(reader: r.reader), reader: r.reader, presentation: owner))
        XCTAssertTrue(request.isCurrent(reader: r.reader)); owner.retire()
        XCTAssertFalse(request.isCurrent(reader: r.reader)); XCTAssertNil(request.makeActivityController(reader: r.reader))
        XCTAssertFalse(RoamMedalSystemShare(request: request, reader: r.reader).makeController() is UIActivityViewController)
        owner.appear(); XCTAssertFalse(owner.isActive, "An old page must never revive its exported request")
    }
    func testReleasedPresentationCannotAuthorizeRetainedSystemRequest() throws {
        let r = try ShareLifetimeRig()
        var owner: RoamSharePresentationLifetime? = .init(photoSave: r.model); owner?.appear()
        let request = try XCTUnwrap(RoamHistorySystemShareRequest(image: UIImage(), selection: .init(record: r.record, includeRoute: false),
            owner: .init(reader: r.reader), reader: r.reader, presentation: owner))
        weak var weakOwner = owner; owner = nil
        XCTAssertNil(weakOwner); XCTAssertFalse(request.isCurrent(reader: r.reader)); XCTAssertNil(request.makeActivityController(reader: r.reader))
    }
    func testLateDismantleOfReplacedAttachmentDoesNotRetireCurrentHost() throws {
        let r = try ShareLifetimeRig(), owner = RoamSharePresentationLifetime(photoSave: r.model)
        let old = owner.attach(); owner.appear(); let fresh = owner.attach()
        owner.dismantle(old); XCTAssertTrue(owner.isActive); XCTAssertTrue(owner.isCurrentAttachment(fresh))
        owner.dismantle(fresh); XCTAssertFalse(owner.isActive); owner.appear(); XCTAssertFalse(owner.isActive)
    }
    func testNativeCompletedPopRetiresButOrdinaryPushCoverDoesNot() async throws {
        let r = try ShareLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        let owner = RoamSharePresentationLifetime(photoSave: r.model)
        let root = UIViewController(), nav = UINavigationController(rootViewController: root)
        scene.window.rootViewController = nav; scene.window.makeKeyAndVisible()
        let host = UIHostingController(rootView: Text("Share lifetime").background(RoamShareNativeLifetime(presentation: owner)))
        nav.pushViewController(host, animated: false); try await eventually { owner.isActive }
        nav.pushViewController(UIViewController(), animated: false); try await settle()
        XCTAssertTrue(owner.isActive, "Push coverage is not a pop")
        XCTAssertNotNil(nav.popViewController(animated: false)); try await settle(); XCTAssertTrue(owner.isActive)
        XCTAssertNotNil(nav.popViewController(animated: false)); try await eventually { !owner.isActive }
    }
    private func mount(_ rig: ShareLifetimeRig, window: UIWindow) {
        let host = UIHostingController(rootView: ShareLifetimeHost(rig: rig))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func openAndPrepare(_ rig: ShareLifetimeRig, in window: UIWindow) async throws {
        try await tap("share.lifetime.open", in: window)
        try await tap(rig.medal ? "roam.medalShare.prepare" : "roam.share.prepare", in: window)
    }
    private func lifetime(in window: UIWindow) throws -> RoamSharePresentationLifetime {
        func search(_ root: UIViewController) -> RoamSharePresentationLifetime? {
            if let anchor = root as? RoamShareNativeLifetimeController { return anchor.presentation }
            if let presented = root.presentedViewController, let result = search(presented) { return result }
            for child in root.children { if let result = search(child) { return result } }
            return nil
        }
        return try XCTUnwrap(window.rootViewController.flatMap(search))
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(150)) }
    private func eventually(_ ready: () -> Bool) async throws {
        for _ in 0..<150 { if ready() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Native share lifecycle did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<120 {
            if let target = find(id, in: window) {
                if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
                else { XCTAssertTrue(target.accessibilityActivate()) }
                return
            }
            scroll(window); try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Missing original share action: " + id); throw APIError.notConfigured
    }
    private func scroll(_ view: UIView) {
        if let value = view as? UIScrollView {
            let end = max(-value.adjustedContentInset.top, value.contentSize.height - value.bounds.height + value.adjustedContentInset.bottom)
            let next = value.contentOffset.y < end ? min(end, value.contentOffset.y + 350) : -value.adjustedContentInset.top
            value.setContentOffset(CGPoint(x: value.contentOffset.x, y: next), animated: false); value.layoutIfNeeded()
        }
        for child in view.subviews { scroll(child) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let children = root.accessibilityElements { for case let child as NSObject in children { if let found = visit(child) { return found } } }
            if let view = root as? UIView { for child in view.subviews { if let found = visit(child) { return found } } }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = root.accessibilityElement(at: index) as? NSObject, let found = visit(child) { return found } } }
            return nil
        }
        return visit(window)
    }
}
@MainActor private struct ShareLifetimeHost: View {
    @ObservedObject var rig: ShareLifetimeRig
    var body: some View {
        Button("Open share") { rig.presented = true }.accessibilityIdentifier("share.lifetime.open")
            .sheet(isPresented: $rig.presented) {
                NavigationStack {
                    if rig.medal {
                        RoamMedalShareView(selection: rig.selection, reader: rig.reader, photoSaveModel: rig.model)
                    } else { RoamHistoryShareView(record: rig.record, reader: rig.reader, photoSaveModel: rig.model) }
                }
            }.environment(\.scenePhase, rig.phase)
    }
}
@MainActor private final class ShareLifetimeRig: ObservableObject {
    let medal: Bool, record: RoamHistoryRecord, selection: RoamMedalShareSelection
    let reader: ShareLifetimeReader, writer = ShareLifetimeWriter()
    lazy var model = RoamSharePhotoSaveModel(writer: writer)
    @Published var presented = false
    @Published var phase: ScenePhase = .active
    init(medal: Bool = false) throws {
        self.medal = medal
        record = try JSONDecoder().decode(RoamHistoryRecord.self, from: Data(#"{"ts":1700000000000,"distance":1.5,"shops":2,"medal":"Synthetic journey medal","shopMedalName":"Synthetic shop medal"}"#.utf8))
        selection = try XCTUnwrap(.init(record: record, kind: .journey)); reader = try .init(record: record)
    }
}
@MainActor private final class ShareLifetimeReader: RoamExperienceReading {
    var identity: RoamExperienceIdentity?
    let isConfigured = true, isOfflineExample = false
    var records: [RoamHistoryRecord]
    init(record: RoamHistoryRecord) throws {
        let scope = try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.test/share-lifetime")!, accountID: 7, namespace: "share-lifetime")
        identity = .init(scope: scope, epoch: 1); records = [record]
    }
    func history() throws -> [RoamHistoryRecord] { records }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
@MainActor private final class ShareLifetimeWriter: RoamSharePhotoWriting {
    var status: RoamSharePhotoSaveState.Authorization = .notDetermined
    var permissionCalls = 0, writes = 0
    var image: UIImage?
    var permission: CheckedContinuation<RoamSharePhotoSaveState.Authorization, Never>?
    var write: CheckedContinuation<Void, Error>?
    func authorizationStatus() -> RoamSharePhotoSaveState.Authorization { status }
    func requestAuthorization() async -> RoamSharePhotoSaveState.Authorization {
        permissionCalls += 1; return await withCheckedContinuation { permission = $0 }
    }
    func add(_ image: UIImage) async throws {
        writes += 1; self.image = image
        try await withCheckedThrowingContinuation { write = $0 }
    }
    func authorize() { let callback = permission; permission = nil; callback?.resume(returning: .authorized) }
    func finish() { let callback = write; write = nil; callback?.resume() }
}
