import Foundation
import XCTest
@testable import Questify

@MainActor private final class NPCReadHostVault: AppTokenStorage {
    var value: String? = "synthetic-npc-host-token"
    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func clear() throws { value = nil }
}
@MainActor private final class NPCReadHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player"
    var status = 200
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" {
            return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
        }
        after?()
        return (Data(#"{"code":200,"data":{"retentionDays":37,"retentionPolicy":"Synthetic policy","records":[{"id":1,"userId":7,"userMsg":"Synthetic private question","npcReply":"Synthetic private reply","createTime":"2026-10-09 09:00:00"}]}}"#.utf8), status)
    }
}
@MainActor private final class NPCReadHostFixture {
    let wire = NPCReadHostWire(), vault = NPCReadHostVault()
    let root: AppCompositionRoot
    let suite = "npc-read-host-" + UUID().uuidString
    let defaults: UserDefaults
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://npc-host.example.test/native",
            approvedBaseURLs: [.china: ["https://npc-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.npc.read." + UUID().uuidString.lowercased(), realm: "synthetic")
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let session = root.makeSession(); await session.bootstrap(); wire.requests = []; return session }
    func approve(_ session: AppSession) throws -> NPCChatDataReadApproval {
        let value = try NPCChatDataReadApproval(context: XCTUnwrap(session.npcChatDataReadIdentity.context), expiresAt: Date().addingTimeInterval(600))
        try root.npcChatDataReadSelection.replace(with: value); return value
    }
    func cleanup() { root.npcChatDataReadSelection.revoke(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class NPCChatDataIndependentHostTests: XCTestCase {
    private func fixture() throws -> NPCReadHostFixture {
        let f = try NPCReadHostFixture(); addTeardownBlock { @MainActor in f.cleanup() }; return f
    }
    func testDefaultNilSourceKeepsUnavailableCoordinatorWithoutRequest() async throws {
        let f = try fixture(), session = await f.boot()
        XCTAssertNil(session.npcChatDataReadIdentity.approvalRevision); XCTAssertNil(session.makeNPCChatDataReader())
        let coordinator = session.makeNPCChatDataReadCoordinator(), model = NPCChatDataViewModel(coordinator: coordinator)
        model.appear(active: true); XCTAssertNil(model.loadIntent); XCTAssertEqual(coordinator.failure, .unavailable)
        XCTAssertFalse(coordinator.canRequestDeletion); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testNormalRootReadUsesExistingModelWithoutDeletionOrConsentRequirements() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let coordinator = session.makeNPCChatDataReadCoordinator(), model = NPCChatDataViewModel(coordinator: coordinator)
        model.appear(active: true); await model.load(model.loadIntent)
        XCTAssertEqual(coordinator.data?.records.first?.userMessage, "Synthetic private question")
        XCTAssertFalse(coordinator.canRequestDeletion); model.requestDeletion(); model.confirmDeletion(); XCTAssertNil(model.deletionIntent)
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET"]); XCTAssertEqual(f.wire.requests.first?.url?.path, "/native/api/ai/npc/chat/data/export")
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
    func testBackgroundAndForegroundRequireExplicitReloadInExistingUIModel() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let model = NPCChatDataViewModel(coordinator: session.makeNPCChatDataReadCoordinator())
        model.appear(active: true)
        await model.load(model.loadIntent); XCTAssertNotNil(model.coordinator.data)
        model.suspend(); model.foreground(); XCTAssertNil(model.coordinator.data); XCTAssertNil(model.loadIntent); XCTAssertEqual(f.wire.requests.count, 1)
        model.requestLoad()
        await model.load(model.loadIntent); XCTAssertEqual(f.wire.requests.count, 2)
    }
    func testSourceWithdrawalClearsAllOpenPrivateModelsImmediately() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let a = NPCChatDataViewModel(coordinator: session.makeNPCChatDataReadCoordinator()), b = NPCChatDataViewModel(coordinator: session.makeNPCChatDataReadCoordinator())
        a.appear(active: true); await a.load(a.loadIntent); b.appear(active: true); await b.load(b.loadIntent)
        a.requestLoad(); let queued = a.loadIntent
        f.root.npcChatDataReadSelection.revoke(); f.wire.requests = []
        XCTAssertNil(a.coordinator.data); XCTAssertNil(b.coordinator.data)
        await a.load(queued); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertNil(session.makeNPCChatDataReader())
    }
    func testReplacementLeaseCannotReanimateOldPresentationOrReuseIssuance() async throws {
        let f = try fixture(), session = await f.boot(), old = try f.approve(session)
        let identity = session.npcChatDataReadIdentity, flow = session.makeNPCChatDataReadCoordinator(); flow.appear(active: true); await flow.load()
        _ = try f.approve(session); f.wire.requests = []
        XCTAssertNotEqual(session.npcChatDataReadIdentity, identity); XCTAssertNil(flow.data)
        await flow.load(); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertThrowsError(try f.root.npcChatDataReadSelection.replace(with: old)); XCTAssertNotNil(session.makeNPCChatDataReader())
        let reopened = session.makeNPCChatDataReadCoordinator(); reopened.appear(active: true); await reopened.load()
        XCTAssertNotNil(reopened.data); XCTAssertNil(flow.data); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testRoleRefreshHidesCachedListAndPreventsQueuedOldRead() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let identity = session.npcChatDataReadIdentity, model = NPCChatDataViewModel(coordinator: session.makeNPCChatDataReadCoordinator())
        model.appear(active: true); await model.load(model.loadIntent); model.requestLoad(); let queued = model.loadIntent
        f.wire.role = "merchant"; await session.refreshOwnAccount(); f.wire.requests = []
        XCTAssertNotEqual(session.npcChatDataReadIdentity, identity); XCTAssertNil(model.coordinator.data)
        await model.load(queued); XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertNil(session.makeNPCChatDataReader())
        let disabled = session.makeNPCChatDataReadCoordinator(); disabled.appear(active: true); XCTAssertEqual(disabled.failure, .unavailable)
        // A separately approved new role can reopen the persistent entry; the old sheet stays retired.
        _ = try f.approve(session)
        let reopened = session.makeNPCChatDataReadCoordinator(); reopened.appear(active: true); await reopened.load()
        XCTAssertNotNil(reopened.data); XCTAssertNil(model.coordinator.data); XCTAssertFalse(disabled.canLoad)
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testCurrent403ClearsPrivateTextWithoutLoggingOutAccount() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let flow = session.makeNPCChatDataReadCoordinator(); flow.appear(active: true)
        await flow.load(); XCTAssertNotNil(flow.data)
        f.wire.status = 403
        await flow.load(); XCTAssertNil(flow.data); XCTAssertNil(session.makeNPCChatDataReader())
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(f.vault.value, "synthetic-npc-host-token")
    }
    func testLateRevoked401CannotExpireCurrentAccount() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let flow = session.makeNPCChatDataReadCoordinator(); flow.appear(active: true)
        f.wire.status = 401; f.wire.after = { f.root.npcChatDataReadSelection.revoke() }
        await flow.load(); XCTAssertNil(flow.data); XCTAssertFalse(approval.revoked)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(f.vault.value, "synthetic-npc-host-token")
    }
    func testDedicatedTransportChecksViewerRevisionEvenWithSameIdentityTuple() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let context = approval.context, host = f.root.transport()
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 1)
        host.current = { viewer }
        let transport = try XCTUnwrap(host.makeNPCChatDataReadTransport(context: context, approval: approval, currentRuntime: { context }, stillSelected: { true }))
        viewer = .init(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 2)
        var r = URLRequest(url: context.baseURL.appendingPathComponent(NPCChatData.path)); r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue(context.session.token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("no-store", forHTTPHeaderField: "Cache-Control"); r.setValue("no-cache", forHTTPHeaderField: "Pragma")
        do { _ = try await transport.send(r); XCTFail() } catch { }; XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testGenericTransportCannotBorrowStandaloneReadLease() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let host = f.root.transport(), context = approval.context
        host.current = { .init(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 1) }
        var r = URLRequest(url: context.baseURL.appendingPathComponent(NPCChatData.path)); r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue(context.session.token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        do { _ = try await host.send(r); XCTFail() } catch { }; XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testLegacyEntryFlagsDefaultOnForExistingCallers() {
        let support = SettingsSupportSections(market: .china)
        XCTAssertTrue(support.showsNPCChatDataEntry)
        let legacy = AccountComplianceSettingsSection(makeCoordinator: { fatalError("Not invoked") }, market: .china, legalReader: SettingsBundledLegalReader())
        XCTAssertTrue(legacy.showsNPCChatDataEntry)
        let normal = SettingsSupportSections(market: .china, showsNPCChatDataEntry: false)
        XCTAssertFalse(normal.showsNPCChatDataEntry)
    }
    func testReadDoesNotWritePreferencesCredentialOrEnableRecording() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let before = f.defaults.dictionaryRepresentation(), token = f.vault.value
        let reader = try XCTUnwrap(session.makeNPCChatDataReader()); _ = try await reader.read(reader.session)
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: f.defaults.dictionaryRepresentation())); XCTAssertEqual(f.vault.value, token)
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
}
