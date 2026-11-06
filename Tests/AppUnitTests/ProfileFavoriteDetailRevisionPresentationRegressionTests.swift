import XCTest
import SwiftUI
import UIKit
import Observation
@testable import Questify

/// Mounts the existing normal detail destination, not a replacement detail view.
/// The selector publishes its own revision changes; no rootView assignment, refresh
/// call, navigation replacement, or unrelated @State toggle forces the update.
@MainActor final class ProfileFavoriteDetailRevisionPresentationRegressionTests: XCTestCase {
    @MainActor @Observable private final class PublishedAccess {
        var selected: ProfileFavoriteDetailAccess?
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var detailNumber = 0
        var holdDetails = false
        var held: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/creativesquare/list") == true {
                return (Data(#"{"code":200,"data":{"rows":[{"id":101,"memberId":91,"contents":"Saved"}]}}"#.utf8), 200)
            }
            if request.url?.path.hasSuffix("/creativesquare/info") == true {
                detailNumber += 1
                let number = detailNumber
                if holdDetails { return try await withCheckedThrowingContinuation { held[number] = $0 } }
                return Self.detail(number)
            }
            if request.url?.path.hasSuffix("/comment/list") == true {
                let body = "{\"code\":200,\"data\":{\"rows\":[{\"id\":\(1000 + detailNumber),\"memberId\":92,\"ownerType\":3,\"ownerId\":101,\"contents\":\"PRIVATE_COMMENT_\(detailNumber)\"}]}}"
                return (Data(body.utf8), 200)
            }
            throw APIError.invalidRequest
        }
        static func detail(_ number: Int) -> (Data, Int) {
            (Data("{\"code\":200,\"data\":{\"id\":101,\"memberId\":91,\"contents\":\"PRIVATE_POST_\(number)\"}}".utf8), 200)
        }
        func finish(_ number: Int, status: Int = 200) {
            let next = held.removeValue(forKey: number)
            if status == 200 { next?.resume(returning: Self.detail(number)) }
            else { next?.resume(returning: (Data("{\"code\":\(status)}".utf8), status)) }
        }
        func abortHeld() {
            let values = Array(held.values); held.removeAll()
            for value in values { value.resume(throwing: CancellationError()) }
        }
    }
    @MainActor private struct Fixture {
        let context: RuntimeDependencyContext, access: PublishedAccess, wire: Wire
        let selection: ProfileFavoritePostSelection, reader: ProfileFavoriteDetailReader
        let lists: ProfileFavoritesReader
        func replace() throws {
            access.selected = try .init(context: context, approval: .init(baseURL: context.baseURL,
                namespace: context.session.namespace, accountID: context.session.accountID,
                paths: ProfileFavoriteDetailRoute.paths))
        }
    }
    private func fixture() async throws -> Fixture {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://favorite-projection.example/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player"))
        let wire = Wire(), access = PublishedAccess(), config = try APIConfiguration(baseURL: context.baseURL)
        let listAccess = try ProfileFavoritesReadAccess(context: context, approval: .init(baseURL: context.baseURL,
            namespace: context.session.namespace, accountID: 7, paths: ProfileFavoritesReadRoute.paths))
        let lists = ProfileFavoritesReader(service: .init(configuration: config, transport: wire), current: { context },
            viewerRevision: { 1 }, access: { _ in listAccess })
        _ = try await lists.favoritePosts(pageNumber: 1, pageSize: 10)
        let selection = try XCTUnwrap(lists.selectPost(.init(id: 101, generation: .legacySquare), renderedScope: lists.scope))
        let reader = ProfileFavoriteDetailReader(selection: selection, service: .init(configuration: config, transport: wire),
            current: { context }, viewerRevision: { 1 }, access: { _ in access.selected })
        let result = Fixture(context: context, access: access, wire: wire, selection: selection, reader: reader, lists: lists)
        try result.replace()
        return result
    }
    private func mount(_ f: Fixture) -> UIWindow {
        let host = UIHostingController(rootView: NavigationStack {
            ProfileFavoriteDetailDestination(selection: f.selection, makeReader: { f.reader }, accountReader: nil, actions: nil)
        }.environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en_US")))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        return window
    }
    private func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(description)
        throw APIError.invalidRequest
    }
    private func contains(_ text: String, in window: UIWindow) -> Bool {
        var visited = Set<ObjectIdentifier>()
        func walk(_ value: NSObject) -> Bool {
            guard visited.insert(ObjectIdentifier(value)).inserted else { return false }
            if let view = value as? UIView, view.isHidden || view.alpha <= 0.01 { return false }
            if value.accessibilityLabel?.contains(text) == true { return true }
            if let label = value as? UILabel, label.text?.contains(text) == true { return true }
            if let label = value as? UITextView, label.text?.contains(text) == true { return true }
            if let view = value as? UIView, view.subviews.contains(where: { walk($0) }) { return true }
            if let children = value.accessibilityElements,
               children.contains(where: { ($0 as? NSObject).map(walk) == true }) { return true }
            let count = value.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count {
                    if let child = value.accessibilityElement(at: index) as? NSObject, walk(child) { return true }
                }
            }
            return false
        }
        return walk(window)
    }
    func testMountedNormalDestinationRemovesOldPostAndCommentsBeforeReplacementCompletes() async throws {
        let f = try await fixture(), window = mount(f)
        defer { f.reader.retire(); f.wire.abortHeld(); window.isHidden = true; window.rootViewController = nil }
        try await waitFor("The original post and comments must actually be visible") {
            self.contains("PRIVATE_POST_1", in: window) && self.contains("PRIVATE_COMMENT_1", in: window)
        }
        let scope = f.reader.scope
        f.wire.holdDetails = true
        try f.replace() // Only the real published capability selector changes.
        try await waitFor("B must reload while A's private projection is absent") {
            f.wire.held[2] != nil && !self.contains("PRIVATE_POST_1", in: window) && !self.contains("PRIVATE_COMMENT_1", in: window)
        }
        XCTAssertNotEqual(scope, f.reader.scope); XCTAssertTrue(f.selection.isCurrent)
        XCTAssertFalse(f.reader.confirmsCurrentDetail)
        f.wire.finish(2)
        try await waitFor("The replacement read supplies both new projections") {
            self.contains("PRIVATE_POST_2", in: window) && self.contains("PRIVATE_COMMENT_2", in: window)
        }
        XCTAssertFalse(contains("PRIVATE_POST_1", in: window)); XCTAssertFalse(contains("PRIVATE_COMMENT_1", in: window))
        XCTAssertTrue(f.reader.confirmsCurrentDetail)
    }
    func testMountedRevocationHidesAlreadyLoadedPrivateProjectionWithoutAnotherRequest() async throws {
        let f = try await fixture(), window = mount(f)
        defer { f.reader.retire(); f.wire.abortHeld(); window.isHidden = true; window.rootViewController = nil }
        try await waitFor("The granted projection must be visible before revocation") {
            self.contains("PRIVATE_POST_1", in: window) && self.contains("PRIVATE_COMMENT_1", in: window)
        }
        let count = f.wire.requests.count
        f.access.selected?.revoke()
        try await waitFor("Revocation hides both already loaded private projections") {
            !self.contains("PRIVATE_POST_1", in: window) && !self.contains("PRIVATE_COMMENT_1", in: window)
        }
        XCTAssertFalse(f.reader.isConfigured); XCTAssertFalse(f.reader.confirmsCurrentDetail)
        XCTAssertEqual(f.wire.requests.count, count)
    }
    func testMountedReplacementWhileOldReadIsSuspendedDoesNotWaitOrAcceptLateOld401() async throws {
        let f = try await fixture(); f.wire.holdDetails = true
        let window = mount(f)
        defer { f.reader.retire(); f.wire.abortHeld(); window.isHidden = true; window.rootViewController = nil }
        try await waitFor("A is genuinely suspended") { f.wire.held[1] != nil }
        try f.replace()
        try await waitFor("B starts without waiting for A") { f.wire.held[2] != nil }
        f.wire.finish(2)
        try await waitFor("B becomes the visible current projection") {
            self.contains("PRIVATE_POST_2", in: window) && self.contains("PRIVATE_COMMENT_2", in: window)
        }
        f.wire.finish(1, status: 401)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(f.reader.confirmsCurrentDetail); XCTAssertTrue(f.selection.isCurrent)
        XCTAssertTrue(contains("PRIVATE_POST_2", in: window)); XCTAssertTrue(contains("PRIVATE_COMMENT_2", in: window))
        XCTAssertFalse(contains("PRIVATE_POST_1", in: window)); XCTAssertEqual(f.wire.detailNumber, 2)
    }
}
