import XCTest
@testable import Questify

@MainActor final class SessionMessagingHomeReaderLifetimeTests: XCTestCase {
    private func fixture() throws -> (AppSessionContainer, IntegratedNativeAcceptanceFixture, AppSession) {
        let container = AppSessionContainer(arguments: [IntegratedNativeAcceptanceFixture.flag, "ready"])
        let wire = try XCTUnwrap(container.integratedAcceptance)
        let defaults = try XCTUnwrap(wire.defaults), suite = wire.suiteName
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (container, wire, try XCTUnwrap(container.session))
    }
    private func login(_ session: AppSession) async {
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    func testSameIssuanceRerenderAndNavigationReturnKeepLoadedListWithoutRead() async throws {
        let (container, wire, session) = try fixture()
        _ = container
        await login(session)
        let owner = SessionMessagingHomeReaderOwner(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let reader = owner.reader(for: session)
        let token = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        await model.perform(token) { try await reader.messagingConversations() }
        XCTAssertEqual(model.value?.map(\.id), [901])
        let reads = wire.ledger.count
        let renderReader = owner.reader(for: session)
        XCTAssertTrue(renderReader === reader)
        XCTAssertNil(model.updateInput(reader: renderReader, refreshRevision: 0, appearance: model.appearance))
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.value?.map(\.id), [901])
        model.disappear()
        XCTAssertNil(model.appear(reader: owner.reader(for: session), refreshRevision: 0))
        XCTAssertEqual(model.value?.map(\.id), [901])
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(wire.ledger.count, reads)
        XCTAssertEqual(wire.ledger.filter { $0.route.hasPrefix("history.") }.map(\.route), ["history.conversations"])
    }
    func testRealReissuanceStillClearsSnapshotAndRequiresFreshRead() async throws {
        let (container, wire, session) = try fixture()
        _ = container
        await login(session)
        let owner = SessionMessagingHomeReaderOwner(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let old = owner.reader(for: session)
        let token = try XCTUnwrap(model.appear(reader: old, refreshRevision: 0))
        await model.perform(token) { try await old.messagingConversations() }
        let context = try XCTUnwrap(session.currentRuntimeDependencyContext)
        let approval = try XCTUnwrap(wire.makeComposition().messagingHistoryReadApproval(context))
        approval.revoke()
        XCTAssertNil(old.identity)
        let fresh = owner.reader(for: session)
        XCTAssertFalse(fresh === old)
        let next = try XCTUnwrap(model.updateInput(reader: fresh, refreshRevision: 0, appearance: model.appearance))
        XCTAssertNil(model.value)
        XCTAssertTrue(model.isLoading)
        await model.perform(next) { try await fresh.messagingConversations() }
        XCTAssertEqual(model.value?.map(\.id), [901])
        XCTAssertEqual(wire.ledger.filter { $0.route.hasPrefix("history.") }.map(\.route), ["history.conversations", "history.conversations"])
        let count = wire.ledger.count
        do { _ = try await old.messagingConversations(); XCTFail("Retired reader dispatched") } catch {}
        XCTAssertEqual(wire.ledger.count, count)
    }
    func testLogoutSameAccountReloginAndDifferentSessionDoNotReuseAuthority() async throws {
        let (container, _, session) = try fixture()
        _ = container
        await login(session)
        let owner = SessionMessagingHomeReaderOwner(), old = owner.reader(for: session)
        await session.logout()
        XCTAssertNil(old.identity)
        XCTAssertFalse(owner.reader(for: session) === old)
        await login(session)
        XCTAssertFalse(owner.reader(for: session) === old)
        XCTAssertNil(old.identity)
        let (otherContainer, _, other) = try fixture()
        _ = otherContainer
        await login(other)
        XCTAssertFalse(owner.reader(for: other) === owner.reader(for: session))
    }
    func testExplicitRefreshRemainsAReadEvenWithStableHostReader() async throws {
        let (container, wire, session) = try fixture()
        _ = container
        await login(session)
        let owner = SessionMessagingHomeReaderOwner(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let reader = owner.reader(for: session)
        let first = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        await model.perform(first) { try await reader.messagingConversations() }
        let input = MessagingReadScreenInput(reader: owner.reader(for: session), refreshRevision: 0)
        let refresh = try XCTUnwrap(model.prepareRefresh(appearance: model.appearance, input: input))
        await model.perform(refresh) { try await reader.messagingConversations() }
        XCTAssertEqual(wire.ledger.filter { $0.route.hasPrefix("history.") }.count, 2)
        XCTAssertEqual(model.value?.map(\.id), [901])
    }
}
