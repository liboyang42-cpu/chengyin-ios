import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MediaDestinationHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var data = Data(#"{"code":200,"url":"https://media.example.com/stamp.jpg"}"#.utf8)
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, 200) }
}
@MainActor private final class MediaDestinationStorage {
    var values: [String: Data] = [:]
    var fail = false
    var discard = false
    var pending: StoredRoamStampPending { .init(read: { self.values[$0] }, write: { data, key in
        if self.fail { throw ImageUploadJournalFailure.unavailable }; if !self.discard { self.values[key] = data }
    }) }
    var uploads: StoredImageUploadJournal { .init(read: { self.values[$0] }, write: { data, key in
        if self.fail { throw ImageUploadJournalFailure.unavailable }; if !self.discard { self.values[key] = data }
    }) }
}
@MainActor private final class MediaDestinationExecutor: RoamMediaMutationExecuting {
    var enabled = true
    var scope: RetainedImageScope?
    var mutations: [RoamExperienceMutation] = []
    var fail = false
    var data = Data(#"{"code":200,"data":{"id":29}}"#.utf8)
    var beforeReturn: (() -> Void)?
    func execute(_ mutation: RoamExperienceMutation) async throws -> Data {
        mutations.append(mutation); beforeReturn?()
        if fail { throw RetainedImageFailure.unknown }; return data
    }
}
@MainActor private final class MediaDestinationLocation: RoamDeviceLocationProviding {
    var requests = 0
    var fix: RoamDeviceFix
    init(datum: RoamDeviceFix.Datum = .gcj02, age: TimeInterval = 0) throws {
        fix = try .init(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31, longitude: 121)), accuracyMeters: 10,
                        measuredAt: Date().addingTimeInterval(-age), datum: datum)
    }
    func currentFix() async throws -> RoamDeviceFix { requests += 1; return fix }
    func stop() {}
}
/// The scan's read completes immediately. The first confirm's read is held; any accidental
/// concurrent confirm gets an immediate read so it can finish before the held one resumes.
@MainActor private final class MediaDestinationDelayedRefresh {
    let node: RoamNodeDetail
    private(set) var calls = 0
    private var pending: CheckedContinuation<RoamNodeDetail, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(node: RoamNodeDetail) { self.node = node }
    func read() async -> RoamNodeDetail {
        calls += 1
        guard calls == 2 else { return node }
        return await withCheckedContinuation { continuation in
            pending = continuation; started?.resume(); started = nil
        }
    }
    func waitForPreflight() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { let reply = pending; pending = nil; reply?.resume(returning: node) }
}
@MainActor private final class MediaDestinationPendingJournal: OperationPendingJournal {
    private(set) var writes = 0
    private(set) var record: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        guard let record else { return nil }
        guard record.ownerKey == ownerKey, record.targetKey == targetKey else { throw APIError.invalidRequest }
        return record
    }
    func write(_ record: OperationPendingRecord) throws {
        guard self.record == nil else { throw APIError.invalidRequest }
        writes += 1; self.record = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        guard self.record == record else { throw APIError.invalidRequest }; self.record = nil
    }
}
@MainActor final class MediaDestinationsTests: XCTestCase {
    private func scope(account: Int = 3, epoch: UUID = UUID()) throws -> RetainedImageScope {
        try .init(accountID: account, epoch: epoch, realm: "https://api.example.com/", destination: .stamp, namespace: "media-tests")
    }
    private func node(_ extra: String = "") throws -> RoamNodeDetail {
        try JSONDecoder().decode(RoamNodeDetail.self, from: Data("{\"poiId\":8,\"status\":1,\"validationMethod\":4\(extra)}".utf8))
    }
    func testGalleryPreservesCurrentIndexAndDuplicatePositions() {
        XCTAssertEqual(MediaGallerySnapshot(sources: ["a", "b", "a"], selectedIndex: 2).initialIndex, 2)
        XCTAssertEqual(MediaGallerySnapshot(sources: ["a"], selectedIndex: -1).initialIndex, 0)
        XCTAssertEqual(MediaGallerySnapshot(sources: [], selectedIndex: 2).initialIndex, 0)
        XCTAssertEqual(MediaGallerySnapshot(sources: Array(repeating: "a", count: 101), selectedIndex: 100).sources.count, 100)
    }
    func testPOIGalleryDecodesJSONSourceArrayWithoutInventingURL() throws {
        let value = try JSONDecoder().decode(RoamPublicMerchant.self, from: Data(#"{"id":1,"gallery":"[\"key-only\",\"https://media.example.com/p.jpg\"]"}"#.utf8))
        XCTAssertEqual(value.gallery, ["key-only", "https://media.example.com/p.jpg"])
    }
    func testPosterServerGatesRemainSeparate() throws {
        XCTAssertEqual(RoamPosterAvailability(node: try node()), .available)
        XCTAssertEqual(RoamPosterAvailability(node: try node(",\"completed\":true")), .completed)
        XCTAssertEqual(RoamPosterAvailability(node: try node(",\"needRedeem\":true")), .needsRedemption)
        XCTAssertEqual(RoamPosterAvailability(node: try node(",\"canInteract\":false")), .unsupported)
        let offline = try JSONDecoder().decode(RoamNodeDetail.self, from: Data(#"{"poiId":8,"status":0,"validationMethod":4}"#.utf8))
        XCTAssertEqual(RoamPosterAvailability(node: offline), .offline)
    }
    func testStampDefaultUploaderAndMutationServiceNeverReadCredentialOrDispatch() async throws {
        let s = try scope(), http = MediaDestinationHTTP(); var credentials = 0
        let uploader = try RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: s.realm)!), transport: http,
            currentScope: { s }, token: { credentials += 1; return "fixture-token" })
        let executor = try RoamMediaMutationService(configuration: .init(baseURL: URL(string: s.realm)!), transport: http,
            currentScope: { s }, token: { credentials += 1; return "fixture-token" })
        do { _ = try await executor.execute(.createStamp(pictureURL: "https://media.example.com/a.jpg", caption: "", idempotencyKey: "same")); XCTFail() } catch {}
        let image = try RetainedSelectedImage(jpeg: Data([255,216,255]), width: 4, height: 5)
        do { _ = try await uploader.upload(.init(scope: s, selection: image)); XCTFail() } catch {}
        XCTAssertEqual(credentials, 0); XCTAssertTrue(http.requests.isEmpty)
    }
    private func capture(_ s: RetainedImageScope, _ storage: MediaDestinationStorage, _ http: MediaDestinationHTTP, _ executor: MediaDestinationExecutor) throws -> RoamStampCaptureCoordinator {
        executor.scope = s
        let uploader = try RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: s.realm)!), transport: http,
            enabled: true, approvedOrigins: ["https://media.example.com"], currentScope: { s }, token: { "fixture-token" })
        return RoamStampCaptureCoordinator(scope: s, uploads: .init(uploader: uploader, journal: storage.uploads), executor: executor, storage: storage.pending)
    }
    func testCaptureUploadAndCreateAreDistinctAndUseSourceMultipart() async throws {
        let s = try scope(), storage = MediaDestinationStorage(), http = MediaDestinationHTTP(), executor = MediaDestinationExecutor()
        let c = try capture(s, storage, http, executor)
        c.captured(try .init(jpeg: Data([255,216,255]), width: 4, height: 5))
        XCTAssertTrue(http.requests.isEmpty); XCTAssertEqual(c.phase, .review)
        await c.upload(); XCTAssertEqual(c.phase, .awaitingCreate); XCTAssertTrue(executor.mutations.isEmpty)
        let body = String(decoding: try XCTUnwrap(http.requests.first?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"bizType\"\r\n\r\nstamp")); XCTAssertTrue(body.contains("name=\"file\""))
        executor.beforeReturn = { XCTAssertNotNil(try? storage.pending.load(scope: s)) }
        await c.create(); XCTAssertEqual(c.phase, .created(29)); XCTAssertNil(try storage.pending.load(scope: s))
        XCTAssertEqual(http.requests.count, 1); XCTAssertEqual(executor.mutations.count, 1)
    }
    func testUnknownCreateReopenAndExactRetryNeverReuploadsOrChangesKey() async throws {
        let s = try scope(), storage = MediaDestinationStorage(), http = MediaDestinationHTTP(), executor = MediaDestinationExecutor()
        let c = try capture(s, storage, http, executor)
        c.captured(try .init(jpeg: Data([255,216,255]), width: 4, height: 5)); await c.upload()
        executor.fail = true; await c.create(); XCTAssertEqual(c.phase, .unknown)
        let original = executor.mutations.first; c.retake(); XCTAssertFalse(c.canCapture)
        let next = try capture(scope(), storage, http, executor)
        XCTAssertEqual(next.phase, .unknown); executor.fail = false; await next.create()
        XCTAssertEqual(executor.mutations.last, original); XCTAssertEqual(http.requests.count, 1)
    }
    func testFailedPendingPersistenceNeverCreatesAndKeepsUploadLocked() async throws {
        let s = try scope(), storage = MediaDestinationStorage(), http = MediaDestinationHTTP(), executor = MediaDestinationExecutor()
        let c = try capture(s, storage, http, executor)
        c.captured(try .init(jpeg: Data([255,216,255]), width: 4, height: 5)); storage.fail = true
        await c.upload(); await c.create(); XCTAssertTrue(executor.mutations.isEmpty); XCTAssertTrue(http.requests.isEmpty)
        XCTAssertEqual(c.phase, .unknown)
    }
    func testPendingStoreFencesAccountButSurvivesEpochRotation() throws {
        let storage = MediaDestinationStorage(), s = try scope()
        let pending = try RoamStampPending(pictureURL: URL(string: "https://media.example.com/a.jpg")!, idempotencyKey: "same-key")
        try storage.pending.save(pending, scope: s)
        XCTAssertEqual(try storage.pending.load(scope: scope()), pending)
        XCTAssertNil(try storage.pending.load(scope: scope(account: 4)))
        storage.discard = true
        XCTAssertThrowsError(try storage.pending.clear(pending, scope: s))
    }
    func testMalformedPendingBlocksCapture() throws {
        let storage = MediaDestinationStorage(), s = try scope(), http = MediaDestinationHTTP(), executor = MediaDestinationExecutor()
        let pending = try RoamStampPending(pictureURL: URL(string: "https://media.example.com/a.jpg")!, idempotencyKey: "key")
        try storage.pending.save(pending, scope: s)
        for key in storage.values.keys { storage.values[key] = Data("corrupt".utf8) }
        let c = try capture(s, storage, http, executor); XCTAssertFalse(c.canCapture); XCTAssertEqual(c.phase, .unavailable)
    }
    func testStaleCreateCallbackCannotClearPendingOrClaimSuccess() async throws {
        let s = try scope(), storage = MediaDestinationStorage(), http = MediaDestinationHTTP(), executor = MediaDestinationExecutor()
        let c = try capture(s, storage, http, executor)
        c.captured(try .init(jpeg: Data([255,216,255]), width: 4, height: 5)); await c.upload()
        executor.beforeReturn = { c.cancel() }; await c.create()
        XCTAssertEqual(c.phase, .unknown); XCTAssertNotNil(try storage.pending.load(scope: s))
    }
    func testPosterRejectsWGS84StaleAndUnconsentedFixes() async throws {
        for (datum, age) in [(RoamDeviceFix.Datum.wgs84, 0.0), (.gcj02, 90.0)] {
            let s = try scope(), e = MediaDestinationExecutor(), n = try node(); e.scope = s
            let location = try MediaDestinationLocation(datum: datum, age: age)
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let c = RoamPosterCoordinator(scope: s, poiID: n.poiId, node: { n }, location: location, executor: e, journal: OperationDefaultsJournal(defaults: defaults))
            await c.scanned("code", purposeAccepted: false); XCTAssertEqual(location.requests, 0)
            await c.scanned("code", purposeAccepted: true); XCTAssertEqual(c.phase, .failed)
            await c.submit(); XCTAssertTrue(e.mutations.isEmpty)
        }
    }
    func testPosterUnknownOutcomeLocksRelaunchAndDoesNotRescan() async throws {
        let s = try scope(), e = MediaDestinationExecutor(), n = try node(), location = try MediaDestinationLocation(); e.scope = s; e.fail = true
        let journal = OperationDefaultsJournal(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let c = RoamPosterCoordinator(scope: s, poiID: n.poiId, node: { n }, location: location, executor: e, journal: journal)
        await c.scanned("code", purposeAccepted: true); XCTAssertEqual(c.phase, .review)
        await c.submit(); XCTAssertEqual(c.phase, .unknown)
        let next = RoamPosterCoordinator(scope: s, poiID: n.poiId, node: { n }, location: location, executor: e, journal: journal)
        await next.scanned("different", purposeAccepted: true); XCTAssertEqual(next.phase, .unknown)
        XCTAssertEqual(location.requests, 1); XCTAssertEqual(e.mutations.count, 1)
    }
    func testConcurrentPosterConfirmDuringDelayedRefreshDispatchesOnce() async throws {
        let n = try node(), refresh = MediaDestinationDelayedRefresh(node: n)
        let s = try scope(), executor = MediaDestinationExecutor(), journal = MediaDestinationPendingJournal()
        executor.scope = s; executor.data = Data(#"{"code":200,"data":{"needRedeem":false}}"#.utf8)
        let c = RoamPosterCoordinator(scope: s, poiID: n.poiId, node: { n }, location: try MediaDestinationLocation(),
            executor: executor, journal: journal, refreshNode: { await refresh.read() })
        await c.scanned("one-code", purposeAccepted: true)
        let first = Task { await c.submit() }
        await refresh.waitForPreflight()
        XCTAssertEqual(c.phase, .preflighting)
        // With the old implementation this second call could finish and clear the journal
        // while the first was held, allowing the first to dispatch again when released.
        let second = Task { await c.submit() }
        await second.value
        XCTAssertEqual(refresh.calls, 2); XCTAssertTrue(executor.mutations.isEmpty)
        XCTAssertEqual(journal.writes, 0); XCTAssertEqual(c.phase, .preflighting)
        refresh.release(); await first.value
        XCTAssertEqual(executor.mutations.count, 1); XCTAssertEqual(journal.writes, 1)
        XCTAssertEqual(c.phase, .completed); XCTAssertNil(journal.record)
        await c.submit(); XCTAssertEqual(executor.mutations.count, 1)
    }
    func testCancelPosterDuringPreflightCannotDispatch() async throws {
        let n = try node(), refresh = MediaDestinationDelayedRefresh(node: n)
        let s = try scope(), executor = MediaDestinationExecutor(), journal = MediaDestinationPendingJournal(); executor.scope = s
        let c = RoamPosterCoordinator(scope: s, poiID: n.poiId, node: { n }, location: try MediaDestinationLocation(),
            executor: executor, journal: journal, refreshNode: { await refresh.read() })
        await c.scanned("one-code", purposeAccepted: true)
        let confirm = Task { await c.submit() }; await refresh.waitForPreflight()
        c.cancel(); refresh.release(); await confirm.value
        XCTAssertEqual(c.phase, .ready); XCTAssertTrue(executor.mutations.isEmpty)
        XCTAssertEqual(journal.writes, 0); XCTAssertNil(journal.record)
        await c.submit(); XCTAssertTrue(executor.mutations.isEmpty) // Canceled review cannot be replayed.
    }
    func testCancelPosterTaskDuringPreflightCannotDispatch() async throws {
        let n = try node(), refresh = MediaDestinationDelayedRefresh(node: n)
        let s = try scope(), executor = MediaDestinationExecutor(), journal = MediaDestinationPendingJournal(); executor.scope = s
        let c = RoamPosterCoordinator(scope: s, poiID: n.poiId, node: { n }, location: try MediaDestinationLocation(),
            executor: executor, journal: journal, refreshNode: { await refresh.read() })
        await c.scanned("one-code", purposeAccepted: true)
        let confirm = Task { await c.submit() }; await refresh.waitForPreflight()
        confirm.cancel(); refresh.release(); await confirm.value
        XCTAssertEqual(c.phase, .ready); XCTAssertTrue(executor.mutations.isEmpty)
        XCTAssertEqual(journal.writes, 0); XCTAssertNil(journal.record)
    }
    func testPosterRedemptionAndMalformedReceiptNeverClaimCompletion() throws {
        let receipt = try JSONDecoder().decode(RoamPosterReceipt.self, from: Data(#"{"needRedeem":true}"#.utf8))
        XCTAssertTrue(receipt.needRedeem)
        XCTAssertThrowsError(try JSONDecoder().decode(RoamPosterReceipt.self, from: Data("{}".utf8)))
    }
    func testWithdrawalMissingSuccessfulBalanceDiffersFromMalformedBalance() throws {
        for raw in ["{}", "{\"balance\":null}", "{\"balance\":\"\"}"] {
            XCTAssertEqual(try JSONDecoder().decode(WithdrawalBalance.self, from: Data(raw.utf8)).balance.value, 0)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(WithdrawalBalance.self, from: Data(#"{"balance":"unknown"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(WithdrawalBalance.self, from: Data(#"{"balance":-1}"#.utf8)))
    }
    func testSupportContactRejectsURLsAndControls() throws {
        XCTAssertThrowsError(try WithdrawalSupportContact(weChatID: "https://unreviewed.example"))
        XCTAssertThrowsError(try WithdrawalSupportContact(weChatID: "bad\ncontact"))
        XCTAssertEqual(try WithdrawalSupportContact(weChatID: "support_demo").weChatID, "support_demo")
    }
}
