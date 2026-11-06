import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Real production view/navigation/sheet lifecycle with sealed protocol data, not a live account.
@MainActor final class NativeFriendRequestReviewHostingTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class Source: NativeFriendServing, NativeFriendMetadataServing, NativeFriendRemovalServing {
        let viewerID: Int64 = 2
        var isCurrent = true
        var canWrite = true
        var canSettle = false
        var version: Int64 = 3
        var accepted = false
        var reads = 0
        var writes: [NativeFriendCommand] = []
        var lookups: [String] = []
        var held = false
        var gate: CheckedContinuation<Void, Never>?
        var unknown = false
        var item: NativeFriendItem { .init(peerID: 9, nickname: "Synthetic applicant", state: accepted ? .friend : .pendingIncoming,
            version: version, message: "Application \(version)", expiresAtMS: 1_900_000_000_000) }
        func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
            reads += 1
            return .init(viewerID: viewerID, incoming: requests && !accepted ? [item] : [], outgoing: [],
                friends: !requests && accepted ? [item] : [], hasMore: false, nextCursor: nil)
        }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
            .init(viewerID: viewerID, peerID: peerID, state: accepted ? .friend : .pendingIncoming, version: version, conversationID: accepted ? 71 : nil)
        }
        func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt {
            writes.append(command)
            if held { await withCheckedContinuation { gate = $0 } }
            if command.action == .accept { accepted = true; version += 1 }
            return try await answer(peerID: command.peerID, action: command.action, requestID: command.requestID)
        }
        func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            lookups.append(requestID); return try await answer(peerID: peerID, action: action, requestID: requestID)
        }
        func read(peerID: Int64) async throws -> NativeFriendMetadata {
            guard accepted else { throw NativeFriendFailure.rejected(404) }
            return .init(viewerID: viewerID, peerID: peerID, friendVersion: version, version: 1,
                remark: nil, groupID: nil, starred: 0, notificationEffect: "NOT_CONNECTED")
        }
        func groups() async throws -> NativeFriendMetadataGroups {
            .init(viewerID: viewerID, list: [.init(id: nil, name: "Default", position: 0, version: 0, isDefault: 1)])
        }
        func write(_ command: NativeFriendMetadataCommand) async throws -> NativeFriendMetadataReceipt { throw NativeFriendFailure.notSent }
        func receipt(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) async throws -> NativeFriendMetadataReceipt { throw NativeFriendFailure.unknown }
        func settle(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID, payloadHash: String) async throws -> NativeFriendMetadataReceipt { throw NativeFriendFailure.notSent }
        func remove(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { throw NativeFriendFailure.notSent }
        func receipt(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { throw NativeFriendFailure.unknown }
        func settle(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { throw NativeFriendFailure.notSent }
        private func answer(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            .init(viewerID: viewerID, peerID: peerID, action: action, requestID: requestID,
                outcome: unknown ? "UNKNOWN" : "APPLIED", relationship: try await relationship(peerID: peerID))
        }
    }
    private final class Routes: ObservableObject {
        @Published var path = ["friends"]
        @Published var phase: ScenePhase = .active
    }
    private struct Root: View {
        @ObservedObject var routes: Routes
        let navigation: NativeFriendHomeNavigation
        let source: Source
        let journal: Journal
        var body: some View {
            NavigationStack(path: $routes.path) {
                Text("Synthetic normal account entry")
                    .navigationDestination(for: String.self) { _ in
                        NativeFriendHomeView(flow: navigation.flow, navigation: navigation,
                            metadataFactory: { .init(peerID: $0.peerID, service: source, journal: journal, ownerKey: "synthetic-owner") },
                            removalFactory: { .init(item: $0, service: source, journal: journal, ownerKey: "synthetic-owner") },
                            conversation: { _ in AnyView(Text("Existing conversation destination")) })
                    }
            }.environment(\.scenePhase, routes.phase)
        }
    }
    private func wait(_ stage: String, file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async throws {
        for _ in 0..<150 { if predicate() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), stage, file: file, line: line)
        if !predicate() { throw NativeFriendFailure.unavailable }
    }
    private func host(_ routes: Routes, _ navigation: NativeFriendHomeNavigation, _ source: Source, _ journal: Journal) throws -> (HostedNavigationSceneWindow, UIViewController) {
        let scene = try HostedNavigationSceneWindow()
        let host = UIHostingController(rootView: Root(routes: routes, navigation: navigation, source: source, journal: journal))
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible()
        XCTAssertTrue(host.view.window === scene.window)
        return (scene, host)
    }
    func testHostedExactReviewCancelAcceptExistingChatAndBackReread() async throws {
        let source = Source(), journal = Journal(), routes = Routes()
        let flow = NativeFriendFlow(service: source, journal: journal, ownerKey: "synthetic-owner")
        let navigation = NativeFriendHomeNavigation(flow)
        let (scene, host) = try host(routes, navigation, source, journal); defer { scene.retire() }
        try await wait("normal list appeared") { flow.phase == .ready && flow.incoming.count == 1 }
        flow.reviewAction(.accept, item: try XCTUnwrap(flow.incoming.first))
        try await wait("real review sheet appeared") { host.presentedViewController != nil }
        XCTAssertEqual(flow.actionReview?.command.expectedVersion, 3)
        flow.cancelReview()
        try await wait("cancel dismissed real sheet") { host.presentedViewController == nil }
        XCTAssertTrue(source.writes.isEmpty); XCTAssertTrue(journal.rows.isEmpty)
        flow.reviewAction(.accept, item: try XCTUnwrap(flow.incoming.first))
        try await wait("review reopened") { host.presentedViewController != nil }
        await flow.confirmReview()
        try await wait("result returned to the list") { host.presentedViewController == nil && flow.friends.count == 1 }
        XCTAssertEqual(source.writes.first?.expectedVersion, 3); XCTAssertEqual(source.writes.count, 1)
        XCTAssertEqual(flow.relationship?.state, .friend); XCTAssertTrue(flow.incoming.isEmpty)
        let peer = try XCTUnwrap(flow.friends.first)
        await navigation.openConversation(peer)
        try await wait("stable chat stays pushed after list purge") { navigation.child != nil && flow.friends.isEmpty && flow.phase == .closed }
        let reads = source.reads
        navigation.child = nil // The actual SwiftUI binding drives Back and appearance.
        try await wait("Back authoritatively rereads") { flow.phase == .ready && flow.friends.count == 1 && source.reads > reads }
        XCTAssertEqual(flow.friends.first?.version, 4); XCTAssertEqual(source.writes.count, 1)
    }
    func testHostedBackDuringWriteAndReopenRecoverOnlyOriginalReceipt() async throws {
        let source = Source(), journal = Journal(), routes = Routes()
        let flow = NativeFriendFlow(service: source, journal: journal, ownerKey: "synthetic-owner")
        let navigation = NativeFriendHomeNavigation(flow)
        let (scene, host) = try host(routes, navigation, source, journal); defer { scene.retire() }
        try await wait("normal list appeared") { flow.phase == .ready }
        flow.reviewAction(.accept, item: try XCTUnwrap(flow.incoming.first))
        try await wait("sheet appeared") { host.presentedViewController != nil }
        let original = try XCTUnwrap(flow.actionReview?.command)
        source.held = true
        let write = Task { await flow.confirmReview() }
        try await wait("sheet consumed and dispatch held") { source.gate != nil && host.presentedViewController == nil }
        routes.path = []
        try await wait("normal Back purged the hidden page") { flow.phase == .closed && flow.incoming.isEmpty }
        source.gate?.resume(); source.gate = nil; await write.value
        XCTAssertNil(flow.relationship); XCTAssertEqual(journal.rows.first?.operationID.uuidString, original.requestID)
        routes.path = ["friends"]
        try await wait("reopen recovered the unresolved identity") { flow.phase == .unknown && flow.pending != nil }
        source.unknown = true; await flow.recover()
        XCTAssertNotNil(flow.pending, "current friendship is not proof of the original receipt")
        source.unknown = false; await flow.recover()
        XCTAssertEqual(source.lookups, [original.requestID, original.requestID]); XCTAssertEqual(source.writes, [original])
        XCTAssertTrue(journal.rows.isEmpty); XCTAssertEqual(flow.phase, .ready)
    }
    func testHostedGrantWithdrawalDismissesReviewAndRejectsOldVersionAfterReturn() async throws {
        let source = Source(), journal = Journal(), routes = Routes()
        let flow = NativeFriendFlow(service: source, journal: journal, ownerKey: "synthetic-owner")
        let navigation = NativeFriendHomeNavigation(flow)
        let (scene, host) = try host(routes, navigation, source, journal); defer { scene.retire() }
        try await wait("normal list appeared") { flow.phase == .ready }
        let old = try XCTUnwrap(flow.incoming.first)
        flow.reviewAction(.reject, item: old)
        try await wait("real sheet appeared") { host.presentedViewController != nil }
        source.isCurrent = false
        XCTAssertNil(flow.actionReview); XCTAssertTrue(flow.incoming.isEmpty)
        try await wait("silent withdrawal dismissed sheet") { host.presentedViewController == nil }
        await flow.confirmReview(); XCTAssertTrue(source.writes.isEmpty); XCTAssertTrue(journal.rows.isEmpty)
        source.isCurrent = true; source.version = 5
        await flow.load(); flow.reviewAction(.accept, item: old)
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.actionReview)
    }
    func testHostedExistingMetadataAndRemovalRoutesSurviveParentPurgeAndBack() async throws {
        for metadata in [true, false] {
            let source = Source(), journal = Journal(), routes = Routes(); source.accepted = true
            let flow = NativeFriendFlow(service: source, journal: journal, ownerKey: "synthetic-owner")
            let navigation = NativeFriendHomeNavigation(flow)
            let (scene, _) = try host(routes, navigation, source, journal); defer { scene.retire() }
            try await wait("real friend row appeared") { flow.phase == .ready && flow.friends.count == 1 }
            let item = try XCTUnwrap(flow.friends.first)
            if metadata {
                navigation.openMetadata(item, using: { .init(peerID: $0.peerID, service: source, journal: journal, ownerKey: "synthetic-owner") })
                guard case .metadata(let child, _)? = navigation.child else { return XCTFail("metadata route missing") }
                try await wait("original metadata child stays open after parent purge") { child.phase == .ready && flow.friends.isEmpty }
                XCTAssertEqual(child.metadata?.peerID, 9); XCTAssertEqual(child.metadata?.friendVersion, 3)
                child.reviewMetadata(remark: "Synthetic edit", groupID: nil, starred: false); child.cancelReview()
            } else {
                navigation.openRemoval(item, using: { .init(item: $0, service: source, journal: journal, ownerKey: "synthetic-owner") })
                guard case .removal(let child)? = navigation.child else { return XCTFail("removal route missing") }
                try await wait("original removal child stays open after parent purge") { child.phase == .ready && flow.friends.isEmpty }
                XCTAssertEqual(child.currentRelationship?.peerID, 9); XCTAssertEqual(child.currentRelationship?.version, 3)
                child.reviewRemoval(); child.cancelReview()
            }
            XCTAssertNotNil(navigation.child); XCTAssertTrue(journal.rows.isEmpty); XCTAssertTrue(source.writes.isEmpty)
            let reads = source.reads; navigation.child = nil
            try await wait("actual Back reloads the original list") { flow.phase == .ready && flow.friends.count == 1 && source.reads > reads }
        }
    }

    func testHostedBackgroundCancelsUnsentReviewAndForegroundRereadsNewVersion() async throws {
        let source = Source(), journal = Journal(), routes = Routes()
        let flow = NativeFriendFlow(service: source, journal: journal, ownerKey: "synthetic-owner")
        let navigation = NativeFriendHomeNavigation(flow)
        let (scene, host) = try host(routes, navigation, source, journal); defer { scene.retire() }
        try await wait("normal list appeared") { flow.phase == .ready }
        flow.reviewAction(.accept, item: try XCTUnwrap(flow.incoming.first))
        try await wait("sheet appeared") { host.presentedViewController != nil }
        // Controlled SwiftUI scene environment exercises the production lifecycle observer.
        // This is not an OS background/process-kill certification.
        routes.phase = .background
        try await wait("background clears sheet and private list") { host.presentedViewController == nil && flow.incoming.isEmpty && flow.phase == .closed }
        XCTAssertNil(flow.actionReview); XCTAssertTrue(source.writes.isEmpty); XCTAssertTrue(journal.rows.isEmpty)
        source.version = 5; routes.phase = .active
        try await wait("foreground reloads replacement application") { flow.phase == .ready && flow.incoming.first?.version == 5 }
        await flow.confirmReview(); XCTAssertTrue(source.writes.isEmpty)
    }

}
