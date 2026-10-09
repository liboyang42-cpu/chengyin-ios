import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectStoryImageTests: XCTestCase {
    @MainActor private final class Context {
        var session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "story-image-tests")
        var current = true
        var draft = ProjectEditSyntheticFixtures.draft()
        var approval: ProjectStoryImageUploadApproval?
        let identity = try! ProjectEditDraftIdentity(topicID: 101)
        let storage = ProjectEditMemoryStorage()
        let wire = Wire()
        lazy var journal = ProjectStoryImageJournal(storage: storage)
        init() {
            let c = draft.chapters[0]
            draft.preserved["publishMode"] = .string("pro")
            draft.chapters[0].blocks = [.init(kind: .text, content: c.description), .init(kind: .node, nodeID: c.nodes[0].id)]
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var reference = "https://example.com/story/e%CC%81.jpg?x=1&y=2"
        var status = 200, raw: Data?, beforeReply: (() -> Void)?
        var held = false, started: XCTestExpectation?, continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if held { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            beforeReply?(); return try response()
        }
        func response() throws -> (Data, Int) {
            (try raw ?? JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(status)), "url": .string(reference)]), status)
        }
        func finish() throws { let old = continuation; continuation = nil; old?.resume(returning: try response()) }
    }
    private func source(_ c: Context, enabled: Bool = true, picker: Bool = true) throws -> ProjectStoryImageUploadClient {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        c.approval = enabled ? try .init(baseURL: config.baseURL, namespace: c.session.storageNamespace, accountID: 7, approvedOrigins: ["https://example.com"], nativePicker: picker) : nil
        return .init(configuration: config, approval: c.approval, transport: c.wire, credentials: { c.current ? try? .init(session: c.session, token: "synthetic-story-token") : nil }, currentApproval: { c.approval })
    }
    private func image() throws -> RetainedSelectedImage { try .init(jpeg: Data([255,216,255,1,2]), width: 2, height: 1) }
    private func flow(_ c: Context, source: ProjectStoryImageUploadClient, replacing: String? = nil) throws -> ProjectStoryImageFlow {
        .init(target: try .init(draft: c.draft, identity: c.identity, session: c.session, chapterID: c.draft.chapters[0].id, replacing: replacing), session: c.session, identity: c.identity, source: source, journal: c.journal, currentDraft: { c.draft }, parentCurrent: { c.current })
    }
    private func upload(_ flow: ProjectStoryImageFlow) async throws {
        flow.load(); flow.stageCropped(try image()); let claim = try XCTUnwrap(flow.claimUpload(try XCTUnwrap(flow.review))); await flow.upload(claim)
    }
    func testDefaultCapabilityIsOffAndPickerHasIndependentGate() async throws {
        let c = Context(), closed = try source(c, enabled: false)
        do { _ = try await closed.upload(image(), attemptID: UUID(), session: c.session); XCTFail() } catch {}
        XCTAssertTrue(c.wire.requests.isEmpty)
        let source = try source(c, picker: false); XCTAssertTrue(source.isCurrent(session: c.session)); XCTAssertFalse(source.permitsPicker(session: c.session))
    }
    func testActualClientUsesExistingImageFreeCommandAndExactReturnedURLBytes() async throws {
        let c = Context(), source = try source(c), selected = try image(), id = UUID()
        let receipt = try await source.upload(selected, attemptID: id, session: c.session)
        XCTAssertEqual(receipt.attemptID, id); XCTAssertEqual(Array(receipt.reference.utf8), Array(c.wire.reference.utf8))
        let request = try XCTUnwrap(c.wire.requests.first), body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertNil(request.url?.query)
        XCTAssertNotNil(body.range(of: selected.jpeg)); XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("name=\"bizType\"\r\n\r\nimage_free"))
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("ownerId")); XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testReturnedOriginsControlsDuplicateKeysAndExistingStoryLengthAreNotRelaxed() async throws {
        let c = Context(), source = try source(c)
        for reference in ["file:///tmp/a.jpg", "https://elsewhere.example/story.jpg", "https://example.com/a.jpg\n", "https://user@example.com/a.jpg"] {
            c.wire.reference = reference
            do { _ = try await source.upload(image(), attemptID: UUID(), session: c.session); XCTFail(reference) } catch {}
        }
        c.wire.raw = Data(#"{"code":200,"url":"https://example.com/a.jpg","url":"https://example.com/b.jpg"}"#.utf8)
        do { _ = try await source.upload(image(), attemptID: UUID(), session: c.session); XCTFail() } catch {}
        c.wire.raw = nil; c.wire.reference = "https://example.com/" + String(repeating: "a", count: 500)
        let f = try flow(c, source: source); try await upload(f)
        XCTAssertNotNil(f.receipt); XCTAssertFalse(f.referenceFitsStory); XCTAssertFalse(f.canApply); XCTAssertNil(f.draftForApply())
    }
    func testCloseAfterSynchronousClaimPreservesIntentAndDispatchesNothing() async throws {
        let c = Context(), f = try flow(c, source: source(c)); f.load(); f.stageCropped(try image())
        let claim = try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review)))
        XCTAssertEqual(try c.journal.read(session: c.session, identity: c.identity).entries.count, 1)
        f.close(); await f.upload(claim)
        XCTAssertTrue(c.wire.requests.isEmpty); XCTAssertEqual(f.state, .closed)
    }
    func testLateEmpty401AfterOwnerChangeCannotAffectNewContext() async throws {
        let c = Context(), source = try source(c), captured = c.session
        c.wire.held = true; c.wire.started = expectation(description: "actual upload held")
        let task = Task { try await source.upload(image(), attemptID: UUID(), session: captured) }
        await fulfillment(of: [try XCTUnwrap(c.wire.started)], timeout: 3)
        c.session = try .init(accountID: 8, epoch: 2, storageNamespace: captured.storageNamespace)
        c.wire.raw = Data(); c.wire.status = 401; try c.wire.finish()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? ProjectStoryImageFailure, .changedContext) }
    }
    func testCurrentEmpty401IsUnauthorizedBeforeJSONParsing() async throws {
        let c = Context(), source = try source(c); c.wire.raw = Data(); c.wire.status = 401
        do { _ = try await source.upload(image(), attemptID: UUID(), session: c.session); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let f = try flow(c, source: source); try await upload(f)
        XCTAssertEqual(f.state, .unauthorized); XCTAssertFalse(f.canPick); XCTAssertEqual(f.unresolvedUploadCount, 1)
    }
    func testCancellationNoPlaceholderAndConfirmedApplyPreservesOtherRawStoryFields() async throws {
        let c = Context(), f = try flow(c, source: source(c)), before = ProjectEditPendingMaterials.exactData(c.draft)
        f.load(); f.stageCropped(try image()); f.cancelReview(try XCTUnwrap(f.review))
        XCTAssertNil(f.review); XCTAssertTrue(c.wire.requests.isEmpty); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft), before)
        try await upload(f); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft), before)
        let next = try XCTUnwrap(f.draftForApply()); XCTAssertEqual(next.chapters[0].blocks?.count, 3)
        XCTAssertEqual(next.chapters[0].blocks?.first, c.draft.chapters[0].blocks?.first)
        XCTAssertEqual(Array(try XCTUnwrap(next.chapters[0].blocks?.last?.url).utf8), Array(c.wire.reference.utf8))
    }
    func testReplacementChangesOnlyOriginalBlockAndFullDraftChangesRejectCapturedAction() async throws {
        let c = Context(); var block = ProjectEditBlock(kind: .image, url: "  historical raw\n")
        block.sourceFields = ["future": .string("e\u{301}\t")]; c.draft.chapters[0].blocks?.append(block)
        let f = try flow(c, source: source(c), replacing: block.id); try await upload(f)
        let next = try XCTUnwrap(f.draftForApply()), replaced = try XCTUnwrap(next.chapters[0].blocks?.last)
        XCTAssertEqual(replaced.id, block.id); XCTAssertEqual(replaced.sourceFields, block.sourceFields)
        XCTAssertEqual(c.draft.chapters[0].blocks?.last?.url, block.url)
        c.draft.chapters[0].blocks?.reverse(); XCTAssertFalse(f.canApply); XCTAssertNil(f.draftForApply())
    }
    func testReceivedButUnstoredReceiptSurvivesCloseAndReopenWithoutAnotherHTTP() async throws {
        let c = Context(), source = try source(c), f = try flow(c, source: source)
        c.wire.beforeReply = { c.storage.failWrites = true }; try await upload(f)
        XCTAssertTrue(f.hasUnstoredReceipt); XCTAssertFalse(f.canApply); XCTAssertEqual(c.wire.requests.count, 1); f.close()
        c.storage.failWrites = false; let reopened = try flow(c, source: source); reopened.load()
        XCTAssertTrue(reopened.hasUnstoredReceipt); reopened.persistReceipt()
        XCTAssertFalse(reopened.hasUnstoredReceipt); XCTAssertTrue(reopened.canApply); XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testAppliedDraftSurvivesReceiptWriteFailureAndRecoveredApplyDoesNotDuplicateBlock() async throws {
        let c = Context(), source = try source(c), f = try flow(c, source: source); try await upload(f)
        c.draft = try XCTUnwrap(f.draftForApply()); c.storage.failWrites = true; f.didSaveAppliedDraft()
        XCTAssertEqual(f.state, .localSaveFailed); XCTAssertEqual(c.draft.chapters[0].blocks?.count, 3); f.close()
        c.storage.failWrites = false; let reopened = try flow(c, source: source); reopened.load()
        XCTAssertTrue(reopened.alreadyApplied); XCTAssertEqual(ProjectEditPendingMaterials.exactData(reopened.draftForApply()), ProjectEditPendingMaterials.exactData(c.draft))
        reopened.didSaveAppliedDraft(); XCTAssertEqual(reopened.state, .applied); XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testJournalCASAndPartialBodyFailureDoNotErasePriorIntentOrReceipt() async throws {
        let c = Context(), f = try flow(c, source: source(c)); f.load(); let stale = try c.journal.read(session: c.session, identity: c.identity)
        f.stageCropped(try image()); let claim = try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review)))
        XCTAssertThrowsError(try c.journal.begin(target: f.target, digest: String(repeating: "a", count: 64), expected: stale, session: c.session, identity: c.identity))
        c.wire.status = 503; await f.upload(claim); XCTAssertEqual(f.state, .unknown); XCTAssertEqual(f.unresolvedUploadCount, 1)
        f.close(); let reopened = try flow(c, source: source(c)); reopened.load()
        XCTAssertEqual(reopened.unresolvedUploadCount, 1); XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testStoredReferenceCannotBorrowChangedOriginApproval() async throws {
        let c = Context(), source = try source(c), f = try flow(c, source: source); try await upload(f)
        c.approval = try .init(baseURL: URL(string: "https://example.com")!, namespace: c.session.storageNamespace, accountID: 7, approvedOrigins: ["https://different.example"])
        XCTAssertFalse(f.canApply); XCTAssertNil(f.draftForApply()); XCTAssertEqual(c.wire.requests.count, 1)
    }
}

