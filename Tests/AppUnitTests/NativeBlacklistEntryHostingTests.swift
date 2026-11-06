import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Authored, NOT_RUN without an approved Apple toolchain. Real navigation/lifecycle with sealed data;
/// controlled scene/authority changes are not device background or live account certification.
@MainActor final class NativeBlacklistEntryHostingTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey }
        }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class Friends: NativeFriendServing {
        let viewerID: Int64 = 2
        var isCurrent = true
        let canWrite = false
        var reads = 0
        func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
            reads += 1
            return .init(viewerID: viewerID, incoming: [], outgoing: [], friends: [], hasMore: false, nextCursor: nil)
        }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship { throw NativeFriendFailure.notSent }
        func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt { throw NativeFriendFailure.notSent }
        func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt { throw NativeFriendFailure.unknown }
    }
    private final class Blacklist: NativeBlacklistServing {
        let viewerID: Int64 = 2
        var isCurrent = true
        var canWrite: Bool { isCurrent }
        var canSettle = false
        let journal = Journal()
        let ownerKey = "blacklist:synthetic-owner-2"
        let item = NativeBlacklistItem(blockID: 31, peerID: 9, nickname: "Blocked peer without a conversation")
        var blocked = true
        var reads = 0
        var heldRead = false
        var heldWrite = false
        var readGate: CheckedContinuation<Void, Never>?
        var writeGate: CheckedContinuation<Void, Never>?
        var writes: [NativeBlacklistCommand] = []
        var receipts: [NativeBlacklistCommand] = []
        var factoryCalls = 0
        func makeFlow() -> NativeBlacklistFlow {
            factoryCalls += 1
            return NativeBlacklistFlow(service: self, journal: journal, ownerKey: ownerKey)
        }
        func page(cursor: Int64) async throws -> NativeBlacklistPage {
            reads += 1
            if heldRead { await withCheckedContinuation { readGate = $0 } }
            return .init(viewerID: viewerID, items: blocked ? [item] : [], writeEnabled: true)
        }
        func current(peerID: Int64) async throws -> NativeBlacklistCurrent {
            .init(viewerID: viewerID, peerID: peerID, blocked: blocked, blockID: blocked ? item.blockID : nil)
        }
        func unblock(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
            writes.append(command)
            if heldWrite { await withCheckedContinuation { writeGate = $0 } }
            blocked = false
            return .init(viewerID: viewerID, command: command, outcome: "APPLIED", reason: "UNBLOCKED")
        }
        func receipt(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
            receipts.append(command)
            return .init(viewerID: viewerID, command: command, outcome: "APPLIED", reason: "UNBLOCKED")
        }
        func settle(_ command: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt { throw NativeBlacklistFailure.notSent }
    }
    private final class Routes: ObservableObject {
        @Published var path = ["friends"]
        @Published var phase: ScenePhase = .active
        @Published var homeAppeared = false
    }
    private struct Root: View {
        @ObservedObject var routes: Routes
        let navigation: NativeFriendHomeNavigation
        let blacklist: Blacklist
        var body: some View {
            NavigationStack(path: $routes.path) {
                Text("Synthetic account entry")
                    .navigationDestination(for: String.self) { _ in
                        NativeFriendHomeView(flow: navigation.flow, navigation: navigation,
                            blacklistFactory: blacklist.makeFlow,
                            conversation: { _ in AnyView(Text("No conversation required")) })
                            .onAppear { routes.homeAppeared = true }
                    }
            }.environment(\.scenePhase, routes.phase)
        }
    }
    private func wait(_ stage: String, file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async throws {
        for _ in 0..<150 { if predicate() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), stage, file: file, line: line)
        if !predicate() { throw NativeBlacklistFailure.unavailable }
    }
    private func host(_ routes: Routes, _ navigation: NativeFriendHomeNavigation, _ blacklist: Blacklist) throws -> HostedNavigationSceneWindow {
        let scene = try HostedNavigationSceneWindow()
        let host = UIHostingController(rootView: Root(routes: routes, navigation: navigation, blacklist: blacklist))
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible()
        XCTAssertTrue(host.view.window === scene.window)
        return scene
    }
    private func open(_ navigation: NativeFriendHomeNavigation, _ source: Blacklist) throws -> NativeBlacklistFlow {
        navigation.openBlacklist(using: source.makeFlow)
        guard case .blacklist(let child)? = navigation.child else { throw NativeBlacklistFailure.unavailable }
        return child
    }
    func testHostedBlacklistWithoutFriendReadAuthorityAndRepeatedOpen() async throws {
        let source = Blacklist(), routes = Routes()
        let parent = NativeFriendFlow(service: nil, journal: source.journal, ownerKey: "friend:unconfigured")
        let navigation = NativeFriendHomeNavigation(parent)
        let scene = try host(routes, navigation, source); defer { scene.retire() }
        // Nil friend service is deliberate: no friend row, conversation or IM grant grants access.
        try await wait("closed friend Home appeared normally") { routes.homeAppeared }
        let child = try open(navigation, source)
        try await wait("independent owner destination appeared") { child.phase == .ready && child.items == [source.item] }
        XCTAssertFalse(parent.isCurrent); XCTAssertTrue(parent.friends.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard case .blacklist(let retained)? = navigation.child else { return XCTFail("friend grant absence popped blacklist") }
        XCTAssertTrue(retained === child)
        navigation.openBlacklist(using: source.makeFlow)
        XCTAssertEqual(source.factoryCalls, 1, "repeat opening cannot replace the live owner destination")
        XCTAssertTrue(source.writes.isEmpty)
    }
    func testHostedBackRereadsParentWithoutRefreshingHiddenRowsOnResolution() async throws {
        let source = Blacklist(), friends = Friends(), routes = Routes()
        let parent = NativeFriendFlow(service: friends, journal: source.journal, ownerKey: "friend:synthetic-owner-2")
        let navigation = NativeFriendHomeNavigation(parent)
        let scene = try host(routes, navigation, source); defer { scene.retire() }
        try await wait("ordinary friend Home appeared") { parent.phase == .ready }
        let child = try open(navigation, source)
        try await wait("blacklist survives real parent disappearance") { child.phase == .ready && parent.phase == .closed }
        let reads = friends.reads
        await child.reviewUnblock(source.item); await child.confirm()
        XCTAssertEqual(child.result?.outcome, "APPLIED"); XCTAssertFalse(try XCTUnwrap(child.current).blocked)
        XCTAssertEqual(friends.reads, reads); XCTAssertEqual(parent.phase, .closed)
        navigation.child = nil // Production binding dismissal, not a manual appearance callback.
        try await wait("Back authoritatively rereads normal Home") { parent.phase == .ready && friends.reads > reads }
        XCTAssertEqual(child.phase, .closed); XCTAssertTrue(child.items.isEmpty); XCTAssertNil(child.result)
        XCTAssertEqual(source.writes.count, 1); XCTAssertTrue(source.journal.rows.isEmpty)
    }
    func testHostedBackgroundRejectsDelayedReadAndForegroundReopensFreshChild() async throws {
        let source = Blacklist(), friends = Friends(), routes = Routes()
        let parent = NativeFriendFlow(service: friends, journal: source.journal, ownerKey: "friend:synthetic-owner-2")
        let navigation = NativeFriendHomeNavigation(parent)
        let scene = try host(routes, navigation, source); defer { scene.retire() }
        try await wait("ordinary Home appeared") { parent.phase == .ready }
        source.heldRead = true
        let old = try open(navigation, source)
        try await wait("blacklist read is held") { source.readGate != nil }
        routes.phase = .background
        try await wait("background dismisses and purges owner destination") { navigation.child == nil && old.phase == .closed }
        source.heldRead = false; source.readGate?.resume(); source.readGate = nil
        await Task.yield()
        XCTAssertTrue(old.items.isEmpty); XCTAssertNil(old.review); XCTAssertNil(old.result)
        routes.phase = .active
        try await wait("foreground rereads Home") { parent.phase == .ready }
        let fresh = try open(navigation, source)
        XCTAssertFalse(fresh === old)
        try await wait("fresh child reads its owner rows") { fresh.phase == .ready && fresh.items.count == 1 }
        XCTAssertTrue(old.items.isEmpty); XCTAssertTrue(source.writes.isEmpty)
    }
    func testHostedOwnerAuthorityRetirementRejectsOldCallbackAndCannotRevive() async throws {
        let source = Blacklist(), routes = Routes()
        let parent = NativeFriendFlow(service: nil, journal: source.journal, ownerKey: "friend:unconfigured")
        let navigation = NativeFriendHomeNavigation(parent)
        let scene = try host(routes, navigation, source); defer { scene.retire() }
        try await wait("closed friend Home appeared normally") { routes.homeAppeared }
        source.heldRead = true
        let old = try open(navigation, source)
        try await wait("old owner's read is held") { source.readGate != nil }
        // The fake flips the captured service authority as an account/role/grant replacement would.
        source.isCurrent = false
        try await wait("silent authority withdrawal purges the retained page") { old.phase == .closed && old.items.isEmpty }
        source.heldRead = false; source.readGate?.resume(); source.readGate = nil
        await Task.yield()
        source.isCurrent = true
        await old.load()
        XCTAssertFalse(old.isCurrent); XCTAssertTrue(old.items.isEmpty); XCTAssertNil(old.review)
        XCTAssertTrue(source.writes.isEmpty)
    }
    func testHostedBackDuringWritePreservesOriginalAndReopenOnlyRecoversReceipt() async throws {
        let source = Blacklist(), friends = Friends(), routes = Routes()
        let parent = NativeFriendFlow(service: friends, journal: source.journal, ownerKey: "friend:synthetic-owner-2")
        let navigation = NativeFriendHomeNavigation(parent)
        let scene = try host(routes, navigation, source); defer { scene.retire() }
        try await wait("ordinary Home appeared") { parent.phase == .ready }
        let old = try open(navigation, source)
        try await wait("blacklist appeared") { old.phase == .ready }
        await old.reviewUnblock(source.item)
        let original = try XCTUnwrap(old.review)
        source.heldWrite = true
        let write = Task { await old.confirm() }
        try await wait("original write dispatched and held") { source.writeGate != nil }
        navigation.child = nil
        try await wait("Back purges the old owner destination") { parent.phase == .ready && old.phase == .closed }
        source.heldWrite = false; source.writeGate?.resume(); source.writeGate = nil
        await write.value
        XCTAssertNil(old.result); XCTAssertEqual(source.journal.rows.first?.operationID, original.requestID)
        let reads = source.reads, reopened = try open(navigation, source)
        try await wait("reopen presents durable original before list") { reopened.phase == .unknown && reopened.pendingCommand == original }
        XCTAssertEqual(source.reads, reads)
        await reopened.recover()
        XCTAssertEqual(source.receipts, [original]); XCTAssertEqual(source.writes, [original])
        XCTAssertTrue(source.journal.rows.isEmpty); XCTAssertEqual(reopened.result?.outcome, "APPLIED")
    }
}
