import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryAudioCompositionTests: XCTestCase {
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
            return (Data(#"{"code":200,"url":"https://example.com/story/exact%20reference.m4a"}"#.utf8), 200)
        }
        func finish401() { let old = continuation; continuation = nil; old?.resume(returning: (Data(), 401)) }
    }
    private func root(_ wire: Wire, _ grant: Grant, imageOnly: Bool = false) throws -> AppCompositionRoot {
        let suite = "story-audio-composition-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.story-audio", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }, projectStoryAudioUploadApproval: { context in
            guard grant.enabled, !imageOnly else { return nil }
            return try? .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, approvedOrigins: ["https://example.com"], nativePicker: grant.picker)
        }, makeProjectStoryAudioUploadTransport: { wire }, projectStoryImageUploadApproval: { context in
            guard imageOnly else { return nil }
            return try? .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, approvedOrigins: ["https://example.com"], nativePicker: true)
        }, makeProjectStoryImageUploadTransport: { wire })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func audio(_ owner: ProjectEditSession) throws -> ProjectStorySelectedAudio {
        try ProjectStoryAudioSynthetic(session: owner, currentSession: { owner }).picked
    }
    func testDefaultFactoryIsAbsentAndExplicitPersonalApprovalKeepsPickerSeparate() async throws {
        let wire = Wire(), grant = Grant(); grant.enabled = false
        let session = try root(wire, grant).makeSession(); await login(session); wire.requests = []
        XCTAssertNil(session.projectEditor(product: .city).storyAudioSource); XCTAssertTrue(wire.requests.isEmpty)
        session.withProjectEditConfigurationChange { grant.enabled = true }
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.storyAudioSource)
        XCTAssertFalse(source.permitsPicker(session: owner)); XCTAssertNil(session.projectEditor(product: .city, owner: .merchant).storyAudioSource)
        _ = try await source.upload(audio(owner), attemptID: UUID(), session: owner)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests[0].url, base.appendingPathComponent(ProjectStoryAudioUploadClient.path))
        XCTAssertTrue(ProjectStoryAudioCompositionRoute.accepts(wire.requests[0], baseURL: base))
        XCTAssertNil(editor.storyImageSource); XCTAssertNil(editor.ownedCoverSource); XCTAssertNil(editor.releasePublicationSource)
    }
    func testImageOnlyApprovalCannotAuthorizeAudioFactoryOrOuterBody() async throws {
        let wire = Wire(), grant = Grant(), composition = try root(wire, grant, imageOnly: true), session = composition.makeSession()
        await login(session); let editor = session.projectEditor(product: .city)
        XCTAssertNotNil(editor.storyImageSource); XCTAssertNil(editor.storyAudioSource)
        let owner = try XCTUnwrap(editor.session), generated = try ProjectStoryAudioSynthetic(session: owner, currentSession: { owner })
        _ = try await generated.upload(generated.picked, attemptID: UUID(), session: owner)
        let audioRequest = try XCTUnwrap(generated.wire.requests.last)
        // Use the actual source URL namespace of this deployment, leaving the audio multipart exact.
        var request = audioRequest; request.url = base.appendingPathComponent(ProjectStoryAudioUploadClient.path)
        request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
        let outer = composition.transport(); outer.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        outer.projectEditConfigurationRevision = { 1 }
        let before = wire.requests.count
        do { _ = try await outer.send(request); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testQueuedActualSourceAfterGrantABAHasZeroUploadDispatch() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let old = session.projectEditor(product: .city), owner = try XCTUnwrap(old.session), source = try XCTUnwrap(old.storyAudioSource), picked = try audio(owner)
        let queued = Task { try await source.upload(picked, attemptID: UUID(), session: owner) }
        session.withProjectEditConfigurationChange { grant.enabled = false; grant.enabled = true }
        let before = wire.requests.count
        do { _ = try await queued.value; XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, before); XCTAssertFalse(source.isCurrent(session: owner))
        XCTAssertEqual(try XCTUnwrap(session.projectEditor(product: .city).session).ownerKey, owner.ownerKey)
    }
    func testHeldCloneResponseAfterConfigurationABAIsRejectedWithoutBorrowingNewGrant() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.storyAudioSource), picked = try audio(owner)
        wire.held = true; wire.started = expectation(description: "bounded actual upload clone")
        let pending = Task { try await source.upload(picked, attemptID: UUID(), session: owner) }
        await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 3)
        session.withProjectEditConfigurationChange { grant.enabled = false; grant.enabled = true }; wire.finish401()
        do { _ = try await pending.value; XCTFail() } catch { XCTAssertFalse(error as? APIError == .unauthorized) }
        XCTAssertEqual(session.account?.id, 7); XCTAssertFalse(source.isCurrent(session: owner))
    }
    func testRoleABARetiresOriginalFactoryAndPreservesDurableOwnerNamespace() async throws {
        let wire = Wire(), grant = Grant(), session = try root(wire, grant).makeSession(); await login(session)
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session), source = try XCTUnwrap(editor.storyAudioSource)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        let count = wire.requests.count
        do { _ = try await source.upload(audio(owner), attemptID: UUID(), session: owner); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, count); XCTAssertFalse(source.isCurrent(session: owner))
        XCTAssertEqual(try XCTUnwrap(session.projectEditor(product: .city).session).ownerKey, owner.ownerKey)
    }
    func testOuterRouteRequiresExactMultipartAndCloneSeesRevocation() async throws {
        let wire = Wire(), grant = Grant(), composition = try root(wire, grant), session = composition.makeSession(); await login(session)
        let editor = session.projectEditor(product: .city), owner = try XCTUnwrap(editor.session)
        _ = try await XCTUnwrap(editor.storyAudioSource).upload(audio(owner), attemptID: UUID(), session: owner)
        let valid = try XCTUnwrap(wire.requests.last), fence = composition.transport()
        fence.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        fence.projectEditConfigurationRevision = { 1 }
        fence.projectStoryAudioUploadApproval = { context in
            grant.enabled ? try? .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: 7, approvedOrigins: ["https://example.com"]) : nil
        }
        let clone = fence.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        wire.requests = []; _ = try await clone.send(valid)
        var wrong = valid; wrong.url = URL(string: valid.url!.absoluteString + "?owner=7")
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        wrong = valid; wrong.httpBody = Data("owner=7&fileType=m4a".utf8)
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        let boundary = try XCTUnwrap(valid.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: "boundary=").last)
        let body = String(decoding: try XCTUnwrap(valid.httpBody), as: UTF8.self)
        wrong = valid; wrong.httpBody = Data(body.replacingOccurrences(of: "\r\n--\(boundary)--\r\n", with: "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"owner\"\r\n\r\n8\r\n--\(boundary)--\r\n").utf8)
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        wrong = valid; wrong.httpBody = Data(body.replacingOccurrences(of: "audio/mp4", with: "video/mp4").utf8)
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        wrong = valid; wrong.url = base.appendingPathComponent("api/topic/cover/upload")
        do { _ = try await clone.send(wrong); XCTFail() } catch {}
        grant.enabled = false
        do { _ = try await clone.send(valid); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
}
#endif
