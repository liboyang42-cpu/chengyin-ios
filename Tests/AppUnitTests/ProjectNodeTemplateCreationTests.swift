import XCTest
@testable import Questify

/// Injected in-memory writers/readers only. No socket, credential or real template is created.
@MainActor final class ProjectNodeTemplateCreationTests: XCTestCase {
    private final class Owner {
        var project: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "create-node")
        var author: TemplateAuthoringSession? = try? .init(accountID: 7, namespace: "create-node", epoch: 1, authorizationRevision: "creator")
    }
    @MainActor private final class Writer: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var response = #"{"code":200,"data":88}"#, calls = 0
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) { calls += 1; return (Data(response.utf8), 200) }
    }
    @MainActor private final class Reader: ProjectStoryTemplateReading {
        var identity = UUID(), permitted = true, holdNext = false
        let owner: Owner
        var reads: [Int] = [], lists = 0
        var pending: CheckedContinuation<ProjectStoryTemplateDraft, Error>?, held: ProjectStoryTemplateDraft?
        init(owner: Owner) { self.owner = owner }
        func isCurrent(session: ProjectEditSession) -> Bool { permitted && owner.project == session }
        func list(page: Int, session: ProjectEditSession) async throws -> ProjectStoryTemplatePage {
            lists += 1; throw ProjectStoryTemplateError.unsupported // A receipt is never replaced by a guessed shelf row.
        }
        func detail(id: MemberPlayTemplateID, session: ProjectEditSession) async throws -> ProjectStoryTemplateDraft {
            reads.append(id.rawValue)
            let raw: ProjectEditJSON = .object(["id": .number(Decimal(id.rawValue)), "memberId": .number(Decimal(session.accountID)), "draftStatus": .number(0),
                "delFlag": .number(0), "title": .string("Saved node game"), "validationMethod": .number(0), "answer": .string("private")])
            let value = try ProjectStoryTemplateDraft.decode(raw, accountID: session.accountID, requestedID: id)
            if holdNext { holdNext = false; held = value; return try await withCheckedThrowingContinuation { pending = $0 } }
            return value
        }
        func release() { let continuation = pending; pending = nil; if let held { continuation?.resume(returning: held) }; held = nil }
    }
    @MainActor private struct Context {
        let owner: Owner, writer: Writer, reader: Reader, authorStorage: TemplateAuthoringMemoryStorage, projectStorage: ProjectEditMemoryStorage
        let author: TemplateAuthoringCoordinator, model: ProjectEditModel, creator: ProjectNodeTemplateCreationController
        var launch: ProjectNodeTemplateCreationLaunch { .init(coordinator: author, sessionRevision: 1, metadataReader: nil, imageSelectionApproved: { false }) }
    }
    private func setup() async throws -> Context {
        let owner = Owner(), writer = Writer(), reader = Reader(owner: owner)
        let authorStorage = TemplateAuthoringMemoryStorage(), projectStorage = ProjectEditMemoryStorage()
        let author = TemplateAuthoringCoordinator(adapter: .init(transport: writer), store: .init(storage: authorStorage), currentSession: { owner.author })
        let draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: projectStorage), storyTemplateSource: reader, currentSession: { owner.project }))
        await model.load()
        return .init(owner: owner, writer: writer, reader: reader, authorStorage: authorStorage, projectStorage: projectStorage, author: author, model: model,
            creator: .init(model: model, chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id))
    }
    private func open(_ c: Context) throws -> ProjectNodeTemplateCreationController.Opening {
        c.creator.open({ c.launch }); return try XCTUnwrap(c.creator.opening)
    }
    private func save(_ c: Context) async throws {
        c.author.change(TemplateAuthoringSyntheticFixtures.draft()); c.author.prepare(.saveDraft)
        await c.author.confirm(try XCTUnwrap(c.author.review))
    }
    func testReturnedIDIsOwnerReadTwiceAndOnlyExplicitBindingChangesOriginalNode() async throws {
        let c = try await setup(), opening = try open(c), before = ProjectEditPendingMaterials.exactData(c.model.draft)
        try await save(c); let saved = try XCTUnwrap(c.author.savedDraft)
        XCTAssertEqual(saved.memberTemplateID.rawValue, 88); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        let read = try XCTUnwrap(c.creator.accept(saved, original: opening)); await read.value
        XCTAssertEqual(c.reader.reads, [88]); XCTAssertEqual(c.reader.lists, 0)
        let review = try XCTUnwrap(c.creator.selector.review)
        let apply = try XCTUnwrap(c.creator.apply(review, original: opening)); await apply.value
        XCTAssertEqual(c.reader.reads, [88, 88]); XCTAssertEqual(c.writer.calls, 1)
        XCTAssertEqual(c.model.draft.chapters[0].nodes[0].templateID, 88)
        XCTAssertFalse(String(decoding: try XCTUnwrap(ProjectEditPendingMaterials.exactData(c.model.draft)), as: UTF8.self).contains("private"))
    }
    func testCancelOrSameByteParentReplacementKeepsSavedReceiptButNeverReturnsToOldNode() async throws {
        for cancelled in [true, false] {
            let c = try await setup(), opening = try open(c); try await save(c)
            let saved = try XCTUnwrap(c.author.savedDraft)
            if cancelled { c.creator.close(opening) } else { let same = c.model.draft; c.model.draft = same }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft)
            XCTAssertFalse(c.creator.canReturn(saved, original: opening)); XCTAssertNil(c.creator.accept(saved, original: opening))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before); XCTAssertEqual(c.author.savedDraft, saved); XCTAssertTrue(c.reader.reads.isEmpty)
        }
    }
    func testMissingSimulatedAndUnknownResultsHaveNoReturnableIDOrAutomaticResubmit() async throws {
        for kind in ["missing", "simulated", "unknown"] {
            let c = try await setup(), opening = try open(c)
            if kind == "missing" { c.writer.response = #"{"code":200}"# }
            if kind == "simulated" { c.writer.authority = .synthetic }
            if kind == "unknown" { c.writer.response = "unreadable" }
            try await save(c); XCTAssertNil(c.author.savedDraft); XCTAssertTrue(c.reader.reads.isEmpty)
            c.creator.close(opening); c.creator.open({ c.launch })
            XCTAssertNil(c.creator.opening); XCTAssertEqual(c.writer.calls, 1)
        }
    }
    func testExplicitNewAfterRealReceiptKeepsOldJournalAndCannotReuseOldID() async throws {
        let c = try await setup(), oldOpening = try open(c); try await save(c)
        let oldReceipt = try XCTUnwrap(c.author.savedDraft), oldIdentity = c.author.identity
        c.creator.close(oldOpening); let next = try open(c)
        XCTAssertNotEqual(c.author.identity, oldIdentity); XCTAssertNil(c.author.savedDraft)
        XCTAssertFalse(c.creator.canReturn(oldReceipt, original: next)); XCTAssertEqual(c.writer.calls, 1)
        let store = TemplateAuthoringLocalStore(storage: c.authorStorage)
        XCTAssertEqual(try store.pending(session: try XCTUnwrap(c.owner.author), identity: oldIdentity)?.savedDraft, oldReceipt)
    }
    func testHeldOwnerReadCannotCrossNodeDeletionOrSourceRevocation() async throws {
        for revoke in [true, false] {
            let c = try await setup(), opening = try open(c); try await save(c); let saved = try XCTUnwrap(c.author.savedDraft)
            c.reader.holdNext = true; let task = try XCTUnwrap(c.creator.accept(saved, original: opening))
            for _ in 0..<100 where c.reader.pending == nil { await Task.yield() }; XCTAssertNotNil(c.reader.pending)
            if revoke { c.reader.identity = UUID(); c.reader.permitted = false } else { c.model.draft.chapters[0].nodes.removeFirst() }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); c.reader.release(); await task.value
            XCTAssertNil(c.creator.selector.review); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
            XCTAssertEqual(c.writer.calls, 1)
        }
    }
    func testAccountMismatchAndFailedNodeSaveCannotLoseOriginalOrCreateAnotherTemplate() async throws {
        let c = try await setup(); c.owner.author = try .init(accountID: 8, namespace: "create-node", epoch: 1, authorizationRevision: "creator")
        c.creator.open({ c.launch }); XCTAssertNil(c.creator.opening); XCTAssertEqual(c.writer.calls, 0)
        let current = try await setup(), opening = try open(current); try await save(current)
        let saved = try XCTUnwrap(current.author.savedDraft), read = try XCTUnwrap(current.creator.accept(saved, original: opening)); await read.value
        let before = ProjectEditPendingMaterials.exactData(current.model.draft), review = try XCTUnwrap(current.creator.selector.review)
        current.projectStorage.failWrites = true; let apply = try XCTUnwrap(current.creator.apply(review, original: opening)); await apply.value
        XCTAssertEqual(current.creator.selector.state, .saveFailed); XCTAssertEqual(ProjectEditPendingMaterials.exactData(current.model.draft), before)
        XCTAssertEqual(current.writer.calls, 1); XCTAssertEqual(current.author.savedDraft, saved)
    }
    func testAuthorIdentityChangeBeforeBindRejectsOldReceiptWithoutASecondRead() async throws {
        let c = try await setup(), opening = try open(c); try await save(c)
        let saved = try XCTUnwrap(c.author.savedDraft), read = try XCTUnwrap(c.creator.accept(saved, original: opening)); await read.value
        let review = try XCTUnwrap(c.creator.selector.review), before = ProjectEditPendingMaterials.exactData(c.model.draft)
        XCTAssertTrue(c.author.beginNewDraft(after: saved))
        XCTAssertNil(c.creator.apply(review, original: opening)); XCTAssertEqual(c.reader.reads, [88])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before); XCTAssertEqual(c.writer.calls, 1)
    }
    func testHeldSecondOwnerReadCannotOutliveAuthorIdentityOrSession() async throws {
        for changeIdentity in [true, false] {
            let c = try await setup(), opening = try open(c); try await save(c)
            let saved = try XCTUnwrap(c.author.savedDraft), read = try XCTUnwrap(c.creator.accept(saved, original: opening)); await read.value
            let review = try XCTUnwrap(c.creator.selector.review), before = ProjectEditPendingMaterials.exactData(c.model.draft)
            c.reader.holdNext = true; let apply = try XCTUnwrap(c.creator.apply(review, original: opening))
            for _ in 0..<100 where c.reader.pending == nil { await Task.yield() }; XCTAssertNotNil(c.reader.pending)
            if changeIdentity { XCTAssertTrue(c.author.beginNewDraft(after: saved)) }
            else { c.owner.author = try .init(accountID: 7, namespace: "create-node", epoch: 1, authorizationRevision: "changed") }
            c.reader.release(); await apply.value
            XCTAssertEqual(c.reader.reads, [88, 88]); XCTAssertEqual(c.writer.calls, 1)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
            XCTAssertNil(c.creator.selector.review); XCTAssertNil(c.creator.selector.opening)
            let store = TemplateAuthoringLocalStore(storage: c.authorStorage)
            XCTAssertEqual(try store.pending(session: opening.authorSession, identity: saved.identity)?.savedDraft, saved)
        }
    }

}
