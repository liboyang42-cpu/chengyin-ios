import Foundation
import XCTest
@testable import Questify

/// New terminal wire specimen under the actual AppSession/composition factory. No live network.
@MainActor final class ParticipantHostSpecimen {
    static let base = URL(string: "https://example.com/native/")!
    final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var failAddress = false, missingCreateRow = false
        var onAddress: (() -> Void)?
        var status = 200
        var row = #"{"id":9,"fullName":"Name","mobilePhone":"13900000000","province":"P","detailAddress":"A","isDefault":1}"#
        var addressRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/user/address/") == true } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/phone") { return (Data(#"{"code":200,"token":"synthetic-participant-7","data":{"id":7,"role":"player"}}"#.utf8),200) }
            if path.hasSuffix("/userInfo") { return (Data(#"{"code":200,"appUser":{"userId":7,"role":"player"}}"#.utf8),200) }
            guard path.contains("/api/user/address/") else { throw APIError.invalidRequest }
            onAddress?()
            if failAddress { throw URLError(.timedOut) }
            if status == 401 { return (Data(#"{"code":401}"#.utf8),401) }
            if path.hasSuffix("/list") { return (Data(("{\"code\":200,\"data\":{\"rows\":[" + row + "]}}").utf8),status) }
            if path.hasSuffix("/info") { return (Data(("{\"code\":200,\"data\":" + row + "}").utf8),status) }
            if path.hasSuffix("/delete") || missingCreateRow { return (Data(#"{"code":200,"data":null}"#.utf8),status) }
            if path.hasSuffix("/action") { return (Data(("{\"code\":200,\"data\":" + row + "}").utf8),status) }
            throw APIError.invalidRequest
        }
    }
    let wire = Wire(), vault = Vault()
    let root: AppCompositionRoot
    let defaults: UserDefaults
    let suite: String
    let namespace: String
    var access: ProfileParticipantAccess?
    init() throws {
        suite = "participant-host-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: Self.base.absoluteString,
            approvedBaseURLs: [.china: [Self.base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.participants." + UUID().uuidString.lowercased(), realm: "synthetic")
        namespace = deployment.storageScope.service
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func cleanup() { access?.revoke(); defaults.removePersistentDomain(forName: suite) }
    func login() async -> AppSession {
        let session = root.makeSession(); session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        wire.requests = []; return session
    }
    func install(_ session: AppSession, writes: Bool) {
        access = nil
        session.participantAccessSelector = { [weak self] context in
            guard let self else { return nil }
            if let access = self.access, ContentDraftContextFence.matches(context, access.context) { return access }
            let issued = try? ProfileParticipantAccess(context: context, permitsWrites: writes, expiresAt: Date().addingTimeInterval(60))
            self.access = issued; return issued
        }
        _ = session.participantReader.identity
    }
    static func draft() -> ParticipantFormDraft {
        var value = ParticipantFormDraft(); value.fullName = "Name"; value.mobilePhone = "13900000000"; return value
    }
}

@MainActor final class ProfileParticipantHostAdmissionTests: XCTestCase {
    func specimen() throws -> ParticipantHostSpecimen {
        let h = try ParticipantHostSpecimen(); addTeardownBlock { @MainActor in h.cleanup() }; return h
    }
    func testDefaultHOLDAndReadOnlyGrantUseActualNormalHost() async throws {
        let h = try specimen(), session = await h.login()
        XCTAssertFalse(session.participantReader.isConfigured); XCTAssertFalse(session.participantCoordinator.isConfigured)
        do { _ = try await session.participantReader.profileParticipants(); XCTFail() } catch {}
        XCTAssertTrue(h.wire.addressRequests.isEmpty)
        h.install(session, writes: false)
        let rows = try await session.participantReader.profileParticipants()
        let row = try await session.participantReader.profileParticipant(id: 9)
        XCTAssertEqual(rows.first?.id, 9); XCTAssertEqual(row.id, 9)
        XCTAssertFalse(session.participantCoordinator.canPrepare)
        XCTAssertEqual(h.wire.addressRequests.count, 2)
        XCTAssertTrue(h.wire.addressRequests.allSatisfy { $0.httpMethod == "POST" })
        XCTAssertNil(h.wire.addressRequests[0].httpBody)
        XCTAssertEqual(session.participantReader.identity, session.participantCoordinator.identity)
        XCTAssertNotEqual(session.participantReader.identity, session.profileReader.identity)
    }
    func testNormalOriginalUUIDCreateThenEditDeleteACK() async throws {
        let h = try specimen(), session = await h.login(); h.install(session, writes: true)
        let coordinator = session.participantCoordinator, identity = try XCTUnwrap(session.participantReader.identity)
        let confirmation = try coordinator.prepare(.save(ParticipantHostSpecimen.draft()), expectedIdentity: identity)
        _ = await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.state, .succeeded); XCTAssertEqual(coordinator.savedParticipant?.id, 9)
        let text = String(decoding: try XCTUnwrap(h.wire.addressRequests.last?.httpBody), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"requestId\"\r\n\r\n" + confirmation.id.uuidString.lowercased() + "\r\n"))
        let row = try await session.participantReader.profileParticipant(id: 9)
        h.wire.missingCreateRow = true // Empty data remains a lawful original edit/delete ACK.
        let edit = try coordinator.prepare(.save(.init(detail: row)), expectedIdentity: identity)
        _ = await coordinator.confirm(edit); XCTAssertEqual(coordinator.state, .succeeded)
        let editText = String(decoding: try XCTUnwrap(h.wire.addressRequests.last?.httpBody), as: UTF8.self)
        XCTAssertFalse(editText.contains("name=\"requestId\"")); XCTAssertTrue(editText.contains("name=\"province\""))
        let deletion = try coordinator.prepare(.delete(id: 9), expectedIdentity: identity)
        _ = await coordinator.confirm(deletion); XCTAssertEqual(coordinator.state, .succeeded)
        XCTAssertEqual(h.wire.addressRequests.count, 4)
    }
    func testGenericRootDoesNotBorrowDedicatedOrMerchantAccess() async throws {
        let h = try specimen(), transport = h.root.transport()
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-participant-7", viewerRevision: 1) }
        let context = RuntimeDependencyContext(market: .china, baseURL: ParticipantHostSpecimen.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: h.namespace, token: "synthetic-participant-7"))
        let access = try ProfileParticipantAccess(context: context, permitsWrites: true, expiresAt: Date().addingTimeInterval(60))
        let request = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent("api/user/address/list"), fields: [:], token: context.session.token, includesBody: false)
        do { _ = try await transport.send(request); XCTFail() } catch {}
        XCTAssertTrue(h.wire.addressRequests.isEmpty)
        let scoped = try XCTUnwrap(transport.makeProfileParticipantTransport(context: context, access: access, currentRuntime: { context }, stillCurrent: { true }))
        _ = try await scoped.send(request); XCTAssertEqual(h.wire.addressRequests.count, 1)
        let other = RuntimeDependencyContext(market: .china, baseURL: context.baseURL, role: "merchant", session: context.session)
        XCTAssertNil(transport.makeProfileParticipantTransport(context: other, access: access, currentRuntime: { other }, stillCurrent: { true }))
    }
    func testPreDispatchGrantWithdrawalIsNotSentAndNeverTouchesWire() async throws {
        let h = try specimen(), session = await h.login(); h.install(session, writes: true)
        let identity = try XCTUnwrap(session.participantReader.identity)
        h.access?.revoke()
        do { _ = try await session.participantWriter.performReturningParticipant(.delete(id: 9), requestID: UUID(), expectedIdentity: identity); XCTFail() }
        catch { XCTAssertEqual(error as? ParticipantWriteError, .notSent(.notConfigured)) }
        XCTAssertTrue(h.wire.addressRequests.isEmpty)
    }
}
