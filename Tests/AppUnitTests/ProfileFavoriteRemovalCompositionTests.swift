import XCTest
@testable import Questify

@MainActor final class ProfileFavoriteRemovalCompositionTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        let base = ProfileFavoritesWire()
        var marked = true, writes = 0
        var unreadableAfterWrite = false, unauthorizedRead = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if request.url?.lastPathComponent == "bookmark" {
                writes += 1; marked = false; base.posts = []
                return (Data(#"{"code":200}"#.utf8), 200)
            }
            if request.url?.lastPathComponent == "info" {
                if unauthorizedRead { return (Data(#"{"code":401}"#.utf8), 401) }
                if unreadableAfterWrite && writes > 0 { throw URLError(.timedOut) }
                return (Data("{\"code\":200,\"data\":{\"id\":101,\"isBookmarked\":\(marked ? 1 : 0)}}".utf8), 200)
            }
            return try await base.send(request)
        }
    }
    @MainActor private final class Grants {
        var enabled = true
        var access: ProfileFavoriteRemovalAccess?
        func select(_ context: RuntimeDependencyContext, _ scope: UUID) -> [ProfileFavoriteRemovalAccess] {
            guard enabled else { return [] }
            if access == nil {
                access = try? .init(context: context, collectionScope: scope,
                    approval: .init(endpoint: .init(baseURL: context.baseURL, namespace: context.session.namespace,
                        accountID: context.session.accountID, paths: ProfileFavoriteRemovalApproval.paths),
                        identity: .init(accountID: context.session.accountID, epoch: context.session.epoch, role: context.role),
                        postID: 101, expiresAt: Date(timeIntervalSince1970: 4102444800)))
            }
            return access.map { [$0] } ?? []
        }
    }
    private struct Fixture { let session: AppSession; let wire: Wire; let grants: Grants }
    private func fixture(enabled: Bool = true) async throws -> Fixture {
        let wire = Wire(), reads = ProfileFavoritesGrants(), grants = Grants(), vault = ProfileFavoritesVault()
        grants.enabled = enabled
        let base = "https://favorites.example/native"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base, approvedBaseURLs: [.china: [base]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.favorite-removal", realm: "synthetic")
        var root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: UserDefaults(suiteName: "favorite-removal-" + UUID().uuidString)!, tokenStore: { _ in vault }),
            makeTransport: { wire }, profileFavoritesReadAccess: { reads.selectList($0) })
        root.profileFavoriteRemovalAccesses = { grants.select($0, $1) }
        let session = root.makeSession()
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        return .init(session: session, wire: wire, grants: grants)
    }
    private func post() throws -> SquarePost {
        try JSONDecoder().decode(SquarePost.self, from: Data(#"{"id":101,"memberId":991,"content":"Saved post"}"#.utf8)).qualified(as: .legacySquare)
    }
    func testDefaultNoWriteCapabilityKeepsFactoryNil() async throws {
        let h = try await fixture(enabled: false)
        XCTAssertNil(h.session.makeProfileFavoriteRemovalController(scope: h.session.profileFavoritesReader.scope))
        XCTAssertEqual(h.wire.writes, 0)
    }
    func testStableNormalEntryUsesSameControllerAndExistingConfirmReadback() async throws {
        let h = try await fixture(), scope = h.session.profileFavoritesReader.scope
        let controller = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope))
        XCTAssertTrue(controller === h.session.makeProfileFavoriteRemovalController(scope: scope))
        let id = try XCTUnwrap(controller.begin(post: post(), collectionScope: scope))
        await controller.prepare(id)
        XCTAssertEqual(controller.phase, .reviewed); XCTAssertEqual(h.wire.writes, 0)
        await controller.confirm(try XCTUnwrap(controller.review))
        XCTAssertEqual(controller.phase, .removed); XCTAssertEqual(h.wire.writes, 1)
    }
    func testRevocationAfterReviewPreventsWrite() async throws {
        let h = try await fixture(), scope = h.session.profileFavoritesReader.scope
        let controller = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope))
        let id = try XCTUnwrap(controller.begin(post: post(), collectionScope: scope))
        await controller.prepare(id)
        let review = try XCTUnwrap(controller.review); h.grants.access?.revoke()
        await controller.confirm(review)
        XCTAssertEqual(h.wire.writes, 0)
        XCTAssertNil(h.session.makeProfileFavoriteRemovalController(scope: scope))
    }
    func testSettingsCapturesSameOptionalController() async throws {
        let h = try await fixture(), scope = h.session.profileFavoritesReader.scope
        let controller = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope))
        let access = try XCTUnwrap(ProfileSettingsFavoritesAccess.current(h.session))
        XCTAssertTrue(access.removal === controller)
        XCTAssertEqual(access.key.removal, ObjectIdentifier(controller))
    }
    func testLogoutInvalidatesRetainedController() async throws {
        let h = try await fixture(), scope = h.session.profileFavoritesReader.scope
        let controller = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope)), saved = try post()
        await h.session.logout()
        XCTAssertFalse(controller.isAvailable(post: saved, collectionScope: scope))
        XCTAssertNil(h.session.makeProfileFavoriteRemovalController(scope: scope))
        XCTAssertEqual(h.wire.writes, 0)
    }
    func testObservedSelectorRemovalRetiresReviewBeforeReinstall() async throws {
        let h = try await fixture(), scope = h.session.profileFavoritesReader.scope
        let first = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope))
        let id = try XCTUnwrap(first.begin(post: post(), collectionScope: scope)); await first.prepare(id)
        let oldReview = try XCTUnwrap(first.review)
        h.grants.enabled = false
        XCTAssertNil(h.session.makeProfileFavoriteRemovalController(scope: scope))
        XCTAssertEqual(first.phase, .idle)
        h.grants.enabled = true
        let next = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope))
        XCTAssertFalse(first === next)
        await first.confirm(oldReview)
        XCTAssertEqual(h.wire.writes, 0)
    }

    func testSettingsReturnCanRecoverAppliedRemovalMissingFromFreshCollection() async throws {
        let h = try await fixture(), owner = ProfileSettingsFavoritesOwner()
        owner.appear(current: .current(h.session), foreground: true)
        XCTAssertTrue(owner.open(.current(h.session)))
        let first = try XCTUnwrap(owner.route), reader = first.access.reader
        let model = AccountCollectionPostsScreenModel()
        await model.refresh(reader: reader, pageSize: 10)
        let saved = try XCTUnwrap(model.state.visibleRows(scope: reader.scope).first)
        let controller = try XCTUnwrap(first.access.removal)
        let id = try XCTUnwrap(controller.begin(post: saved, collectionScope: reader.scope))
        await controller.prepare(id); h.wire.unreadableAfterWrite = true
        await controller.confirm(try XCTUnwrap(controller.review))
        XCTAssertEqual(controller.phase, .unknown); controller.retire(id)
        XCTAssertTrue(owner.close(first.id)); XCTAssertTrue(owner.open(.current(h.session)))
        let returned = try XCTUnwrap(owner.route), current = try XCTUnwrap(returned.access.removal)
        XCTAssertTrue(current === controller)
        await model.refresh(reader: returned.access.reader, pageSize: 10)
        XCTAssertTrue(model.state.visibleRows(scope: reader.scope).isEmpty)
        XCTAssertEqual(current.recoveryAvailability(collectionScope: reader.scope), .pending([saved.id]))
        let recovery = try XCTUnwrap(current.beginRecovery(postID: saved.id, collectionScope: reader.scope))
        h.wire.unreadableAfterWrite = false; await current.reconcile(recovery)
        XCTAssertEqual(current.phase, .removed); XCTAssertEqual(h.wire.writes, 1)
        let completion = ProfileFavoriteRemovalPresentation(id: recovery, postID: saved.id, scope: reader.scope)
        let refreshed = expectation(description: "Current Settings collection refreshed")
        completion.finish(controller: current,
            isCurrent: { owner.accepts(returned, current: .current(h.session)) },
            onRemoved: { await model.refresh(reader: reader, pageSize: 10); refreshed.fulfill() })
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertTrue(model.state.visibleRows(scope: reader.scope).isEmpty)
        XCTAssertEqual(current.recoveryAvailability(collectionScope: reader.scope), .pending([]))
    }
    func testMatchingUnauthorizedReadExpiresNormalSessionWithoutWrite() async throws {
        let h = try await fixture(), scope = h.session.profileFavoritesReader.scope
        let controller = try XCTUnwrap(h.session.makeProfileFavoriteRemovalController(scope: scope))
        h.wire.unauthorizedRead = true
        let id = try XCTUnwrap(controller.begin(post: post(), collectionScope: scope))
        await controller.prepare(id)
        XCTAssertNil(h.session.account); XCTAssertNil(h.session.makeProfileFavoriteRemovalController(scope: scope))
        XCTAssertEqual(h.wire.writes, 0)
    }

}
