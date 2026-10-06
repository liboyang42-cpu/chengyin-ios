import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryImageCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.com/native")!
    private final class Grant { var enabled = true, picker = false }
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], role = "player", held = false
        var started: XCTestExpectation?, continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/phone") == true { return (Data("{\"code\":200,\"token\":\"synthetic-7\",\"data\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            if request.url?.path.hasSuffix("/userInfo") == true { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200) }
            if held { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            return (Data(#"{"code":200,"url":"https://example.com/story/exact%20reference.jpg"}"#.utf8), 200)
        }
        func finish401() { let old = continuation; continuation = nil; old?.resume(returning: (Data(), 401)) }
    }
    private func root(_ wire: Wire, _ grant: Grant) throws -> AppCompositionRoot {
        let suite = "story-image-composition-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.story-image", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }, projectStoryImageUploadApproval: { context in
            guard grant.enabled else { return nil }
            return try? .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, approvedOrigins: ["https://example.com"], nativePicker: grant.picker)
        }, makeProjectStoryImageUploadTransport: { wire })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func image(_ owner: ProjectEditSession) throws -> RetainedSelectedImage {
        try ProjectStoryImageSynthetic(session: owner, currentSession: { owner }).picked
    }
    func testDefaultFactoryIsAbsentAndExplicitPersonalApprovalKeepsPickerSeparate() async throws {
        let wire = Wire(), grant = Grant(); grant.enabled = false
        let session = try root(wire, grant).makeSession(); await login(session); wire.requests = []
        XCTAssertNil(session.projectEditor(product: .city).storyImageSource); XCTAssertTrue(wire.requests.isEmpty)
        session.withProjectEditConfigurationChange { grant.enabled = true }
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.storyImageSource)
        XCTAssertFalse(source.permitsPicker(session: owner)); XCTAssertNil(session.projectEditor(product: .city, owner: .merchant).storyImageSource)
        _ = try await source.upload(image(owner), attemptID: UUID(), session: owner)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests[0].url, base.appendingPathComponent(ProjectStoryImageUploadClient.path))
        XCTAssertTrue(ProjectStoryImageCompositionRoute.accepts(wire.requests[0], baseURL: base))
        XCTAssertNil(editor.ownedCoverSource); XCTAssertNil(editor.releasePublicationSource)
    }
    func testQueuedActualSourceAfterGrantABAHasZeroUploadDispatch() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let old = session.projectEditor(product: .city), owner = try XCTUnwrap(old.session), source = try XCTUnwrap(old.storyImageSource), picked = try image(owner)
        let queued = Task { try await source.upload(picked, attemptID: UUID(), session: owner) }
        session.withProjectEditConfigurationChange { grant.enabled = false; grant.enabled = true }
        let before = wire.requests.count
        do { _ = try await queued.value; XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, before); XCTAssertFalse(source.isCurrent(session: owner))
        XCTAssertEqual(try XCTUnwrap(session.projectEditor(product: .city).session).ownerKey, owner.ownerKey)
    }
    func testHeldCloneResponseAfterConfigurationABAIsRejectedWithoutBorrowingNewGrant() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.storyImageSource), picked = try image(owner)
        wire.held = true; wire.started = expectation(description: "bounded actual upload clone")
        let pending = Task { try await source.upload(picked, attemptID: UUID(), session: owner) }
        await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 3)
        session.withProjectEditConfigurationChange { grant.enabled = false; grant.enabled = true }; wire.finish401()
        do { _ = try await pending.value; XCTFail() } catch { XCTAssertFalse(error as? APIError == .unauthorized) }
        XCTAssertEqual(session.account?.id, 7); XCTAssertFalse(source.isCurrent(session: owner))
    }
    func testRoleABARetiresOriginalFactoryAndPreservesDurableOwnerNamespace() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.storyImageSource)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        let count = wire.requests.count
        do { _ = try await source.upload(image(owner), attemptID: UUID(), session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, count); XCTAssertFalse(source.isCurrent(session: owner))
        XCTAssertEqual(try XCTUnwrap(session.projectEditor(product: .city).session).ownerKey, owner.ownerKey)
    }
    func testOuterRouteRequiresExactMultipartAndCloneSeesRevocation() async throws {
        let wire = Wire(), grant = Grant(), composition = try root(wire, grant), session = composition.makeSession(); await login(session)
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session)
        _ = try await XCTUnwrap(editor.storyImageSource).upload(image(owner), attemptID: UUID(), session: owner)
        let valid = try XCTUnwrap(wire.requests.last), fence = composition.transport()
        fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        fence.projectEditConfigurationRevision = { 1 }
        fence.projectStoryImageUploadApproval = { context in
            grant.enabled ? try? .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: 7, approvedOrigins: ["https://example.com"]) : nil
        }
        let clone = fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        wire.requests = []; _ = try await clone.send(valid)
        var wrong = valid; wrong.url = URL(string: valid.url!.absoluteString + "?owner=7")
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        wrong = valid; wrong.httpBody = Data("owner=7&bizType=image_free".utf8)
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        wrong = valid; wrong.url = base.appendingPathComponent("api/topic/cover/upload")
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        grant.enabled = false
        do { _ = try await clone.send(valid); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
}
#endif
