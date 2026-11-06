import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileFavoriteRemovalAccessTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player",
                         market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: "https://profile.example/native")!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: "synthetic-token"))
    }
    private func approval(_ context: RuntimeDependencyContext) throws -> ProfileFavoriteRemovalApproval {
        try .init(endpoint: .init(baseURL: context.baseURL, namespace: "synthetic", accountID: 7,
                                 paths: ProfileFavoriteRemovalApproval.paths),
                  identity: .init(accountID: 7, epoch: 1, role: "player"), postID: 101,
                  expiresAt: Date(timeIntervalSince1970: 200))
    }
    func testExactContextScopePostAndExpiry() throws {
        let context = try context(), scope = UUID()
        let access = try ProfileFavoriteRemovalAccess(context: context, collectionScope: scope, approval: approval(context))
        XCTAssertTrue(access.matches(context, collectionScope: scope, postID: 101, now: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(access.matches(context, collectionScope: UUID(), postID: 101, now: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(access.matches(context, collectionScope: scope, postID: 102, now: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(access.matches(context, collectionScope: scope, postID: 101, now: Date(timeIntervalSince1970: 200)))
    }
    func testRevocationCannotBeReversedBySameContext() throws {
        let context = try context(), scope = UUID()
        let access = try ProfileFavoriteRemovalAccess(context: context, collectionScope: scope, approval: approval(context))
        access.revoke()
        XCTAssertFalse(access.matches(context, collectionScope: scope, postID: 101, now: Date(timeIntervalSince1970: 100)))
    }
    func testChangedIdentityCannotReuseGrant() throws {
        let first = try context(), grant = try approval(first)
        for changed in [try context(account: 8), try context(epoch: 2), try context(role: "merchant")] {
            XCTAssertThrowsError(try ProfileFavoriteRemovalAccess(context: changed, collectionScope: UUID(), approval: grant))
        }
    }
    func testNewAccessHasDifferentRevision() throws {
        let context = try context(), scope = UUID(), grant = try approval(context)
        let first = try ProfileFavoriteRemovalAccess(context: context, collectionScope: scope, approval: grant)
        let second = try ProfileFavoriteRemovalAccess(context: context, collectionScope: scope, approval: grant)
        XCTAssertNotEqual(first.revision, second.revision)
    }
    func testOnlyExplicitRemoveAndReadbackBodiesAreAccepted() throws {
        let base = URL(string: "https://profile.example/native")!
        let requestID = UUID().uuidString
        func request(_ path: String, _ fields: [String: String]) throws -> URLRequest {
            try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic-token")
        }
        XCTAssertNotNil(ProfileFavoriteRemovalRoute(request: try request("api/creativesquare/info", ["id": "101"]), baseURL: base))
        XCTAssertNotNil(ProfileFavoriteRemovalRoute(request: try request("api/creativesquare/bookmark", ["id": "101", "bookmark": "0", "request_id": requestID]), baseURL: base))
        for fields in [["id": "101"], ["id": "101", "bookmark": "1", "request_id": requestID],
                       ["id": "101", "bookmark": "0", "request_id": "invalid"],
                       ["id": "101", "bookmark": "0", "request_id": requestID, "member_id": "7"]] {
            XCTAssertNil(ProfileFavoriteRemovalRoute(request: try request("api/creativesquare/bookmark", fields), baseURL: base))
        }
        XCTAssertNil(ProfileFavoriteRemovalRoute(request: try request("api/topic/like", ["id": "101"]), baseURL: base))
    }

}

@MainActor final class ProfileFavoriteRemovalTransportTests: XCTestCase {
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var onSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); onSend?()
            return (Data(#"{"code":200}"#.utf8), 200)
        }
    }
    private final class State {
        var context: RuntimeDependencyContext?
        var scope: UUID? = UUID()
        var accesses: [ProfileFavoriteRemovalAccess] = []
    }
    private func fixture() throws -> (State, Wire, ProfileFavoriteRemovalTransport, URLRequest) {
        let state = State(), wire = Wire(), base = URL(string: "https://profile.example/native")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token"))
        state.context = context
        let approval = try ProfileFavoriteRemovalApproval(endpoint: .init(baseURL: base, namespace: "synthetic",
            accountID: 7, paths: ProfileFavoriteRemovalApproval.paths), identity: .init(accountID: 7, epoch: 1, role: "player"),
            postID: 101, expiresAt: Date(timeIntervalSince1970: 200))
        state.accesses = [try .init(context: context, collectionScope: state.scope!, approval: approval)]
        let transport = ProfileFavoriteRemovalTransport(accesses: state.accesses, collectionScope: state.scope!,
            underlying: wire, current: { state.context }, currentScope: { state.scope }, select: { _, _ in state.accesses },
            now: { Date(timeIntervalSince1970: 100) })
        let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/creativesquare/bookmark"),
            fields: ["id": "101", "bookmark": "0", "request_id": UUID().uuidString], token: "synthetic-token")
        return (state, wire, transport, request)
    }
    func testExactSuppliedAccessDispatchesOnlyRequestedBody() async throws {
        let (_, wire, transport, request) = try fixture()
        _ = try await transport.send(request)
        XCTAssertEqual(wire.requests, [request])
    }
    func testRevokedOrMissingSelectorBlocksDispatch() async throws {
        for revoke in [true, false] {
            let (state, wire, transport, request) = try fixture()
            if revoke { state.accesses[0].revoke() } else { state.accesses = [] }
            do { _ = try await transport.send(request); XCTFail() } catch {}
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testReplacementSameGrantCannotReuseOldTransport() async throws {
        let (state, wire, transport, request) = try fixture(), original = try XCTUnwrap(state.accesses.first)
        state.accesses = [try .init(context: state.context!, collectionScope: state.scope!, approval: original.approval)]
        do { _ = try await transport.send(request); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testWrongTokenOrCollectionCannotDispatch() async throws {
        for token in [true, false] {
            let (state, wire, transport, original) = try fixture(); var request = original
            if token { request.setValue("other-token", forHTTPHeaderField: "Authorization") } else { state.scope = UUID() }
            do { _ = try await transport.send(request); XCTFail() } catch {}
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testRevocationDuringResponseNeverReturnsSuccess() async throws {
        let (state, wire, transport, request) = try fixture()
        wire.onSend = { state.accesses[0].revoke() }
        do { _ = try await transport.send(request); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testDuplicateCurrentGrantsCannotAuthorizeDispatch() async throws {
        let (state, wire, transport, request) = try fixture()
        state.accesses.append(state.accesses[0])
        do { _ = try await transport.send(request); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