// Album-append regressions. Authored here; execution requires the Swift test toolchain.
@MainActor extension ProjectStoryImageTests {
    private func albumContext(_ count: Int = 2) -> Context {
        let c = Context()
        var album = ProjectEditBlock(kind: .dream); album.id = "album-é"
        album.sourceFields = ["title": .string(" Raw title "), "images": .array((0..<count).map { index in
            .object(["url": .string("https://example.com/same.jpg"), "line": index == 0 ? .null : .string(" caption e\u{301} ")])
        })]
        c.draft.chapters[0].blocks?.insert(album, at: 1)
        return c
    }
    private func albumTarget(_ c: Context) throws -> ProjectStoryImageTarget {
        try .init(draft: c.draft, identity: c.identity, session: c.session, chapterID: c.draft.chapters[0].id, appendingToAlbum: "album-é")
    }
    private func albumReceipt(_ c: Context) throws -> ProjectStoryUploadedImage {
        try .restore(attemptID: UUID(), ownerKey: c.session.ownerKey, reference: "https://example.com/e%CC%81.jpg")
    }
    func testAlbumAppendPreservesEveryPriorRawFieldAndDuplicatePhotoOrdinal() throws {
        let c = albumContext(), target = try albumTarget(c), receipt = try albumReceipt(c), before = c.draft
        let next = try target.applying(receipt, to: before, identity: c.identity, session: c.session)
        var expected = before
        let raw = try XCTUnwrap(before.chapters[0].blocks?[1].sourceFields?["images"]?.array)
        expected.chapters[0].blocks?[1].sourceFields?["images"] = .array(raw + [.object(["url": .string(receipt.reference), "line": .string("")])])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(before), ProjectEditPendingMaterials.exactData(c.draft))
        XCTAssertTrue(target.hasAppliedReference(receipt, in: next, identity: c.identity, session: c.session))
    }
    func testAlbumZeroThroughFiveCanAppendButSixCannotMintAnotherTarget() throws {
        for count in 0...5 {
            let c = albumContext(count), target = try albumTarget(c), receipt = try albumReceipt(c)
            let next = try target.applying(receipt, to: c.draft, identity: c.identity, session: c.session)
            XCTAssertEqual(next.chapters[0].blocks?[1].sourceFields?["images"]?.array?.count, count + 1)
            XCTAssertTrue(target.hasAppliedReference(receipt, in: next, identity: c.identity, session: c.session))
        }
        XCTAssertThrowsError(try albumTarget(albumContext(6)))
        XCTAssertThrowsError(try albumTarget(albumContext(7)))
    }
    func testAlbumMalformedRawRowsAndUnknownFieldsNeverGetCompactedOrReplaced() throws {
        let rows: [ProjectEditJSON?] = [nil, .null, .string("legacy"), .array([.null]), .array([.string("legacy")]),
            .array([.object(["url": .string(""), "line": .string("")])]),
            .array([.object(["url": .string("https://example.com/a"), "extra": .bool(true)])]),
            .array([.object(["url": .string("https://example.com/a"), "line": .number(1)])]),
            .array([.object(["url": .string(String(repeating: "x", count: 501))])]),
            .array([.object(["url": .string("https://example.com/a"), "line": .string(String(repeating: "😀", count: 41))])])]
        for raw in rows {
            let c = albumContext(); c.draft.chapters[0].blocks?[1].sourceFields?["images"] = raw
            let before = ProjectEditPendingMaterials.exactData(c.draft)
            XCTAssertThrowsError(try albumTarget(c)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft), before)
        }
        let c = albumContext(); c.draft.chapters[0].blocks?[1].sourceFields?["unknown"] = .bool(true)
        XCTAssertThrowsError(try albumTarget(c))
    }
    func testAlbumIdentityRejectsCanonicalAliasesAndDuplicatesAcrossChapters() throws {
        let c = albumContext(), chapter = c.draft.chapters[0]
        XCTAssertThrowsError(try ProjectStoryImageTarget(draft: c.draft, identity: c.identity, session: c.session,
            chapterID: chapter.id, appendingToAlbum: "album-e\u{301}"))
        var other = chapter; other.id = "other"; other.blocks?[1].id = "album-e\u{301}"; c.draft.chapters.append(other)
        XCTAssertThrowsError(try albumTarget(c))
        c.draft.chapters = [chapter, chapter]; XCTAssertThrowsError(try albumTarget(c))
    }
    func testAlbumUnsupportedShapeAndConflictingActionsFailClosed() throws {
        for mode in 0..<6 {
            let c = albumContext()
            switch mode {
            case 0: c.draft.chapters[0].schemaVersion = 2
            case 1: c.draft.chapters[0].blocks?[1].content = "unexpected"
            case 2: c.draft.chapters[0].blocks?[1].url = "unexpected"
            case 3: c.draft.chapters[0].blocks?[1].nodeID = "unexpected"
            case 4: c.draft.chapters[0].blocks?[1].kind = .image
            default: c.draft.chapters[0].blocks?[1].sourceFields?["title"] = .number(1)
            }
            XCTAssertThrowsError(try albumTarget(c))
        }
        let c = albumContext()
        XCTAssertThrowsError(try ProjectStoryImageTarget(draft: c.draft, identity: c.identity, session: c.session,
            chapterID: c.draft.chapters[0].id, replacing: "album-é", appendingToAlbum: "album-é"))
    }
    func testAlbumInverseRequiresExactWholePreimageAndExactLastCaption() throws {
        let c = albumContext(), target = try albumTarget(c), receipt = try albumReceipt(c)
        let applied = try target.applying(receipt, to: c.draft, identity: c.identity, session: c.session)
        for mutation in 0..<7 {
            var changed = applied
            var images = try XCTUnwrap(changed.chapters[0].blocks?[1].sourceFields?["images"]?.array)
            switch mutation {
            case 0: images[0] = .object(["url": .string("https://example.com/same.jpg"), "line": .string("")])
            case 1: images[2] = .object(["url": .string(receipt.reference), "line": .null])
            case 2: images.swapAt(0, 2)
            case 3: changed.chapters[0].blocks?[1].sourceFields?["title"] = .string("Changed")
            case 4: changed.chapters[0].blocks?[0].content += "changed neighbor"
            case 5: changed.chapters[0].blocks?[1].id = "album-e\u{301}"
            default: images.append(images[2])
            }
            changed.chapters[0].blocks?[1].sourceFields?["images"] = .array(images)
            XCTAssertFalse(target.hasAppliedReference(receipt, in: changed, identity: c.identity, session: c.session))
        }
    }
    func testAlbumTargetRejectsStaleDraftOwnerAndOversizedReceipt() throws {
        let c = albumContext(), target = try albumTarget(c), receipt = try albumReceipt(c)
        c.draft.chapters[0].name += "new"
        XCTAssertThrowsError(try target.applying(receipt, to: c.draft, identity: c.identity, session: c.session))
        let other = try ProjectEditSession(accountID: 8, epoch: 2, storageNamespace: c.session.storageNamespace)
        XCTAssertFalse(target.matches(c.draft, identity: c.identity, session: other))
        let fresh = albumContext(), selected = try albumTarget(fresh)
        let large = try ProjectStoryUploadedImage.restore(attemptID: UUID(), ownerKey: fresh.session.ownerKey, reference: "https://example.com/" + String(repeating: "a", count: 500))
        XCTAssertThrowsError(try selected.applying(large, to: fresh.draft, identity: fresh.identity, session: fresh.session))
    }
    func testAlbumActionRoundTripKeepsOldActionEncodingAndExactBytes() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let old: [(ProjectStoryImageTarget.Action, String)] = [(.append, #"{"append":{}}"#), (.replace("a"), #"{"replace":{"_0":"a"}}"#), (.insertBefore("a"), #"{"insertBefore":{"_0":"a"}}"#)]
        for (action, json) in old { XCTAssertEqual(try encoder.encode(action), Data(json.utf8)) }
        let c = albumContext(), target = try albumTarget(c)
        let restored = try JSONDecoder().decode(ProjectStoryImageTarget.self, from: encoder.encode(target))
        XCTAssertEqual(restored, target)
        XCTAssertNotEqual(ProjectStoryImageTarget.Action.appendAlbumImage(Data("é".utf8)), .appendAlbumImage(Data("e\u{301}".utf8)))
    }
    func testAlbumExistingFlowRequiresExplicitUploadThenExplicitAppendAndCanReopenReceipt() async throws {
        let c = albumContext(), selected = try albumTarget(c), source = try source(c), before = ProjectEditPendingMaterials.exactData(c.draft)
        let f = ProjectStoryImageFlow(target: selected, session: c.session, identity: c.identity, source: source, journal: c.journal, currentDraft: { c.draft }, parentCurrent: { c.current })
        f.load(); f.stageCropped(try image()); XCTAssertTrue(c.wire.requests.isEmpty)
        let claim = try XCTUnwrap(f.claimUpload(try XCTUnwrap(f.review))); await f.upload(claim)
        XCTAssertEqual(c.wire.requests.count, 1); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft), before)
        f.close()
        let next = ProjectStoryImageFlow(target: try albumTarget(c), session: c.session, identity: c.identity, source: source, journal: c.journal, currentDraft: { c.draft }, parentCurrent: { c.current })
        next.load(); c.draft = try XCTUnwrap(next.draftForApply()); next.didSaveAppliedDraft()
        XCTAssertEqual(next.state, .applied); XCTAssertEqual(c.draft.chapters[0].blocks?[1].sourceFields?["images"]?.array?.count, 3)
        XCTAssertEqual(c.wire.requests.count, 1)
    }
    func testAlbumSixthPhotoReceiptOnlyRecoveryCannotSelectOrAppendAgain() async throws {
        let c = albumContext(5), selected = try albumTarget(c), source = try source(c)
        let f = ProjectStoryImageFlow(target: selected, session: c.session, identity: c.identity, source: source, journal: c.journal, currentDraft: { c.draft }, parentCurrent: { c.current })
        try await upload(f); c.draft = try XCTUnwrap(f.draftForApply())
        let entry = try XCTUnwrap(c.journal.read(session: c.session, identity: c.identity).entries.last); f.close()
        let next = ProjectStoryImageFlow(target: selected, session: c.session, identity: c.identity, source: source, journal: c.journal,
            recoveryOnly: entry, currentDraft: { c.draft }, parentCurrent: { c.current })
        next.load(); let before = ProjectEditPendingMaterials.exactData(c.draft)
        XCTAssertFalse(next.canPick); XCTAssertNil(next.beginPicking()); XCTAssertTrue(next.alreadyApplied)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next.draftForApply()), ProjectEditPendingMaterials.exactData(Optional(c.draft)))
        next.didSaveAppliedDraft(); XCTAssertEqual(next.state, .applied)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.draft), before); XCTAssertEqual(c.wire.requests.count, 1)
    }
}
