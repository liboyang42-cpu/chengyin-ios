import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// The real place detail and original reader/service, with only an in-memory HTTP transport.
/// No map rendering, permission request, remote image, camera, system share or business writer.
@MainActor final class RoamPlaceDetailReadLifetimeTests: XCTestCase {
    func testInitialBackgroundDoesNotReadUntilVisibleForeground() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.phase = .background; mount(r, window: scene.window)
        try await open(r, window: scene.window); try await settle()
        XCTAssertTrue(r.wire.requests.isEmpty)
        r.phase = .active
        try await eventually { r.wire.merchantCount == 1 && self.find("roamFeaturedActivity.open", in: scene.window) != nil }
        XCTAssertEqual(r.wire.nodeCount, 1)
    }
    func testBackgroundCancelsHeldNodeAndDoesNotDispatchSupplementaryMerchant() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.holdNext = .node; mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { r.wire.pending != nil }
        r.phase = .background; try await eventually { r.wire.cancellations == 1 }
        r.wire.finish(); try await settle()
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 0)
        XCTAssertNil(find("roamSub.w208.poi.node", in: scene.window))
        r.phase = .active
        try await eventually { r.wire.nodeCount == 2 && r.wire.merchantCount == 1 && self.find("roamFeaturedActivity.open", in: scene.window) != nil }
    }
    func testBackgroundCancelsHeldMerchantAndForegroundUsesOriginalReadChain() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.holdNext = .merchant; mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { r.wire.pending != nil }
        r.phase = .inactive; try await eventually { r.wire.cancellations == 1 }
        r.wire.finish(); try await settle()
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 1)
        XCTAssertNil(find("roamFeaturedActivity.open", in: scene.window))
        r.phase = .active
        try await eventually { r.wire.nodeCount == 2 && r.wire.merchantCount == 2 && self.find("roamFeaturedActivity.open", in: scene.window) != nil }
    }
    func testManualMerchantRetryStillReadsOnlyMerchantAndRetainedButtonCannotActInBackground() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.merchantStatus = 503; mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { self.find("roam.merchant.retry", in: scene.window) != nil }
        let oldButton = try XCTUnwrap(find("roam.merchant.retry", in: scene.window))
        r.phase = .background; try await settle(); activate(oldButton); try await settle()
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 1)
        r.phase = .active
        try await eventually { r.wire.merchantCount == 2 && self.find("roam.merchant.retry", in: scene.window) != nil }
        activate(oldButton); try await settle()
        XCTAssertEqual(r.wire.merchantCount, 2, "Old visit cannot retry after foreground ABA")
        r.wire.merchantStatus = 200; try await tap("roam.merchant.retry", in: scene.window)
        try await eventually { self.find("roamFeaturedActivity.open", in: scene.window) != nil }
        XCTAssertEqual(r.wire.nodeCount, 2); XCTAssertEqual(r.wire.merchantCount, 3)
    }
    func testHeldExplicitMerchantRetryCannotPaintAfterBackground() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.merchantStatus = 503; mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { self.find("roam.merchant.retry", in: scene.window) != nil }
        r.wire.merchantStatus = 200; r.wire.holdNext = .merchant
        try await tap("roam.merchant.retry", in: scene.window); try await eventually { r.wire.pending != nil }
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 2)
        r.phase = .background; try await eventually { r.wire.cancellations == 1 }
        r.wire.finish(); try await settle()
        XCTAssertNil(find("roamFeaturedActivity.open", in: scene.window)); XCTAssertEqual(r.wire.requests.count, 3)
        r.phase = .active
        try await eventually { r.wire.nodeCount == 2 && r.wire.merchantCount == 3 && self.find("roamFeaturedActivity.open", in: scene.window) != nil }
    }
    func testAcceptedFeaturedChildSurvivesCoverAndForegroundWithoutHiddenParentRead() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await open(r, window: scene.window)
        try await tap("roamFeaturedActivity.open", in: scene.window)
        try await eventually { self.find("place.read.child", in: scene.window) != nil }
        XCTAssertEqual(Set(r.destinations), [.activity(33)])
        let count = r.wire.requests.count
        r.phase = .background; try await settle(); r.phase = .active; try await settle()
        XCTAssertNotNil(find("place.read.child", in: scene.window)); XCTAssertEqual(r.wire.requests.count, count)
        let nav = try XCTUnwrap(navigationController(scene.window.rootViewController))
        XCTAssertNotNil(nav.popViewController(animated: false))
        try await eventually { r.wire.nodeCount == 2 && r.wire.merchantCount == 2 && self.find("roamFeaturedActivity.open", in: scene.window) != nil }
        XCTAssertEqual(Set(r.destinations), [.activity(33)], "Only the original activity ID can remain a destination")
    }
    func testTrueSheetCloseCancelsReadAndLaterForegroundDoesNotReopenIt() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.holdNext = .node; mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { r.wire.pending != nil }
        r.presented = false; try await eventually { r.wire.cancellations == 1 }
        r.wire.finish(); r.phase = .background; try await settle(); r.phase = .active; try await settle()
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 0)
        XCTAssertNil(find("roam.detail", in: scene.window))
    }
    func testOwnerChangeInBackgroundNeverReadsNewAccountIntoOldDetail() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { self.find("roamFeaturedActivity.open", in: scene.window) != nil }
        r.phase = .background; try await settle()
        r.session = try .init(accountID: 8, epoch: 2, token: "replacement-synthetic")
        r.phase = .active; try await settle()
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 1)
        XCTAssertNil(find("roamFeaturedActivity.open", in: scene.window)); XCTAssertNotNil(find("roam.error", in: scene.window))
    }
    func testOriginalNode410StaysUnavailableWithoutSupplementaryRead() async throws {
        let r = try PlaceReadLifetimeRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.nodeStatus = 410; mount(r, window: scene.window); try await open(r, window: scene.window)
        try await eventually { self.find("roamSub.w208.poi.unavailable", in: scene.window) != nil }
        XCTAssertEqual(r.wire.nodeCount, 1); XCTAssertEqual(r.wire.merchantCount, 0)
        XCTAssertNil(find("roam.merchant.retry", in: scene.window))
    }
    private func mount(_ rig: PlaceReadLifetimeRig, window: UIWindow) {
        let host = UIHostingController(rootView: PlaceReadLifetimeHost(rig: rig))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func open(_ rig: PlaceReadLifetimeRig, window: UIWindow) async throws {
        try await tap("place.read.open", in: window)
        try await eventually { self.find("roam.detail", in: window) != nil }
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(150)) }
    private func eventually(_ ready: () -> Bool) async throws {
        for _ in 0..<150 { if ready() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Original place detail did not settle"); throw APIError.notConfigured
    }
    private func activate(_ target: NSObject) {
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { _ = target.accessibilityActivate() }
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<100 {
            if let target = find(id, in: window) { activate(target); return }
            scroll(window); try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Missing original control: " + id); throw APIError.notConfigured
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let end = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let next = scroll.contentOffset.y < end ? min(end, scroll.contentOffset.y + 400) : -scroll.adjustedContentInset.top
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false); scroll.layoutIfNeeded()
        }
        view.subviews.forEach { scroll($0) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return nil }
            if (node as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return node }
            if let children = node.accessibilityElements { for case let child as NSObject in children { if let found = visit(child) { return found } } }
            if let view = node as? UIView { for child in view.subviews { if let found = visit(child) { return found } } }
            let count = node.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = node.accessibilityElement(at: index) as? NSObject, let found = visit(child) { return found } } }
            return nil
        }
        return visit(window)
    }
    private func navigationController(_ controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController, let found = navigationController(presented) { return found }
        if let nav = controller as? UINavigationController { return nav }
        for child in controller.children { if let found = navigationController(child) { return found } }
        return nil
    }
}
@MainActor private struct PlaceReadLifetimeHost: View {
    @ObservedObject var rig: PlaceReadLifetimeRig
    var body: some View {
        Button("Open selected place") { rig.presented = true }.accessibilityIdentifier("place.read.open")
            .sheet(isPresented: $rig.presented) {
                RoamItemDetailView(item: .place(rig.place), reader: rig.reader, eventDestination: { destination in
                    rig.destinations.append(destination)
                    return AnyView(Text("Synthetic activity").accessibilityIdentifier("place.read.child"))
                })
            }
            .environment(\.scenePhase, rig.phase)
    }
}
@MainActor private final class PlaceReadLifetimeRig: ObservableObject {
    let wire = PlaceReadLifetimeWire()
    let place: RoamPlace
    let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 30, longitude: 120)!, label: "Synthetic manual area")
    @Published var phase: ScenePhase = .active
    @Published var presented = false
    @Published var session: RoamReadSession?
    var destinations: [RoamEventDestination] = []
    lazy var reader = RoamSessionReader(service: try! .init(configuration: .init(baseURL: URL(string: "https://example.test/place-read")!), transport: wire),
        currentSession: { [weak self] in self?.session }, searchArea: { [weak self] in self?.area })
    init() throws {
        place = try JSONDecoder().decode(RoamPlace.self, from: Data(#"{"id":11,"type":2,"name":"Synthetic place"}"#.utf8))
        session = try .init(accountID: 7, epoch: 1, token: "synthetic-place-read")
    }
}
@MainActor private final class PlaceReadLifetimeWire: HTTPTransport {
    enum Kind: Equatable { case node, merchant }
    var requests: [URLRequest] = []
    var nodeCount: Int { requests.filter { $0.url?.lastPathComponent == "11" }.count }
    var merchantCount: Int { requests.filter { $0.url?.lastPathComponent == "public-detail" }.count }
    var nodeStatus = 200, merchantStatus = 200
    var holdNext: Kind?
    var pending: CheckedContinuation<(Data, Int), Error>?
    var cancellations = 0
    private var held: (Data, Int)?
    func finish() { let continuation = pending; pending = nil; if let held { self.held = nil; continuation?.resume(returning: held) } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-place-read")
        let kind: Kind, status: Int, bytes: Data
        switch request.url?.path {
        case "/place-read/api/city/nodes/11":
            kind = .node; status = nodeStatus
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertNil(request.url?.query)
            bytes = Data(#"{"code":\#(status),"data":{"poiId":11,"name":"Synthetic node","status":1,"merchantId":22,"completed":false,"favorited":false}}"#.utf8)
        case "/place-read/api/merchant/public-detail":
            kind = .merchant; status = merchantStatus
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.url?.query)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int], ["id": 22])
            bytes = Data(#"{"code":\#(status),"data":{"id":22,"name":"Synthetic merchant"},"featured":{"featuredType":1,"featuredId":33,"name":"Synthetic featured activity"}}"#.utf8)
        default: XCTFail("Unexpected request, including any map/GPS/business writer"); throw APIError.notConfigured
        }
        if holdNext == kind {
            holdNext = nil; held = (bytes, status)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { pending = $0 }
            } onCancel: { Task { @MainActor [weak self] in self?.cancellations += 1 } }
        }
        return (bytes, status)
    }
}
