import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Sealed test-only responses. Production views and real existing metadata/removal flows are hosted
/// in an active scene; the test never invokes appearance/disappearance hooks or dispatches a network request.
@MainActor final class NativeFriendDirectoryNavigationHostingTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class State: NativeFriendMetadataServing, NativeFriendRemovalServing {
        let viewerID: Int64 = 2
        var isCurrent = true
        var canWrite: Bool { isCurrent }
        var canSettle: Bool { isCurrent }
        var friend = true
        var friendVersion: Int64 = 3
        var metadataVersion: Int64 = 1
        var remark: String? = "Private rider"
        var groupID: Int64? = 4
        var starred = 1
        var writes: [NativeFriendMetadataCommand] = []
        var removals: [NativeFriendRemovalCommand] = []
        let journal = Journal()
        var item: NativeFriendItem { .init(peerID: 9, nickname: "Synthetic peer", state: .friend, version: friendVersion,
            message: "", expiresAtMS: 0, friendRemark: remark, groupID: groupID, starred: starred) }
        var metadata: NativeFriendMetadata { .init(viewerID: viewerID, peerID: 9, friendVersion: friendVersion,
            version: metadataVersion, remark: remark, groupID: groupID, starred: starred, notificationEffect: "NOT_CONNECTED") }
        var groupPage: NativeFriendMetadataGroups { .init(viewerID: viewerID, list: [
            .init(id: nil, name: "default", position: 0, version: 0, isDefault: 1),
            .init(id: 4, name: "riders", position: 1, version: 1, isDefault: 0)]) }
        func read(peerID: Int64) async throws -> NativeFriendMetadata {
            guard isCurrent, friend, peerID == 9 else { throw NativeFriendFailure.rejected(404) }; return metadata
        }
        func groups() async throws -> NativeFriendMetadataGroups { groupPage }
        func write(_ command: NativeFriendMetadataCommand) async throws -> NativeFriendMetadataReceipt {
            guard isCurrent, friend, command.targetID == 9 else { throw NativeFriendFailure.notSent }
            writes.append(command); remark = command.remark; groupID = command.groupID; starred = command.starred ?? 0; metadataVersion += 1
            return .init(viewerID: viewerID, requestID: command.requestID.uuidString, action: command.action,
                targetID: command.targetID, outcome: "APPLIED", current: metadata, groups: nil, payloadHash: try command.fingerprint())
        }
        func receipt(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) async throws -> NativeFriendMetadataReceipt { throw NativeFriendFailure.unknown }
        func settle(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID, payloadHash: String) async throws -> NativeFriendMetadataReceipt { throw NativeFriendFailure.notSent }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
            guard isCurrent, peerID == 9 else { throw NativeFriendFailure.notSent }
            return .init(viewerID: viewerID, peerID: peerID, state: friend ? .friend : .none, version: friendVersion, conversationID: nil)
        }
        func remove(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
            guard isCurrent, friend, command.peerID == 9, command.expectedVersion == friendVersion else { throw NativeFriendFailure.notSent }
            removals.append(command); friend = false; friendVersion += 1
            return .init(viewerID: viewerID, command: command, outcome: "APPLIED", reason: "REMOVED",
                removedVersion: friendVersion, currentRelationship: try await relationship(peerID: command.peerID))
        }
        func receipt(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { throw NativeFriendFailure.unknown }
        func settle(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { throw NativeFriendFailure.notSent }
        func makeMetadata(_ item: NativeFriendItem) -> NativeFriendMetadataFlow {
            .init(peerID: item.peerID, service: self, journal: journal, ownerKey: "synthetic-owner-2")
        }
        func makeRemoval(_ item: NativeFriendItem?) -> NativeFriendRemovalFlow {
            .init(item: item, service: self, journal: journal, ownerKey: "synthetic-owner-2")
        }
    }
    /// The directory grant is deliberately independent from still-current metadata/removal grants.
    private final class Directory: NativeFriendDirectoryServing {
        let state: State
        var allowed = true
        var expiresAt: Date = .distantFuture
        var viewerID: Int64 { state.viewerID }
        var isCurrent: Bool { state.isCurrent && allowed && Date() < expiresAt }
        var pages: [NativeFriendDirectoryFilter] = []
        var details: [Int64] = []
        var conversationID: Int?
        var detailHandler: ((Int64) async throws -> NativeFriendDirectoryDetail)?
        init(_ state: State) { self.state = state }
        func page(filter: NativeFriendDirectoryFilter, cursor: String?) async throws -> NativeFriendDirectoryPage {
            guard isCurrent else { throw NativeFriendFailure.notSent }; pages.append(filter)
            let included = state.friend && (filter.groupID == nil || filter.groupID == (state.groupID ?? 0)) && (!filter.starredOnly || state.starred == 1)
            return .init(viewerID: viewerID, section: filter.section, groupID: filter.groupID, starredOnly: filter.starredOnly,
                revision: String(repeating: "a", count: 64), groups: state.groupPage,
                counts: ["all": state.friend ? 1 : 0, "together": state.friend ? 1 : 0, "recent": state.friend ? 1 : 0],
                total: included ? 1 : 0, items: included ? [state.item] : [], hasMore: false, nextCursor: nil)
        }
        func detail(peerID: Int64) async throws -> NativeFriendDirectoryDetail {
            guard isCurrent else { throw NativeFriendFailure.notSent }; details.append(peerID)
            if let detailHandler { return try await detailHandler(peerID) }
            guard state.friend, peerID == 9 else { throw NativeFriendDirectoryFailure.unavailablePeer }
            return .init(viewerID: viewerID, item: state.item, conversationID: conversationID)
        }
    }
    private func wait(_ stage: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), stage, file: file, line: line)
        if !condition() { throw NativeFriendFailure.unavailable }
    }
    private func host(_ state: State, _ navigation: NativeFriendDirectoryNavigation,
                      publicProfile: ((Int, @escaping () -> Bool) -> AnyView)? = nil,
                      conversation: @escaping (Int) -> AnyView = { _ in AnyView(Text("No conversation fixture")) }) throws -> HostedNavigationSceneWindow {
        let scene = try HostedNavigationSceneWindow()
        let root = NativeFriendDirectoryView(flow: navigation.flow, navigation: navigation,
            metadataFactory: state.makeMetadata, removalFactory: state.makeRemoval, publicProfile: publicProfile, conversation: conversation)
        let host = UIHostingController(rootView: NavigationStack { root })
        scene.window.rootViewController = host; scene.window.makeKeyAndVisible()
        XCTAssertTrue(host.view.window === scene.window)
        return scene
    }
    func testHostedDirectoryDetailMetadataBackPreservesFilterAndRereadsMovedStarredRow() async throws {
        // Each hosting tree uses exactly one captured owner; never substitute the current row by index.
        let state = State()
        let source = Directory(state)
        let directory = NativeFriendDirectoryFlow(service: source), navigation = NativeFriendDirectoryNavigation(directory)
        let scene = try host(state, navigation); defer { scene.retire() }
        try await wait("directory appeared") { directory.phase == .ready }
        let filter = NativeFriendDirectoryFilter(section: .recent, groupID: 4, starredOnly: true)
        await directory.select(filter)
        navigation.open(try XCTUnwrap(directory.items.first))
        let detail = try XCTUnwrap(navigation.selection)
        try await wait("detail stays pushed after list data was purged") { detail.flow.canOpen && directory.items.isEmpty && directory.phase == .closed }
        XCTAssertEqual(detail.flow.peerID, 9)
        detail.openMetadata(using: state.makeMetadata)
        guard case .metadata(let metadata, _)? = detail.child else { return XCTFail("metadata route missing") }
        try await wait("metadata stays pushed after detail data was purged") { metadata.phase == .ready && detail.flow.detail == nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(navigation.selection === detail); XCTAssertNotNil(detail.child)
        metadata.reviewMetadata(remark: "Moved rider", groupID: nil, starred: false)
        metadata.cancelReview(); XCTAssertTrue(state.writes.isEmpty)
        metadata.reviewMetadata(remark: "Moved rider", groupID: nil, starred: false)
        await metadata.confirm(); XCTAssertEqual(state.writes.count, 1); XCTAssertEqual(metadata.metadata?.starred, 0)
        let detailReads = source.details.count
        detail.child = nil // Actual navigation binding back, not manual lifecycle calls.
        try await wait("detail returned with authoritative changed metadata") { detail.flow.detail?.item.friendRemark == "Moved rider" && source.details.count > detailReads }
        XCTAssertEqual(detail.flow.detail?.item.starred, 0); XCTAssertNil(detail.flow.detail?.item.groupID)
        navigation.selection = nil
        try await wait("original filter returned and no longer contains changed peer") { directory.phase == .ready && directory.items.isEmpty }
        XCTAssertEqual(directory.filter, filter); XCTAssertEqual(source.pages.last, filter)
        await directory.select(.init())
        navigation.open(try XCTUnwrap(directory.items.first))
        try await wait("reopened detail keeps peer identity") { navigation.selection?.flow.detail?.item.friendRemark == "Moved rider" }
        XCTAssertEqual(navigation.selection?.flow.peerID, 9); XCTAssertTrue(state.journal.rows.isEmpty)
    }
    func testHostedRemoveCancelConfirmReturnAndReaddedVersion() async throws {
        let state = State()
        let service = Directory(state)
        let directory = NativeFriendDirectoryFlow(service: service), navigation = NativeFriendDirectoryNavigation(directory)
        let scene = try host(state, navigation); defer { scene.retire() }
        try await wait("directory appeared") { directory.phase == .ready }
        navigation.open(try XCTUnwrap(directory.items.first)); let detail = try XCTUnwrap(navigation.selection)
        try await wait("detail appeared") { detail.flow.canOpen && directory.phase == .closed }
        detail.openRemoval(using: state.makeRemoval)
        guard case .removal(let removal)? = detail.child else { return XCTFail("removal route missing") }
        try await wait("removal stays pushed without parent detail snapshot") { removal.phase == .ready && detail.flow.detail == nil }
        removal.reviewRemoval(); removal.cancelReview(); XCTAssertTrue(state.removals.isEmpty)
        removal.reviewRemoval(); await removal.confirm(); XCTAssertEqual(removal.phase, .resolved)
        XCTAssertEqual(state.removals.first?.peerID, 9); XCTAssertEqual(state.removals.first?.expectedVersion, 3)
        detail.child = nil
        try await wait("removed detail returns unavailable") { detail.flow.issue == "friendDirectory.unavailablePeer" }
        XCTAssertFalse(detail.flow.canOpen)
        navigation.selection = nil
        try await wait("removed row disappears on list return") { directory.phase == .ready && directory.items.isEmpty }
        state.friend = true; state.friendVersion = 5; state.remark = nil; state.groupID = nil; state.starred = 0
        await directory.load()
        navigation.open(try XCTUnwrap(directory.items.first))
        try await wait("readded row uses a fresh authoritative relationship") { navigation.selection?.flow.detail?.item.version == 5 }
        XCTAssertEqual(navigation.selection?.flow.detail?.item.starred, 0); XCTAssertTrue(state.journal.rows.isEmpty)
    }
    func testHostedIndependentGrantWithdrawalAndExpiryDismissBothKindsOfChildWithoutReads() async throws {
        for metadataRoute in [true, false] {
            let state = State()
            let service = Directory(state)
            let directory = NativeFriendDirectoryFlow(service: service), navigation = NativeFriendDirectoryNavigation(directory)
            let scene = try host(state, navigation); defer { scene.retire() }
            try await wait("list appeared") { directory.phase == .ready }
            navigation.open(try XCTUnwrap(directory.items.first)); let detail = try XCTUnwrap(navigation.selection)
            try await wait("detail appeared") { detail.flow.canOpen }
            var metadata: NativeFriendMetadataFlow?, removal: NativeFriendRemovalFlow?
            if metadataRoute {
                detail.openMetadata(using: state.makeMetadata)
                if case .metadata(let child, _)? = detail.child { metadata = child }
                try await wait("metadata appeared") { metadata?.phase == .ready }
            } else {
                detail.openRemoval(using: state.makeRemoval)
                if case .removal(let child)? = detail.child { removal = child }
                try await wait("removal appeared") { removal?.phase == .ready }
            }
            let reads = service.pages.count + service.details.count
            if metadataRoute { service.allowed = false } else { service.expiresAt = Date().addingTimeInterval(0.03) }
            try await wait("silent grant retirement dismisses nested route") { navigation.selection == nil && detail.child == nil }
            XCTAssertTrue(state.isCurrent, "independent metadata/removal approvals have not been withdrawn")
            XCTAssertNil(metadata?.metadata); XCTAssertNil(removal?.currentRelationship); XCTAssertNil(detail.flow.detail)
            XCTAssertTrue(directory.items.isEmpty); XCTAssertEqual(directory.phase, .closed)
            XCTAssertEqual(service.pages.count + service.details.count, reads)
            XCTAssertTrue(state.writes.isEmpty); XCTAssertTrue(state.removals.isEmpty)
        }
    }
    func testHostedReadyAccountSwitchClearsWithoutRefreshAndOldRouteCannotReopen() async throws {
        let state = State()
        let service = Directory(state)
        let flow = NativeFriendDirectoryFlow(service: service), navigation = NativeFriendDirectoryNavigation(flow)
        let scene = try host(state, navigation); defer { scene.retire() }
        try await wait("directory appeared") { flow.phase == .ready }
        let old = try XCTUnwrap(flow.items.first), reads = service.pages.count
        state.isCurrent = false
        XCTAssertTrue(flow.items.isEmpty); XCTAssertTrue(flow.groups.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        navigation.open(old); XCTAssertNil(navigation.selection); XCTAssertEqual(service.pages.count, reads)
        state.isCurrent = true
        await flow.load(); XCTAssertEqual(flow.phase, .closed); XCTAssertTrue(flow.items.isEmpty)
    }
    func testHostedRealPublicProfileUsesIndependentGrantAndReturnsToSameFriendAndFilter() async throws {
        for enabled in [false, true] {
            let state = State(), publicInfo = try PublicProfileHarness(enabled: enabled)
            publicInfo.session.authChannels.cancel()
            await publicInfo.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
            let service = Directory(state)
            let live = NativeFriendDirectoryFlow(service: service), navigation = NativeFriendDirectoryNavigation(live)
            let scene = try host(state, navigation, publicProfile: { memberID, isCurrent in
                let reader = publicInfo.session.makeProfilePublicInfoReader(memberID: memberID, isCurrent: isCurrent)
                return AnyView(ProfilePublicInfoHost(reader: reader) { reader in
                    SocialPublicProfileView(memberID: memberID, reader: reader, squareReader: publicInfo.session.squareReader,
                        showsStartChat: false, isCurrent: { isCurrent() && reader.isCurrent })
                })
            }); defer { scene.retire() }
            try await wait("directory appeared") { live.phase == .ready }
            let filter = NativeFriendDirectoryFilter(section: .recent, groupID: 4, starredOnly: true)
            await live.select(filter); navigation.open(try XCTUnwrap(live.items.first))
            let detail = try XCTUnwrap(navigation.selection)
            try await wait("detail appeared") { detail.flow.canOpen }
            await detail.openProfile()
            guard case .profile(let selected)? = detail.child else { return XCTFail("public profile route missing") }
            XCTAssertEqual(selected.memberID, 9)
            try await wait("public profile owns route after private detail clears") { detail.flow.detail == nil && detail.owns(selected) }
            if enabled { try await wait("real profile read") { publicInfo.wire.paths.contains("public-info") } }
            else {
                try await Task.sleep(nanoseconds: 100_000_000)
                XCTAssertFalse(publicInfo.wire.paths.contains("public-info"), "Directory authority cannot substitute for public-info approval")
            }
            let detailReads = service.details.count
            detail.child = nil
            try await wait("profile Back rereads exact friend") { detail.flow.canOpen && service.details.count > detailReads }
            XCTAssertFalse(detail.owns(selected)); XCTAssertEqual(detail.flow.detail?.item.peerID, 9)
            navigation.selection = nil
            try await wait("directory Back rereads same filter") { live.phase == .ready }
            XCTAssertEqual(live.filter, filter)
            XCTAssertTrue(publicInfo.wire.paths.allSatisfy { ["phone", "userInfo", "public-info"].contains($0) })
            XCTAssertTrue(state.writes.isEmpty); XCTAssertTrue(state.removals.isEmpty)
        }
    }
    func testHostedExistingConversationReturnsAndGrantWithdrawalDismissesNestedRoute() async throws {
        let state = State()
        let source = Directory(state)
        source.conversationID = 80
        let flow = NativeFriendDirectoryFlow(service: source), navigation = NativeFriendDirectoryNavigation(flow)
        var opened: [Int] = []
        let scene = try host(state, navigation, conversation: { id in
            AnyView(Text("Existing conversation").onAppear { opened.append(id) })
        }); defer { scene.retire() }
        try await wait("directory appeared") { flow.phase == .ready }
        navigation.open(try XCTUnwrap(flow.items.first)); let detail = try XCTUnwrap(navigation.selection)
        try await wait("detail appeared") { detail.flow.canOpen }
        await detail.openConversation()
        try await wait("existing conversation survives detail disappearance") { opened.contains(80) && detail.flow.detail == nil }
        source.conversationID = nil; detail.child = nil
        try await wait("Back observes unavailable conversation without creating a new one") { detail.flow.canOpen && detail.flow.detail?.conversationID == nil }
        await detail.openConversation(); XCTAssertNil(detail.child)
        source.conversationID = 80; await detail.flow.load(); await detail.openConversation()
        source.allowed = false
        try await wait("directory grant retirement closes existing conversation") { navigation.selection == nil && detail.child == nil }
        XCTAssertEqual(Set(opened), [80]); XCTAssertTrue(flow.items.isEmpty)
    }
    func testLateConversationCannotReplaceNewerMetadataRouteAfterBack() async throws {
        let state = State()
        let service = Directory(state)
        let flow = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
        let detail = NativeFriendDirectoryDetailModel(flow); await flow.load()
        var held: CheckedContinuation<NativeFriendDirectoryDetail, Error>?
        service.detailHandler = { _ in try await withCheckedThrowingContinuation { held = $0 } }
        let pending = Task { await detail.openConversation() }
        for _ in 0..<100 where held == nil { await Task.yield() }
        detail.retire(); service.detailHandler = nil; await flow.load()
        let oldGeneration = detail.routeGeneration
        detail.openMetadata(using: state.makeMetadata)
        detail.closeChild(generation: oldGeneration)
        held?.resume(returning: .init(viewerID: 2, item: state.item, conversationID: 80)); await pending.value
        guard case .metadata? = detail.child else { return XCTFail("late conversation replaced the newer route") }
    }
    func testPublicProfileGateRetiresWithParentEvenWhileIndependentGrantRemains() async throws {
        let state = State()
        let source = Directory(state)
        let flow = NativeFriendDirectoryFlow(service: source), navigation = NativeFriendDirectoryNavigation(flow)
        var current: (() -> Bool)?
        let scene = try host(state, navigation, publicProfile: { _, isCurrent in
            current = isCurrent; return AnyView(Text("Public profile route"))
        }); defer { scene.retire() }
        try await wait("directory appeared") { flow.phase == .ready }
        navigation.open(try XCTUnwrap(flow.items.first)); let detail = try XCTUnwrap(navigation.selection)
        try await wait("detail appeared") { detail.flow.canOpen }; await detail.openProfile()
        try await wait("profile appeared") { current?() == true }
        source.allowed = false
        XCTAssertEqual(current?(), false)
        try await wait("parent grant closes profile") { navigation.selection == nil && detail.child == nil }
    }
    func testPublicProfileDeploymentRejectsInvalidDomainEvenWhenApproved() throws {
        let base = "https://friend-profile.invalid/native"
        XCTAssertThrowsError(try ReviewedAppDeployment(market: .china, baseURL: base,
            approvedBaseURLs: [.china: [base]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.friend-profile", realm: "synthetic")) { error in
            XCTAssertEqual(error as? APIError, .invalidConfiguration)
        }
    }
    @MainActor private final class PublicProfileHarness {
        let wire = PublicProfileWire()
        let session: AppSession
        init(enabled: Bool) throws {
            let base = "https://friend-profile.example.test/native"
            let deployment = try ReviewedAppDeployment(market: .china, baseURL: base,
                approvedBaseURLs: [.china: [base]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.friend-profile", realm: "synthetic")
            let vault = PublicProfileVault(), wire = self.wire
            var access: ProfilePublicInfoReadAccess?
            let root = AppCompositionRoot(deployment: .reviewed(deployment),
                storage: .init(defaults: UserDefaults(suiteName: "friend-profile-" + UUID().uuidString)!, tokenStore: { _ in vault }),
                makeTransport: { wire }, profilePublicInfoReadAccess: { context in
                    guard enabled else { return nil }
                    if access == nil {
                        access = try? .init(context: context, approval: .init(baseURL: context.baseURL,
                            namespace: context.session.namespace, accountID: context.session.accountID, paths: [ProfilePublicInfoReadRoute.path]))
                    }
                    return access
                })
            session = root.makeSession()
        }
    }
    @MainActor private final class PublicProfileVault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class PublicProfileWire: HTTPTransport {
        var paths: [String] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let path = request.url!.lastPathComponent; paths.append(path)
            switch path {
            case "phone": return (Data(#"{"code":200,"token":"synthetic-profile","data":{"id":2,"role":"player"}}"#.utf8), 200)
            case "userInfo": return (Data(#"{"code":200,"appUser":{"userId":2,"role":"player"}}"#.utf8), 200)
            case "public-info": return (Data(#"{"code":200,"data":{"id":9,"nickname":"Public friend","introduction":"Public introduction"}}"#.utf8), 200)
            default: return (Data(#"{"code":404}"#.utf8), 404)
            }
        }
    }

}
