import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectStoryAudioFlowTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], status = 200, raw: Data?
        var reference = "https://example.com/story/e%CC%81.mp3?revision=1"
        var beforeReply: (() -> Void)?, started: XCTestExpectation?, continuation: CheckedContinuation<(Data, Int), Error>?
        var held = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if held { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            beforeReply?(); return try response()
        }
        func response() throws -> (Data, Int) { (try raw ?? JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(status)), "url": .string(reference)]), status) }
        func finish() throws { let old = continuation; continuation = nil; old?.resume(returning: try response()) }
    }
    @MainActor private final class Context {
        var session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "story-audio-tests")
        var current = true, draft = ProjectEditSyntheticFixtures.draft()
        let storage = ProjectEditMemoryStorage(), wire = Wire(), identity = try! ProjectEditDraftIdentity(topicID: 101)
        var approval: ProjectStoryAudioUploadApproval?
        lazy var journal = ProjectStoryAudioJournal(storage: storage)
        init() {
            draft.preserved["publishMode"] = .string("pro")
            let c = draft.chapters[0]
            draft.chapters[0].blocks = [.init(kind: .text, content: c.description), .init(kind: .node, nodeID: c.nodes[0].id), .init(kind: .audio)]
        }
        var blockID: String { draft.chapters[0].blocks!.last!.id }
    }
    private func selected(_ ext: String = "mp3") throws -> ProjectStorySelectedAudio {
        var sent = false
        return try ProjectStoryAudioCapture.read(filename: "声音 e\u{301}." + ext, reportedByteCount: 3, checkCancellation: {}, readChunk: { _ in
            if sent { return Data() }; sent = true; return Data([1,2,3])
        })
    }
    private func source(_ c: Context, enabled: Bool = true, picker: Bool = true) throws -> ProjectStoryAudioUploadClient {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        c.approval = enabled ? try .init(baseURL: configuration.baseURL, namespace: c.session.storageNamespace, accountID: 7, approvedOrigins: ["https://example.com"], nativePicker: picker) : nil
        return .init(configuration: configuration, approval: c.approval, transport: c.wire, credentials: {
            c.current ? try? .init(session: c.session, token: "synthetic-audio-token") : nil
        }, currentApproval: { c.approval })
    }
    private func flow(_ c: Context, _ source: ProjectStoryAudioUploadClient) throws -> ProjectStoryAudioFlow {
        .init(target: try .init(draft: c.draft, identity: c.identity, session: c.session, chapterID: c.draft.chapters[0].id, blockID: c.blockID), session: c.session, identity: c.identity, source: source, journal: c.journal, currentDraft: { c.draft }, parentCurrent: { c.current })
    }
    private func upload(_ f: ProjectStoryAudioFlow) async throws {
        f.load(); f.stageSelected(try selected()); let claim = try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review))); await f.upload(claim)
    }
    func testIndependentDefaultOffAndPickerOffCannotBorrowImageApproval() async throws {
        let c = Context(), closed = try source(c, enabled: false)
        do { _ = try await closed.upload(selected(), attemptID: UUID(), session: c.session); XCTFail() } catch {}
        XCTAssertTrue(c.wire.requests.isEmpty)
        let configured = try source(c, picker: false); XCTAssertTrue(configured.isCurrent(session: c.session)); XCTAssertFalse(configured.permitsPicker(session: c.session))
    }
    func testExistingMultipartCarriesActualSelectedBytesTypeAndExactFilename() async throws {
        let c = Context(), source = try source(c)
        for ext in ["mp3", "m4a", "aac"] {
            let audio = try selected(ext), receipt = try await source.upload(audio, attemptID: UUID(), session: c.session)
            let request = try XCTUnwrap(c.wire.requests.last), body = try XCTUnwrap(request.httpBody), text = String(decoding: body, as: UTF8.self)
            XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNotNil(body.range(of: audio.bytes)); XCTAssertTrue(text.contains("name=\"fileType\"\r\n\r\n" + ext))
            XCTAssertTrue(text.contains("name=\"fileName\"\r\n\r\n" + audio.filename)); XCTAssertFalse(text.contains("image_free"))
            XCTAssertEqual(Array(receipt.filename.utf8), Array(audio.filename.utf8)); XCTAssertEqual(Array(receipt.reference.utf8), Array(c.wire.reference.utf8))
        }
        XCTAssertEqual(c.wire.requests.count, 3)
    }
    func testCancellingLocalSelectionKeepsPreexistingEmptyAudioBlock() throws {
        let c = Context(), f = try flow(c, source(c)), original = ProjectEditPendingMaterials.exactData(c.draft)
        f.load(); f.stageSelected(try selected()); f.cancelReview(try XCTUnwrap(f.review))
        XCTAssertNil(f.review); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft), original)
        XCTAssertEqual(c.draft.chapters[0].blocks?.last?.kind, .audio); XCTAssertEqual(c.draft.chapters[0].blocks?.last?.url, "")
        XCTAssertTrue(c.wire.requests.isEmpty)
    }
    func testReturnedReferenceFillsOnlyOriginalAudioBlockAndLocalNameIsNotInPayload() async throws {
        let c = Context(), f = try flow(c, source(c)); let block = c.blockID
        try await upload(f); let next = try XCTUnwrap(f.draftForApply())
        XCTAssertEqual(c.draft.chapters[0].blocks?.last?.url, ""); XCTAssertEqual(next.chapters[0].blocks?.count, 3)
        XCTAssertEqual(next.chapters[0].blocks?.last?.id, block)
        XCTAssertEqual(Array(try XCTUnwrap(next.chapters[0].blocks?.last?.localAudio?.filename).utf8), Array("声音 e\u{301}.mp3".utf8))
        let oldRows = try ProjectEditStoryContract.materializedBlocks(c.draft.chapters[0], ordered: c.draft.chapters[0].nodes)
        let rows = try ProjectEditStoryContract.materializedBlocks(next.chapters[0], ordered: next.chapters[0].nodes)
        XCTAssertEqual(oldRows.count, 2); XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(try XCTUnwrap(rows.last?.object).keys), Set(["key", "type", "url"]))
        XCTAssertEqual(Array(try XCTUnwrap(rows.last?.object?["url"]?.text).utf8), Array(c.wire.reference.utf8))
    }
    func testDeleteOrMoveToOtherChapterRejectsLateApplyWithoutRecreatingBlock() async throws {
        let c = Context(), f = try flow(c, source(c)); try await upload(f)
        var other = ProjectEditChapter(); other.blocks = [try XCTUnwrap(c.draft.chapters[0].blocks?.last)]
        c.draft.chapters[0].blocks?.removeLast(); c.draft.chapters.append(other)
        XCTAssertFalse(f.canApply); XCTAssertNil(f.draftForApply()); XCTAssertEqual(c.draft.chapters[0].blocks?.count, 2)
        XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testClosingQueuedClaimRetainsOriginalIntentAndSendsNothing() async throws {
        let c = Context(), f = try flow(c, source(c)); f.load(); f.stageSelected(try selected())
        let claim = try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review))); f.close(); await f.upload(claim)
        XCTAssertTrue(c.wire.requests.isEmpty); XCTAssertEqual(try c.journal.read(session: c.session, identity: c.identity).entries.count, 1)
    }
    func testHeldLate401AfterAccountChangeIsNotCurrentUnauthorized() async throws {
        let c = Context(), source = try source(c), original = c.session, audio = try selected()
        c.wire.held = true; c.wire.started = expectation(description: "actual audio request held")
        let request = Task { try await source.upload(audio, attemptID: UUID(), session: original) }
        await fulfillment(of: [try XCTUnwrap(c.wire.started)], timeout: 3)
        c.session = try .init(accountID: 8, epoch: 2, storageNamespace: original.storageNamespace); c.wire.status = 401; c.wire.raw = Data(); try c.wire.finish()
        do { _ = try await request.value; XCTFail() } catch { XCTAssertEqual(error as? ProjectStoryAudioFailure, .changedContext) }
    }
    func testCurrentEmpty401IsUnauthorizedAndCannotStartAnotherPicker() async throws {
        let c = Context(), f = try flow(c, source(c)); c.wire.status = 401; c.wire.raw = Data()
        try await upload(f); XCTAssertEqual(f.state, .unauthorized); XCTAssertFalse(f.canPick)
        XCTAssertEqual(f.unresolvedUploadCount, 1); XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testOldLocalEnvelopeWithoutAudioMetadataDecodesWithoutInventingFilename() throws {
        let old = Data(#"{"id":"old-audio","kind":"audio","content":"","nodeID":"","url":"  old exact reference  "}"#.utf8)
        let block = try JSONDecoder().decode(ProjectEditBlock.self, from: old)
        XCTAssertNil(block.localAudio); XCTAssertEqual(Array(block.url.utf8), Array("  old exact reference  ".utf8))
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? [String: Any]
        XCTAssertNil(saved?["localAudio"])
    }
    func testKnownReceiptSaveFailureReopensLocallyWithoutUploadingAgain() async throws {
        let c = Context(), source = try source(c), old = try flow(c, source)
        c.wire.beforeReply = { c.storage.failWrites = true }; try await upload(old); XCTAssertTrue(old.hasUnstoredReceipt); old.close()
        c.storage.failWrites = false; let fresh = try flow(c, source); fresh.load(); XCTAssertTrue(fresh.hasUnstoredReceipt)
        fresh.persistReceipt(); XCTAssertTrue(fresh.canApply); XCTAssertEqual(c.wire.requests.count, 1)
        XCTAssertEqual(Array(try XCTUnwrap(fresh.receipt?.filename).utf8), Array("声音 e\u{301}.mp3".utf8))
    }
    func testUnknownUploadHasNoStatusRetryAndReopeningSendsNothing() async throws {
        let c = Context(), source = try source(c), old = try flow(c, source); c.wire.status = 503
        try await upload(old); XCTAssertEqual(old.state, .unknown); old.close()
        let fresh = try flow(c, source); fresh.load(); XCTAssertNil(fresh.receipt); XCTAssertEqual(fresh.unresolvedUploadCount, 1)
        XCTAssertEqual(c.wire.requests.count, 1); XCTAssertEqual(c.draft.chapters[0].blocks?.last?.url, "")
    }
    func testReturnedOriginAndStoryLengthRemainBoundedWithoutTruncatingReceipt() async throws {
        let c = Context(), source = try source(c); c.wire.reference = "https://different.example/audio.mp3"
        do { _ = try await source.upload(selected(), attemptID: UUID(), session: c.session); XCTFail() } catch {}
        c.wire.reference = "https://example.com/" + String(repeating: "x", count: 500)
        let f = try flow(c, source); try await upload(f); XCTAssertNotNil(f.receipt); XCTAssertFalse(f.referenceFitsStory); XCTAssertNil(f.draftForApply())
    }
}
