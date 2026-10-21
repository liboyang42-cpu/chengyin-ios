import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProfileSettingsFavoritesTests: XCTestCase {
    private func opened(_ h: ProfileFavoritesHarness) throws -> (ProfileSettingsFavoritesOwner, ProfileSettingsFavoritesRoute) {
        let owner = ProfileSettingsFavoritesOwner()
        owner.appear(current: .current(h.session), foreground: true)
        XCTAssertTrue(owner.open(.current(h.session)))
        return (owner, try XCTUnwrap(owner.route))
    }
    private func loadBoth(_ h: ProfileFavoritesHarness) async throws {
        _ = try await h.session.profileFavoritesReader.favoritePosts(pageNumber: 1, pageSize: 10)
        _ = try await h.session.profileFavoritesReader.favoriteTopics(pageNumber: 1, pageSize: 10)
    }
    func testEntryRequiresAuthenticatedMatchingAccount() async throws {
        let h = try ProfileFavoritesHarness()
        XCTAssertNil(ProfileSettingsFavoritesAccess.current(h.session))
        await h.login()
        let access = try XCTUnwrap(ProfileSettingsFavoritesAccess.current(h.session))
        XCTAssertTrue(access.reader === h.session.profileFavoritesReader)
        XCTAssertNil(ProfileSettingsFavoritesAccess(accountID: 0, identity: h.session.socialAccountReader.identity,
            viewerRevision: h.session.contentDetailRevision, reader: access.reader))
        XCTAssertNil(ProfileSettingsFavoritesAccess(accountID: 82, identity: h.session.socialAccountReader.identity,
            viewerRevision: h.session.contentDetailRevision, reader: access.reader))
    }
    func testDefaultNilApprovalOpensHonestUnavailableCollectionWithoutDispatch() async throws {
        let h = try ProfileFavoritesHarness(lists: false, details: false); await h.login()
        h.wire.requests = []
        let (owner, route) = try opened(h)
        XCTAssertFalse(route.access.key.configured)
        XCTAssertTrue(owner.accepts(route, current: .current(h.session)))
        let model = AccountCollectionPostsScreenModel()
        await model.refresh(reader: route.access.reader, pageSize: 10)
        XCTAssertNotNil(model.state.issue)
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertFalse(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        XCTAssertFalse(owner.openTopic(201, from: route, current: .current(h.session)))
    }
    func testOnlyAcceptedCollectionRowsCanOpenExistingDetailSelections() async throws {
        let h = try ProfileFavoritesHarness(); await h.login()
        let (owner, route) = try opened(h)
        XCTAssertFalse(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        XCTAssertFalse(owner.openTopic(201, from: route, current: .current(h.session)))
        try await loadBoth(h)
        XCTAssertFalse(owner.openPost(.init(id: 101, generation: .communityV1), from: route, current: .current(h.session)))
        XCTAssertFalse(owner.openPost(.init(id: 999, generation: .legacySquare), from: route, current: .current(h.session)))
        XCTAssertFalse(owner.openTopic(999, from: route, current: .current(h.session)))
        XCTAssertTrue(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        let post = try XCTUnwrap(owner.posts.selection)
        XCTAssertEqual(post.route.id, 101)
        XCTAssertFalse(owner.openPost(post.route, from: route, current: .current(h.session)))
        XCTAssertFalse(owner.openTopic(201, from: route, current: .current(h.session)))
        XCTAssertTrue(owner.posts.close(id: post.id))
        XCTAssertTrue(owner.openTopic(201, from: route, current: .current(h.session)))
        XCTAssertEqual(owner.topics.selection?.topicID, 201)
        XCTAssertFalse(owner.openPost(post.route, from: route, current: .current(h.session)))
    }
    func testRepeatedOpenDoesNotReplaceActiveCollection() async throws {
        let h = try ProfileFavoritesHarness(); await h.login()
        let (owner, route) = try opened(h)
        XCTAssertFalse(owner.open(.current(h.session)))
        XCTAssertEqual(owner.route?.id, route.id)
    }
    func testOldDismissalAndOldRowCannotDismissOrOpenSuccessor() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, first) = try opened(h), binding = owner.binding(for: first)
        XCTAssertTrue(owner.close(first.id))
        XCTAssertTrue(owner.open(.current(h.session)))
        let second = try XCTUnwrap(owner.route)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(binding.wrappedValue)
        binding.wrappedValue = nil
        XCTAssertEqual(owner.route?.id, second.id)
        XCTAssertFalse(owner.openPost(.init(id: 101, generation: .legacySquare), from: first, current: .current(h.session)))
        XCTAssertFalse(owner.openTopic(201, from: first, current: .current(h.session)))
        XCTAssertTrue(owner.openTopic(201, from: second, current: .current(h.session)))
    }
    func testPopCollectionRetiresBothKindsOfNestedDetail() async throws {
        for post in [true, false] {
            let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
            let (owner, route) = try opened(h)
            if post { XCTAssertTrue(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session))) }
            else { XCTAssertTrue(owner.openTopic(201, from: route, current: .current(h.session))) }
            let oldPost = owner.posts.selection, oldTopic = owner.topics.selection
            owner.binding(for: route).wrappedValue = nil
            XCTAssertNil(owner.route); XCTAssertNil(owner.posts.selection); XCTAssertNil(owner.topics.selection)
            if let oldPost { XCTAssertFalse(oldPost.isCurrent) }
            if let oldTopic { XCTAssertFalse(oldTopic.isCurrent) }
        }
    }
    func testAccountEpochRoleViewerAndDependencyChangesRejectCapturedRowsImmediately() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, route) = try opened(h), original = route.access
        let other = try ProfileFavoritesHarness(); await other.login()
        for mutation in ["account", "epoch", "role", "viewer", "dependency"] {
            let identity = original.key.identity
            let id = mutation == "account" ? 82 : 81
            let changed = try XCTUnwrap(ProfileSettingsFavoritesAccess(accountID: id,
                identity: .init(accountID: id, epoch: identity.epoch + (mutation == "epoch" ? 1 : 0),
                    role: mutation == "role" ? "merchant" : identity.role),
                viewerRevision: original.key.viewerRevision + (mutation == "viewer" ? 1 : 0),
                reader: mutation == "dependency" ? other.session.profileFavoritesReader : original.reader))
            XCTAssertFalse(owner.accepts(route, current: changed), mutation)
            XCTAssertFalse(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: changed), mutation)
            XCTAssertFalse(owner.openTopic(201, from: route, current: changed), mutation)
        }
        let accountID = try XCTUnwrap(original.key.identity.accountID)
        let gateA = SettingsFavoritesGateStub()
        let gateB = SettingsFavoritesGateStub(scope: gateA.scope)
        func access(_ gate: SettingsFavoritesGateStub) -> ProfileSettingsFavoritesAccess? {
            ProfileSettingsFavoritesAccess(accountID: accountID, identity: original.key.identity,
                viewerRevision: original.key.viewerRevision, reader: original.reader, removal: original.removal, communityGate: gate)
        }
        let accessA = try XCTUnwrap(access(gateA))
        let accessB = try XCTUnwrap(access(gateB))
        XCTAssertEqual(accessA.key.gate, ObjectIdentifier(gateA))
        XCTAssertEqual(accessA.key.gateScope, gateA.scope)
        XCTAssertEqual(accessB.key.gateScope, gateA.scope)
        XCTAssertNotEqual(accessA.key, accessB.key)
        let gated = ProfileSettingsFavoritesOwner()
        gated.appear(current: accessA, foreground: true)
        XCTAssertTrue(gated.open(accessA))
        let gatedRoute = try XCTUnwrap(gated.route)
        XCTAssertTrue(gated.openPost(.init(id: 101, generation: .legacySquare), from: gatedRoute, current: accessA))
        XCTAssertTrue(gated.posts.close(id: try XCTUnwrap(gated.posts.selection?.id)))
        gated.setForeground(false)
        XCTAssertFalse(gated.openTopic(201, from: gatedRoute, current: accessA))
        gated.setForeground(true)
        gated.synchronize(accessB)
        XCTAssertNil(gated.route)
        XCTAssertFalse(gated.accepts(gatedRoute, current: accessB))
        XCTAssertFalse(gated.openPost(.init(id: 101, generation: .legacySquare), from: gatedRoute, current: accessB))
        XCTAssertFalse(gated.openTopic(201, from: gatedRoute, current: accessB))
        let gateA2 = SettingsFavoritesGateStub(scope: gateA.scope)
        let accessA2 = try XCTUnwrap(access(gateA2))
        XCTAssertNotEqual(accessA.key, accessA2.key)
        gated.synchronize(accessA2)
        XCTAssertTrue(gated.open(accessA2))
        XCTAssertNotEqual(gated.route?.id, gatedRoute.id)
        XCTAssertFalse(gated.openTopic(201, from: gatedRoute, current: accessA2))
        XCTAssertFalse(gated.openPost(.init(id: 101, generation: .legacySquare), from: gatedRoute, current: accessA2))
    }
    func testApprovalRevocationRetiresCollectionAndSelection() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, route) = try opened(h)
        XCTAssertTrue(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        let post = try XCTUnwrap(owner.posts.selection)
        h.grants.list?.revoke()
        XCTAssertFalse(owner.accepts(route, current: .current(h.session)))
        owner.synchronize(.current(h.session))
        XCTAssertNil(owner.route); XCTAssertFalse(post.isCurrent)
        XCTAssertTrue(owner.open(.current(h.session)))
        XCTAssertFalse(try XCTUnwrap(owner.route).access.key.configured)
    }
    func testLogoutAndReauthenticationCannotReviveOldCollection() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, route) = try opened(h)
        XCTAssertTrue(owner.openTopic(201, from: route, current: .current(h.session)))
        let topic = try XCTUnwrap(owner.topics.selection)
        await h.session.logout(); owner.synchronize(.current(h.session))
        XCTAssertNil(owner.route); XCTAssertFalse(topic.isCurrent)
        h.wire.account = 82; h.grants.list = nil; await h.login()
        owner.synchronize(.current(h.session))
        XCTAssertTrue(owner.open(.current(h.session)))
        XCTAssertFalse(owner.openTopic(201, from: route, current: .current(h.session)))
    }
    func testBackgroundRetiresDetailButPreservesCollectionForExplicitReturn() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, route) = try opened(h)
        XCTAssertTrue(owner.openTopic(201, from: route, current: .current(h.session)))
        let topic = try XCTUnwrap(owner.topics.selection)
        owner.setForeground(false)
        XCTAssertEqual(owner.route?.id, route.id); XCTAssertFalse(topic.isCurrent)
        XCTAssertFalse(owner.openTopic(201, from: route, current: .current(h.session)))
        owner.setForeground(true)
        XCTAssertTrue(owner.openTopic(201, from: route, current: .current(h.session)))
        XCTAssertNotEqual(owner.topics.selection?.id, topic.id)
    }
    func testClosingSettingsIsPermanentForRetainedOwnerAndCallbacks() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, route) = try opened(h)
        owner.retire(); owner.appear(current: .current(h.session), foreground: true)
        owner.setForeground(true); owner.synchronize(.current(h.session))
        XCTAssertNil(owner.route); XCTAssertFalse(owner.open(.current(h.session)))
        XCTAssertFalse(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        XCTAssertFalse(owner.openTopic(201, from: route, current: .current(h.session)))
    }
    func testHeldPostReplyAfterCollectionPopCannotReachNewRoute() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); try await loadBoth(h)
        let (owner, route) = try opened(h)
        XCTAssertTrue(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        let selection = try XCTUnwrap(owner.posts.selection), reader = h.session.makeProfileFavoriteDetailReader(selection)
        h.wire.holdPath = "info"
        let held = expectation(description: "Old Settings post detail"); h.wire.onHeld = { held.fulfill() }
        let task = Task { try await reader.squareDetail(id: 101) }
        await fulfillment(of: [held], timeout: 2)
        XCTAssertTrue(owner.close(route.id)); XCTAssertTrue(owner.open(.current(h.session)))
        let next = try XCTUnwrap(owner.route)
        h.wire.finish(body: #"{"code":200,"data":{"id":101,"memberId":991,"content":"Old reply"}}"#)
        do { _ = try await task.value; XCTFail("A retired detail must reject the late response") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(owner.route?.id, next.id); XCTAssertNil(owner.posts.selection)
    }
    func testSettingsCollectionUsesOriginalDetailAndKeepsOwnerWhenCovered() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); h.wire.requests = []
        let owner = ProfileSettingsFavoritesOwner()
        let root = NavigationStack {
            Form { ProfileSettingsFavoritesEntry(session: h.session, owner: owner) }
                .modifier(ProfileSettingsFavoritesNavigation(session: h.session, owner: owner))
        }.modifier(ProfileSettingsFavoritesLifecycle(session: h.session, owner: owner))
            .environment(\.scenePhase, .active)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<100 where owner.route == nil {
            if owner.open(.current(h.session)) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let route = try XCTUnwrap(owner.route)
        for _ in 0..<100 where !h.wire.paths.contains("list") { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(h.wire.paths.contains("list"))
        XCTAssertTrue(owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session)))
        let selection = try XCTUnwrap(owner.posts.selection)
        for _ in 0..<100 where !h.wire.paths.contains("info") { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(h.wire.paths.contains("info")); XCTAssertTrue(selection.isCurrent)
        XCTAssertEqual(owner.route?.id, route.id)
        XCTAssertTrue(owner.posts.close(id: selection.id))
        XCTAssertTrue(owner.accepts(route, current: .current(h.session)))
        owner.binding(for: route).wrappedValue = nil
        XCTAssertNil(owner.route); XCTAssertFalse(selection.isCurrent)
        XCTAssertTrue(owner.open(.current(h.session)))
    }
}

@MainActor private final class SettingsFavoritesGateStub: SquareCommunityFeatureReading {
    var scope: UUID
    init(scope: UUID = UUID()) { self.scope = scope }
    func communityFeatures() async throws -> SquareCommunityFeatures {
        SquareCommunityFeatures(read: true, write: false)
    }
}
