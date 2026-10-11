import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class StampCaptionHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var beforeReply: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?()
        return (Data(#"{"code":200,"url":"https://media.example.com/stamp.jpg"}"#.utf8), 200)
    }
}
@MainActor private final class StampCaptionStorage {
    var values: [String: Data] = [:]
    var pending: StoredRoamStampPending { .init(read: { self.values[$0] }, write: { self.values[$1] = $0 }) }
    var uploads: StoredImageUploadJournal { .init(read: { self.values[$0] }, write: { self.values[$1] = $0 }) }
}
@MainActor private final class StampCaptionExecutor: RoamMediaMutationExecuting {
    var enabled = true
    var scope: RetainedImageScope?
    var mutations: [RoamExperienceMutation] = []
    var fail = false
    var beforeReply: (() -> Void)?
    func execute(_ mutation: RoamExperienceMutation) async throws -> Data {
        mutations.append(mutation); beforeReply?()
        if fail { throw RetainedImageFailure.unknown }
        return Data(#"{"code":200,"data":{"id":29}}"#.utf8)
    }
}

@MainActor final class RoamStampCaptionTests: XCTestCase {
    private let picture = URL(string: "https://media.example.com/stamp.jpg")!
    private func scope(account: Int = 3) throws -> RetainedImageScope {
        try .init(accountID: account, epoch: UUID(), realm: "https://api.example.com/", destination: .stamp, namespace: "caption-tests")
    }
    private func capture(_ scope: RetainedImageScope, storage: StampCaptionStorage,
                         http: StampCaptionHTTP, executor: StampCaptionExecutor, enabled: Bool = true) throws -> RoamStampCaptureCoordinator {
        executor.scope = scope
        let uploader = try RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: scope.realm)!), transport: http,
            enabled: enabled, approvedOrigins: ["https://media.example.com"], currentScope: { scope }, token: { "fixture-token" })
        return .init(scope: scope, uploads: .init(uploader: uploader, journal: storage.uploads), executor: executor, storage: storage.pending)
    }
    private func image() throws -> RetainedSelectedImage { try .init(jpeg: Data([255, 216, 255]), width: 4, height: 5) }

    func testCaptionLimitUsesUTF16AndAllowsEmptyWithoutTruncation() throws {
        XCTAssertNoThrow(try RoamStampPending(pictureURL: picture, caption: "", idempotencyKey: "key"))
        XCTAssertNoThrow(try RoamStampPending(pictureURL: picture, caption: String(repeating: "字", count: 30), idempotencyKey: "key"))
        XCTAssertNoThrow(try RoamStampPending(pictureURL: picture, caption: String(repeating: "🙂", count: 15), idempotencyKey: "key"))
        XCTAssertThrowsError(try RoamStampPending(pictureURL: picture, caption: String(repeating: "🙂", count: 15) + "字", idempotencyKey: "key"))
    }
    func testLegacyPendingDecodesAsExactEmptyCaption() throws {
        let legacy = Data(#"{"pictureURL":"https://media.example.com/stamp.jpg","idempotencyKey":"legacy-key"}"#.utf8)
        let pending = try JSONDecoder().decode(RoamStampPending.self, from: legacy)
        XCTAssertEqual(pending.caption, ""); XCTAssertEqual(pending.idempotencyKey, "legacy-key")
        XCTAssertEqual(try JSONDecoder().decode(RoamStampPending.self, from: JSONEncoder().encode(pending)), pending)
    }
    func testMalformedPresentCaptionIsNotSilentlyMigrated() {
        for value in ["null", "31", "[]", "\"" + String(repeating: "x", count: 31) + "\""] {
            let data = Data((#"{"pictureURL":"https://media.example.com/stamp.jpg","idempotencyKey":"key","caption": "# + value + "}").utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(RoamStampPending.self, from: data))
        }
    }
    func testLocalEditingWorksWithDisabledUploaderAndDoesNotDispatchOrPersist() async throws {
        let storage = StampCaptionStorage(), http = StampCaptionHTTP(), executor = StampCaptionExecutor()
        let c = try capture(scope(), storage: storage, http: http, executor: executor, enabled: false)
        c.updateCaption("给下一站的一句"); c.captured(try image())
        XCTAssertEqual(c.caption, "给下一站的一句"); XCTAssertTrue(c.canEditCaption); XCTAssertFalse(c.canUpload)
        await c.upload(); await c.create()
        XCTAssertTrue(http.requests.isEmpty); XCTAssertTrue(executor.mutations.isEmpty); XCTAssertTrue(storage.values.isEmpty)
    }
    func testOverLimitDraftStaysVisibleAndBlocksUploadUntilCorrected() async throws {
        let storage = StampCaptionStorage(), http = StampCaptionHTTP(), executor = StampCaptionExecutor()
        let c = try capture(scope(), storage: storage, http: http, executor: executor)
        c.captured(try image()); let tooLong = String(repeating: "🙂", count: 16); c.updateCaption(tooLong)
        XCTAssertEqual(c.caption, tooLong); XCTAssertFalse(c.canUpload)
        await c.upload(); XCTAssertTrue(http.requests.isEmpty); XCTAssertTrue(storage.values.isEmpty)
        c.updateCaption(""); XCTAssertTrue(c.canUpload)
    }
    func testRetakePreservesCaptionAndCancelClearsUnsentDraft() throws {
        let c = try capture(scope(), storage: StampCaptionStorage(), http: StampCaptionHTTP(), executor: StampCaptionExecutor())
        c.updateCaption("重拍保留"); c.captured(try image()); c.retake()
        XCTAssertEqual(c.caption, "重拍保留"); XCTAssertNil(c.selection)
        c.captured(try image()); c.cancel()
        XCTAssertEqual(c.caption, ""); XCTAssertNil(c.selection)
    }
    func testUploadFreezesReviewedCaptionBeforeFirstSuspension() async throws {
        let s = try scope(), storage = StampCaptionStorage(), http = StampCaptionHTTP(), executor = StampCaptionExecutor()
        let c = try capture(s, storage: storage, http: http, executor: executor)
        c.updateCaption("保留空格  \n🙂"); c.captured(try image())
        http.beforeReply = {
            XCTAssertFalse(c.canEditCaption); c.updateCaption("late edit")
        }
        await c.upload()
        XCTAssertEqual(c.caption, "保留空格  \n🙂"); XCTAssertEqual(c.pending?.caption, c.caption)
        XCTAssertEqual(try storage.pending.load(scope: s)?.caption, c.caption)
        XCTAssertTrue(executor.mutations.isEmpty)
        c.updateCaption("not allowed"); XCTAssertEqual(c.caption, "保留空格  \n🙂")
        let pending = try XCTUnwrap(c.pending)
        await c.create()
        XCTAssertEqual(executor.mutations, [.createStamp(pictureURL: picture.absoluteString, caption: "保留空格  \n🙂", idempotencyKey: pending.idempotencyKey)])
        XCTAssertEqual(c.phase, .created(29)); XCTAssertNil(try storage.pending.load(scope: s))
    }
    func testUnknownCreateReopenRestoresExactCaptionURLAndKey() async throws {
        let s = try scope(), storage = StampCaptionStorage(), http = StampCaptionHTTP(), executor = StampCaptionExecutor()
        let c = try capture(s, storage: storage, http: http, executor: executor)
        c.updateCaption("  原文🙂  "); c.captured(try image()); await c.upload()
        executor.fail = true; await c.create(); c.cancel()
        XCTAssertEqual(c.caption, "  原文🙂  "); XCTAssertFalse(c.canEditCaption)
        let next = try capture(scope(), storage: storage, http: http, executor: executor)
        XCTAssertEqual(next.caption, "  原文🙂  "); next.updateCaption("changed"); next.retake()
        executor.fail = false; await next.create()
        XCTAssertEqual(executor.mutations.count, 2); XCTAssertEqual(executor.mutations.first, executor.mutations.last)
        XCTAssertEqual(http.requests.count, 1); XCTAssertEqual(next.phase, .created(29))
    }
    func testPendingCaptionCannotBeReplacedUnderSameURLAndKey() throws {
        let s = try scope(), storage = StampCaptionStorage()
        let original = try RoamStampPending(pictureURL: picture, caption: "original", idempotencyKey: "key")
        try storage.pending.save(original, scope: s)
        let replacement = try RoamStampPending(pictureURL: picture, caption: "replacement", idempotencyKey: "key")
        XCTAssertThrowsError(try storage.pending.save(replacement, scope: s))
        XCTAssertEqual(try storage.pending.load(scope: s), original)
    }
    func testCaptionIsAccountScopedButSurvivesEpochRotation() throws {
        let storage = StampCaptionStorage(), original = try RoamStampPending(pictureURL: picture, caption: "private draft", idempotencyKey: "key")
        try storage.pending.save(original, scope: scope())
        XCTAssertEqual(try storage.pending.load(scope: scope())?.caption, "private draft")
        XCTAssertNil(try storage.pending.load(scope: scope(account: 4)))
    }
    func testCanonicallyEquivalentCaptionCannotReplaceExactUTF8Payload() throws {
        let s = try scope(), storage = StampCaptionStorage()
        let original = try RoamStampPending(pictureURL: picture, caption: "e\u{301}", idempotencyKey: "key")
        let replacement = try RoamStampPending(pictureURL: picture, caption: "\u{e9}", idempotencyKey: "key")
        XCTAssertNotEqual(original, replacement)
        try storage.pending.save(original, scope: s)
        XCTAssertThrowsError(try storage.pending.save(replacement, scope: s))
        XCTAssertEqual(Array(try XCTUnwrap(storage.pending.load(scope: s)).caption.utf8), Array(original.caption.utf8))
    }
    func testLegacyStoredCommandRetriesWithEmptyCaptionWithoutReupload() async throws {
        let s = try scope(), storage = StampCaptionStorage(), http = StampCaptionHTTP(), executor = StampCaptionExecutor()
        try storage.pending.save(.init(pictureURL: picture, idempotencyKey: "legacy-key"), scope: s)
        for key in Array(storage.values.keys) {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: storage.values[key]!) as? [String: Any])
            json.removeValue(forKey: "caption"); storage.values[key] = try JSONSerialization.data(withJSONObject: json)
        }
        let c = try capture(s, storage: storage, http: http, executor: executor)
        XCTAssertEqual(c.caption, ""); XCTAssertFalse(c.canEditCaption)
        await c.create()
        XCTAssertEqual(executor.mutations, [.createStamp(pictureURL: picture.absoluteString, caption: "", idempotencyKey: "legacy-key")])
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testStaleCreateCannotClearCaptionOrPending() async throws {
        let s = try scope(), storage = StampCaptionStorage(), http = StampCaptionHTTP(), executor = StampCaptionExecutor()
        let c = try capture(s, storage: storage, http: http, executor: executor)
        c.updateCaption("keep for retry"); c.captured(try image()); await c.upload()
        executor.beforeReply = { c.cancel() }; await c.create()
        XCTAssertEqual(c.phase, .unknown); XCTAssertEqual(c.caption, "keep for retry")
        XCTAssertEqual(try storage.pending.load(scope: s)?.caption, "keep for retry")
    }
}
