import XCTest
@testable import Questify

/// NOT_RUN. Real AppSession/factory/journal adapter over synthetic auth, HTTP and vault primitives.
/// No location sample, permission request, OS Keychain, real credential or live backend operation.
@MainActor final class NativeHomeReturnSelectorRevisionJourneyTests: XCTestCase {
    @MainActor private final class Token: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private actor Vault: PrivateHomeKeychainPrimitive {
        var items: [String: PrivateHomeKeychainItem] = [:]
        func read(key: String) throws -> PrivateHomeKeychainItem? { items[key] }
        func insert(key: String, item: PrivateHomeKeychainItem) throws -> Bool {
            guard items[key] == nil else { return false }; items[key] = item; return true
        }
        func remove(key: String, matchingTag: Data) throws -> Bool {
            guard items[key]?.tag == matchingTag else { return false }; items[key] = nil; return true
        }
        func snapshot() -> [String: Data] { items.mapValues { $0.bytes + $0.tag } }
    }
    @MainActor private final class Issued {
        var value: NativeHomeReturnApproval?
        func select(_ context: RuntimeDependencyContext) -> NativeHomeReturnApproval? {
            if value == nil { value = try? .init(context: context, expiresAt: Date().addingTimeInterval(600)) }
            return value
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], restores: [NativeHomeRestoreRequest] = []
        var pauseSuffix: String?, onPause: (() -> Void)?
        private var paused: CheckedContinuation<Void, Never>?
        var version = 4
        var native: [URLRequest] { requests.filter { $0.url?.path.contains("/api/native/home/return/") == true } }
        func resume() { let saved = paused; paused = nil; saved?.resume() }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let suffix = request.url?.lastPathComponent
            if pauseSuffix == suffix, pauseSuffix != nil {
                pauseSuffix = nil; await withCheckedContinuation { paused = $0; onPause?() }
            }
            switch suffix {
            case "phone": return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8), 200)
            case "userInfo": return (Data(#"{"code":200,"appUser":{"id":7,"role":"player"}}"#.utf8), 200)
            default: break
            }
            let data: Any
            switch suffix {
            case "runs":
                data = ["runs": [["runId": "42", "activityId": "5", "topicId": "6", "playInstanceId": "synthetic-run", "resourceType": "sys.hp", "current": 2, "maximum": 5, "version": 4]], "truncated": false]
            case "policy":
                data = ["policyVersion": "synthetic", "maxAccuracyMeters": 20, "maxFixAgeSeconds": 30,
                        "dwellSeconds": 0, "serverTimeMillis": Int64(Date().timeIntervalSince1970 * 1000)]
            case "account":
                data = ["scopeType": "RUN", "scopeId": "42", "resourceType": "sys.hp", "current": version == 4 ? 2 : 5,
                        "maximum": 5, "version": version]
            case "restore":
                let original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                restores.append(original); version = 5
                data = ["requestId": original.requestId, "proofId": original.proofId, "decision": "RESTORED",
                        "current": 5, "maximum": 5, "accountVersion": 5]
            case "receipt": data = NSNull()
            default: data = NSNull()
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    @MainActor private struct Fixture {
        let root: AppCompositionRoot, session: AppSession, wire: Wire, vault: Vault, storageScope: RegionalSessionStorageScope
        let issued = Issued()
        func install() { session.nativeHomeReturnApprovalSelector = { [issued] in issued.select($0) } }
        func reinstall(_ approval: NativeHomeReturnApproval) { session.nativeHomeReturnApprovalSelector = { _ in approval } }
        func journal() throws -> NativeHomeReturnKeychainJournal {
            let approval = try XCTUnwrap(issued.value)
            return try .init(storageScope: storageScope, owner: approval.context.session, primitive: vault)
        }
    }
    private func fixture() async throws -> Fixture {
        func deployment(_ grant: PrivateHomeTransportGrant?) throws -> ReviewedAppDeployment {
            try .init(market: .china, baseURL: "https://home-selector.example.test/native",
                approvedBaseURLs: [.china: ["https://home-selector.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.questify.homeSelector", realm: "synthetic", privateHome: grant)
        }
        let base = try deployment(nil)
        let reviewed = try deployment(.init(storageScope: base.storageScope, accountID: 7, role: "player"))
        let suite = "native-home-selector-" + UUID().uuidString, token = Token(), vault = Vault(), wire = Wire()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let root = AppCompositionRoot(deployment: .reviewed(reviewed),
            storage: .init(defaults: defaults, tokenStore: { _ in token }, privateHomeKeychain: vault), makeTransport: { wire })
        let session = root.makeSession()
        await session.bootstrap(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
        return Fixture(root: root, session: session, wire: wire, vault: vault, storageScope: reviewed.storageScope)
    }
    private func original() throws -> NativeHomeRestoreRequest {
        try JSONDecoder().decode(NativeHomeRestoreRequest.self,
            from: Data(#"{"requestId":"restore-original","proofId":"proof-original","homeVersion":3,"expectedAccountVersion":4,"scopeType":"RUN","scopeId":"42","resourceType":"sys.hp"}"#.utf8))
    }

    func testUnchangedSelectorKeepsTheSameSessionOwnerWithoutAutomaticReads() async throws {
        let f = try await fixture(); XCTAssertNil(f.session.nativeHomeReturnSelection); f.install()
        let first = try XCTUnwrap(f.session.nativeHomeReturnSelection)
        for _ in 0..<3 { XCTAssertTrue(f.session.nativeHomeReturnSelection === first) }
        XCTAssertEqual(first.phase, .idle); XCTAssertTrue(f.wire.native.isEmpty)
        let stored = await f.vault.snapshot(); XCTAssertTrue(stored.isEmpty)
        await first.load(); XCTAssertEqual(first.phase, .ready); XCTAssertEqual(f.wire.native.count, 1)
    }

    func testSameGrantSelectorReassignmentImmediatelyInvalidatesOldOwner() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        await old.load(); let before = f.wire.native.count
        f.reinstall(approval)
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.runs.isEmpty); XCTAssertFalse(old.isAuthorized)
        await old.load(); XCTAssertEqual(f.wire.native.count, before)
        let fresh = try XCTUnwrap(f.session.nativeHomeReturnSelection)
        XCTAssertFalse(fresh === old); XCTAssertEqual(fresh.phase, .idle); XCTAssertEqual(f.wire.native.count, before)
        XCTAssertFalse(approval.revoked)
    }

    func testNilThenSameGrantWithoutInterveningGetterCannotReviveOldReference() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        await old.load(); let before = f.wire.native.count
        f.session.nativeHomeReturnApprovalSelector = { _ in nil }
        f.reinstall(approval) // Deliberately no selection getter between A -> nil -> A.
        await old.load()
        XCTAssertEqual(old.phase, .invalidated); XCTAssertFalse(old.isAuthorized); XCTAssertEqual(f.wire.native.count, before)
        XCTAssertFalse(try XCTUnwrap(f.session.nativeHomeReturnSelection) === old)
        XCTAssertEqual(f.wire.native.count, before); XCTAssertFalse(approval.revoked)
    }

    func testSetterNilDoesNotCreateGrantOrJourneyFromPrivateHomePermission() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection)
        f.session.nativeHomeReturnApprovalSelector = { _ in nil }
        XCTAssertNil(f.session.nativeHomeReturnSelection); XCTAssertEqual(old.phase, .invalidated)
        XCTAssertNotNil(f.session.privateHomeCoordinator); XCTAssertTrue(f.wire.native.isEmpty)
    }

    func testNativeSelectorReplacementDoesNotInvalidateIndependentCrudOwner() async throws {
        let f = try await fixture(), crud = try XCTUnwrap(f.session.privateHomeCoordinator); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        f.session.nativeHomeReturnApprovalSelector = { _ in nil }; f.reinstall(approval)
        XCTAssertTrue(f.session.privateHomeCoordinator === crud); XCTAssertEqual(crud.phase, .idle)
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(f.wire.native.isEmpty)
    }

    func testPausedRunsResponseCannotReviveOwnerAfterUnobservedSelectorABA() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        let entered = expectation(description: "Synthetic runs reached final transport")
        f.wire.pauseSuffix = "runs"; f.wire.onPause = { entered.fulfill() }
        let loading = Task { await old.load() }; defer { f.wire.resume(); loading.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        f.session.nativeHomeReturnApprovalSelector = { _ in nil }; f.reinstall(approval)
        let fresh = try XCTUnwrap(f.session.nativeHomeReturnSelection)
        f.wire.resume(); await loading.value
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.runs.isEmpty); XCTAssertFalse(old.isAuthorized)
        XCTAssertEqual(fresh.phase, .idle); XCTAssertEqual(f.wire.native.count, 1)
        await old.load(); XCTAssertEqual(f.wire.native.count, 1)
    }

    func testPausedSelectedAccountCannotRepopulateAfterSameGrantReset() async throws {
        let f = try await fixture(); f.install()
        let selection = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        await selection.load(); let run = try XCTUnwrap(selection.runs.first)
        let entered = expectation(description: "Synthetic account reached final transport")
        f.wire.pauseSuffix = "account"; f.wire.onPause = { entered.fulfill() }
        let choosing = Task { await selection.select(run) }; defer { f.wire.resume(); choosing.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        let oldModel = try XCTUnwrap(selection.selected); f.reinstall(approval)
        f.wire.resume(); await choosing.value
        XCTAssertEqual(selection.phase, .invalidated); XCTAssertNil(selection.selected)
        XCTAssertEqual(oldModel.phase, .invalidated); XCTAssertNil(oldModel.account); XCTAssertFalse(oldModel.canCheckIn)
        let before = f.wire.native.count; await oldModel.load(); await oldModel.retryExact(); XCTAssertEqual(f.wire.native.count, before)
        XCTAssertEqual(try XCTUnwrap(f.session.nativeHomeReturnSelection).phase, .idle)
    }

    func testPendingOriginalSurvivesSelectorReplacementAndNeedsExplicitFreshOwnerRecovery() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        let journal = try f.journal(), request = try original(); try await journal.save(request)
        await old.load(); let oldModel = try XCTUnwrap(old.selected)
        XCTAssertEqual(oldModel.phase, .unknown); XCTAssertTrue(oldModel.hasPendingRestore)
        let originalBytes = await f.vault.snapshot(), before = f.wire.native.count
        f.session.nativeHomeReturnApprovalSelector = { _ in nil }; f.reinstall(approval)
        let afterReplacement = await f.vault.snapshot(); XCTAssertEqual(afterReplacement, originalBytes)
        await oldModel.retryExact(); await oldModel.readBack(); await old.load()
        XCTAssertEqual(oldModel.phase, .invalidated); XCTAssertEqual(f.wire.native.count, before)
        let fresh = try XCTUnwrap(f.session.nativeHomeReturnSelection); XCTAssertFalse(fresh === old)
        XCTAssertEqual(f.wire.native.count, before); await fresh.load()
        let recovered = try XCTUnwrap(fresh.selected); XCTAssertEqual(recovered.phase, .unknown)
        let afterReload = await f.vault.snapshot(); XCTAssertEqual(afterReload, originalBytes); XCTAssertTrue(f.wire.restores.isEmpty)
        let persisted = try await journal.read(); XCTAssertEqual(persisted, request)
        await recovered.retryExact()
        XCTAssertEqual(f.wire.restores, [request]); XCTAssertEqual(recovered.decision, .restored); XCTAssertEqual(recovered.account?.version, 5)
        let afterSettlement = await f.vault.snapshot(); XCTAssertTrue(afterSettlement.isEmpty)
    }

    func testPausedOriginalReceiptCannotClearJournalAfterSelectorReset() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        let journal = try f.journal(), request = try original(); try await journal.save(request)
        await old.load(); let oldModel = try XCTUnwrap(old.selected), bytes = await f.vault.snapshot()
        let entered = expectation(description: "Synthetic receipt read reached final transport")
        f.wire.pauseSuffix = "receipt"; f.wire.onPause = { entered.fulfill() }
        let reading = Task { await oldModel.readBack() }; defer { f.wire.resume(); reading.cancel() }
        await fulfillment(of: [entered], timeout: 1)
        f.reinstall(approval); f.wire.resume(); await reading.value
        XCTAssertEqual(oldModel.phase, .invalidated); XCTAssertNil(oldModel.decision)
        let retained = await f.vault.snapshot(); XCTAssertEqual(retained, bytes); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testReplacingExternalCompositionValueDoesNotPretendToMutateExistingSessionCopy() async throws {
        let f = try await fixture(); var copiedRoot = f.root
        let issued = Issued(); copiedRoot.nativeHomeReturnApproval = { issued.select($0) }
        // AppSession stores its original root value. This does not signal a live configuration change.
        XCTAssertNil(f.session.nativeHomeReturnSelection); XCTAssertTrue(f.wire.native.isEmpty); XCTAssertNil(issued.value)
        f.install(); XCTAssertNotNil(f.session.nativeHomeReturnSelection)
        XCTAssertNil(issued.value) // Only the session's explicit selector was invoked.
    }

    func testGrantRevocationRemainsIrreversibleDespiteSelectorReassignment() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        approval.revoke(); f.reinstall(approval)
        XCTAssertNil(f.session.nativeHomeReturnSelection); await old.load()
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(f.wire.native.isEmpty); XCTAssertTrue(approval.revoked)
    }

    func testOffscreenPresentationCannotBeReactivatedBySelectorReplacement() async throws {
        let f = try await fixture(); f.install()
        let old = try XCTUnwrap(f.session.nativeHomeReturnSelection), approval = try XCTUnwrap(f.issued.value)
        f.session.setPrivateHomePresentationActive(false); f.reinstall(approval)
        XCTAssertNil(f.session.nativeHomeReturnSelection); XCTAssertEqual(old.phase, .invalidated)
        await old.load(); XCTAssertTrue(f.wire.native.isEmpty)
        f.session.setPrivateHomePresentationActive(true)
        let fresh = try XCTUnwrap(f.session.nativeHomeReturnSelection); XCTAssertFalse(fresh === old)
        XCTAssertEqual(fresh.phase, .idle); XCTAssertTrue(f.wire.native.isEmpty)
    }
}
