import XCTest
@testable import Questify

@MainActor final class ProjectChapterRemovalTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "chapter-removal") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var writes = 0
        var reads = 0
        var failAt: Int?
        var failReads = false
        var afterRead: (() -> Void)?
        var beforeWrite: (() -> Void)?
        func read(_ key: String) throws -> Data? {
            reads += 1
            if failReads { throw ProjectEditError.persistenceUnavailable }
            let value = data[key]
            let callback = afterRead; afterRead = nil; callback?()
            return value
        }
        func write(_ value: Data, key: String) throws {
            writes += 1
            let callback = beforeWrite; beforeWrite = nil; callback?()
            if writes == failAt { throw ProjectEditError.persistenceUnavailable }
            data[key] = value
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(scope: ProjectEditScope = .full, product: ProjectEditProduct = .city,
                       existing: Bool = false) async throws -> (ProjectEditModel, ProjectChapterRemovalController, Owner, Storage, ProjectEditLocalStore, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var draft = ProjectEditSyntheticFixtures.draft(product: product)
        draft.chapters[0].id = "first-chapter"
        draft.chapters[0].nodes[0].id = "first-node"
        draft.chapters[0].preserved["future"] = .object(["raw": .string("  e\u{301}  ")])
        var other = ProjectEditChapter(); other.id = "other-chapter"; other.name = "Retained chapter"
        other.description = "Retained story"; other.preserved["future"] = .array([.null, .number(8)])
        var otherNode = draft.chapters[0].nodes[0]; otherNode.id = "other-node"; other.nodes = [otherNode]
        draft.chapters.append(other)
        var pending = ProjectEditNode(); pending.id = "pending-node"; pending.name = "Pending material"
        draft.pendingMaterials = [.init(node: pending)]
        if existing { draft.baseRevision = "fixture-r1" }
        let initial = ProjectEditSnapshot(topicID: existing ? 7101 : nil, scope: scope, draft: draft)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load()
        return (model, .init(model: model), owner, storage, store, service)
    }
    private func open(_ controller: ProjectChapterRemovalController, _ offsets: IndexSet = IndexSet(integer: 0)) throws -> ProjectChapterRemovalController.Confirmation {
        controller.open(offsets: offsets, captured: controller.capture())
        return try XCTUnwrap(controller.confirmation)
    }
    private func stored(_ model: ProjectEditModel, _ owner: Owner, _ store: ProjectEditLocalStore) throws -> ProjectEditDraft {
        guard case .ready(let value) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: try XCTUnwrap(model.coordinator.snapshot).draft) else { throw ProjectEditError.persistenceUnavailable }
        return value.draft
    }
    func testOpenAndCancelDoNotDeleteOrWriteAndOldDismissalCannotCloseNewReview() async throws {
        let (model, controller, _, storage, _, service) = try await setup()
        let before = model.draft, writes = storage.writes
        let first = try open(controller), dismissal = controller.binding(controller.confirmation)
        XCTAssertEqual(first.chapters.map(\.id), ["first-chapter"])
        controller.close(first)
        let second = try open(controller, IndexSet(integer: 1))
        dismissal.wrappedValue = nil
        controller.confirm(first)
        XCTAssertEqual(controller.confirmation?.id, second.id)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testExplicitConfirmationPersistsOnlySelectedChapterAndColdRestores() async throws {
        for product in ProjectEditProduct.allCases {
            let (model, controller, owner, storage, store, service) = try await setup(product: product)
            let before = model.draft, confirmation = try open(controller)
            var expected = before; expected.chapters.removeFirst()
            controller.confirm(confirmation)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
            XCTAssertEqual(try stored(model, owner, store), expected)
            let writes = storage.writes
            controller.confirm(confirmation)
            XCTAssertEqual(storage.writes, writes); XCTAssertNil(controller.confirmation)
            let fresh = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service, store: store, currentSession: { owner.session }))
            await fresh.load(); fresh.restore()
            XCTAssertEqual(fresh.draft, expected); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testDeleteAllLeavesCreateChapterUsableWithoutRestoringDeletedContents() async throws {
        let (model, controller, _, _, _, service) = try await setup()
        let pending = model.draft.pendingMaterials
        controller.confirm(try open(controller, IndexSet(integersIn: 0..<2)))
        XCTAssertTrue(model.draft.chapters.isEmpty); XCTAssertEqual(model.draft.pendingMaterials, pending)
        let starter = ProjectEditStarterController(model: model)
        starter.createChapter(lease: model.captureStarterLease(), name: "New chapter")
        XCTAssertEqual(model.draft.chapters.count, 1)
        XCTAssertEqual(model.draft.chapters[0].name, "New chapter")
        XCTAssertTrue(model.draft.chapters[0].nodes.isEmpty); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testRenderedOffsetsNeverResolveAgainstReorderedOrEditedReplacement() async throws {
        for mutation in ["reorder", "delete", "name", "contentABA", "sameBytes"] {
            let (model, controller, _, storage, _, _) = try await setup()
            let capture = try XCTUnwrap(controller.capture()), before = model.draft
            switch mutation {
            case "reorder": model.draft.chapters.reverse()
            case "delete": model.draft.chapters.removeFirst()
            case "name": model.draft.chapters[1].name = "Changed"
            case "contentABA": model.draft.chapters[0].name = "Temporary"; model.draft = before
            default: model.draft = before
            }
            let expected = model.draft, writes = storage.writes
            controller.open(offsets: IndexSet(integer: 0), captured: capture)
            XCTAssertNil(controller.confirmation, mutation)
            XCTAssertEqual(model.draft, expected); XCTAssertEqual(storage.writes, writes)
        }
    }
    func testConfirmationRejectsDraftABAOrTopologyChanges() async throws {
        for mutation in ["reorder", "deleteABA", "contentABA", "topicField", "pending", "retire"] {
            let (model, controller, _, storage, _, service) = try await setup()
            let original = model.draft, confirmation = try open(controller)
            switch mutation {
            case "reorder": model.draft.chapters.reverse()
            case "deleteABA": model.draft.chapters.removeFirst(); model.draft = original
            case "contentABA": model.draft.chapters[0].name = "Temporary"; model.draft = original
            case "topicField": model.draft.description = "Changed"
            case "pending": model.draft.pendingMaterials?.removeAll()
            default: controller.retire()
            }
            let expected = model.draft, writes = storage.writes
            controller.confirm(confirmation)
            XCTAssertFalse(controller.isCurrent(confirmation), mutation)
            XCTAssertEqual(model.draft, expected); XCTAssertEqual(storage.writes, writes)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testOwnerEpochVisitRestoreDiscardAndModeChangesRejectCapturedIntent() async throws {
        for mutation in ["account", "signOut", "epoch", "viewer", "config", "visit", "restore", "discard", "product", "merchant"] {
            let (model, controller, owner, storage, _, service) = try await setup()
            let confirmation = try open(controller)
            switch mutation {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "chapter-removal")
            case "signOut": owner.session = nil
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "chapter-removal")
            case "viewer": owner.session = try .init(accountID: 901, epoch: 1, storageNamespace: "chapter-removal", viewerRevision: 2)
            case "config": owner.session = try .init(accountID: 901, epoch: 1, storageNamespace: "chapter-removal", configurationRevision: 2)
            case "visit": model.coordinator.beginEditorVisit(UUID())
            case "restore": model.restore()
            case "discard": model.discard()
            case "product": model.draft.product = .freeExplore
            default: model.draft.owner = .merchant
            }
            let expected = model.draft, writes = storage.writes
            controller.confirm(confirmation)
            XCTAssertFalse(controller.isCurrent(confirmation), mutation)
            XCTAssertEqual(model.draft, expected); XCTAssertEqual(storage.writes, writes)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistDuplicateIDsInvalidOffsetsAndForeignControllerAreRejected() async throws {
        let (_, limited, _, _, _, _) = try await setup(scope: .whitelist)
        XCTAssertNil(limited.capture()); limited.open(offsets: IndexSet(integer: 0), captured: nil)
        XCTAssertNil(limited.confirmation)
        let (model, controller, _, storage, _, _) = try await setup()
        let capture = try XCTUnwrap(controller.capture()), writes = storage.writes
        controller.open(offsets: [], captured: capture)
        controller.open(offsets: IndexSet(integer: 3), captured: capture)
        XCTAssertNil(controller.confirmation)
        let other = ProjectChapterRemovalController(model: model)
        other.open(offsets: IndexSet(integer: 0), captured: capture)
        XCTAssertNil(other.confirmation)
        model.draft.chapters[1].id = model.draft.chapters[0].id
        XCTAssertNil(controller.capture()); XCTAssertEqual(storage.writes, writes)
    }
    func testReentrantAndQueuedDoubleConfirmationSaveOnlyOnce() async throws {
        let (model, controller, _, storage, _, service) = try await setup()
        let confirmation = try open(controller), writes = storage.writes
        storage.beforeWrite = { controller.confirm(confirmation) }
        controller.confirm(confirmation); controller.confirm(confirmation)
        XCTAssertEqual(storage.writes, writes + 2)
        XCTAssertEqual(model.draft.chapters.map(\.id), ["other-chapter"])
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testEnvelopeAndPointerFailuresKeepPageConsumeIntentAndOnlyReadOriginalIdentity() async throws {
        for offset in [1, 2] {
            let (model, controller, owner, storage, store, service) = try await setup()
            model.saveLocal()
            let before = model.draft, identity = try XCTUnwrap(model.coordinator.identity), confirmation = try open(controller)
            storage.failAt = storage.writes + offset
            controller.confirm(confirmation)
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(model.draft, before)
            let writes = storage.writes
            storage.failAt = nil
            controller.confirm(confirmation)
            controller.open(offsets: IndexSet(integer: 1), captured: confirmation.capture)
            XCTAssertNil(controller.capture()); XCTAssertEqual(storage.writes, writes)
            controller.inspect()
            XCTAssertEqual(controller.readbackResult, offset == 1 ? .original : .removed)
            XCTAssertEqual(model.coordinator.identity, identity)
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(storage.writes, writes)
            XCTAssertEqual(model.draft, before)
            if offset == 1 { XCTAssertEqual(try stored(model, owner, store), before) }
            else { XCTAssertEqual(try stored(model, owner, store).chapters.map(\.id), ["other-chapter"]) }
            controller.close(confirmation)
            XCTAssertTrue(controller.canInspect)
            controller.inspect(); controller.confirm(confirmation)
            XCTAssertNil(controller.confirmation); XCTAssertEqual(storage.writes, writes)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testNewDraftPointerFailureReadsEnvelopeEvenWhenNoActivePointerWasEverSaved() async throws {
        let (model, controller, owner, storage, store, service) = try await setup()
        let identity = try XCTUnwrap(model.coordinator.identity), confirmation = try open(controller)
        storage.failAt = storage.writes + 2
        controller.confirm(confirmation)
        XCTAssertTrue(controller.saveUnconfirmed)
        XCTAssertNil(try store.activeIdentity(session: try XCTUnwrap(owner.session), product: model.draft.product, owner: model.draft.owner))
        let writes = storage.writes
        controller.inspect()
        XCTAssertEqual(controller.readbackResult, .removed)
        XCTAssertEqual(model.coordinator.identity, identity); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(model.draft.chapters.count, 2); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testReadbackOtherMissingAndUnreadableRemainLockedWithoutWrites() async throws {
        for scenario in ["other", "missing", "unavailable"] {
            let (model, controller, owner, storage, store, _) = try await setup()
            model.saveLocal()
            let confirmation = try open(controller)
            storage.failAt = storage.writes + 1
            controller.confirm(confirmation); storage.failAt = nil
            let session = try XCTUnwrap(owner.session), identity = try XCTUnwrap(model.coordinator.identity)
            switch scenario {
            case "other": var other = model.draft; other.name = "Unrelated revision"; try store.save(other, session: session, identity: identity)
            case "missing": try store.remove(session: session, identity: identity)
            default: storage.failReads = true
            }
            let writes = storage.writes
            controller.inspect()
            XCTAssertEqual(controller.readbackResult, scenario == "other" ? .other : (scenario == "missing" ? .missing : .unavailable))
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertNil(controller.capture())
            XCTAssertEqual(storage.writes, writes)
        }
    }
    func testReadbackCannotCrossOwnerOrCoordinatorAndRechecksAfterStorageRead() async throws {
        let (model, controller, owner, storage, _, _) = try await setup()
        let confirmation = try open(controller)
        storage.failAt = storage.writes + 1; controller.confirm(confirmation)
        let reads = storage.reads, writes = storage.writes
        let (replacement, _, _, replacementStorage, _, _) = try await setup()
        let replacementReads = replacementStorage.reads
        XCTAssertEqual(replacement.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
        XCTAssertEqual(replacementStorage.reads, replacementReads)
        owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "chapter-removal")
        XCTAssertEqual(model.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
        XCTAssertEqual(storage.reads, reads)
        owner.session = try .init(accountID: 901, epoch: 1, storageNamespace: "chapter-removal")
        storage.afterRead = { owner.session = nil }
        XCTAssertEqual(model.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
        XCTAssertEqual(storage.writes, writes)
        controller.inspect(); XCTAssertFalse(controller.canInspect)
    }
    func testAuthorityDowngradeAndNewVisitInvalidateReadbackBeforeReadingStorage() async throws {
        let (model, controller, _, storage, _, service) = try await setup(existing: true)
        let confirmation = try open(controller)
        service.snapshot = .init(topicID: 7101, scope: .whitelist, draft: model.draft)
        await model.load(force: true)
        let reads = storage.reads
        XCTAssertEqual(model.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
        XCTAssertEqual(storage.reads, reads); XCTAssertNil(controller.capture())
        model.coordinator.beginEditorVisit(UUID())
        XCTAssertEqual(model.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
    }
    func testUnknownSubmissionCannotBeReplacedByChapterRemoval() async throws {
        let (model, controller, _, storage, _, service) = try await setup()
        let confirmation = try open(controller)
        service.scenario = .unknown
        model.coordinator.prepare(model.draft)
        let submission = try XCTUnwrap(model.coordinator.confirmation)
        await model.coordinator.confirm(submission)
        let pending = model.coordinator.pending, writes = storage.writes, before = model.draft
        controller.confirm(confirmation)
        XCTAssertNil(controller.capture()); XCTAssertEqual(model.draft, before)
        XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(model.coordinator.pending?.operationID, pending?.operationID)
        XCTAssertEqual(service.submissions.count, 1)
    }
    func testFailureThenAllLocalWriteEntrypointsAndLeaveKeepUnknownEnvelopeUntouched() async throws {
        let (model, controller, _, storage, _, service) = try await setup()
        let confirmation = try open(controller), lease = try XCTUnwrap(model.captureStarterLease())
        storage.failAt = storage.writes + 2
        controller.confirm(confirmation); storage.failAt = nil
        let envelope = storage.data, writes = storage.writes, before = model.draft
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        XCTAssertFalse(model.canEdit); XCTAssertFalse(model.canSaveLocal)
        XCTAssertFalse(model.persistLocalChange(before, lease: lease))
        XCTAssertFalse(model.persistExistingStoryChange(before, lease: lease))
        XCTAssertFalse(model.coordinator.saveLocal(before))
        XCTAssertFalse(model.coordinator.canReplaceExistingStoryDraft(before))
        XCTAssertFalse(model.coordinator.replaceExistingStoryDraft(before, replacing: before))
        XCTAssertThrowsError(try model.coordinator.copyForMode(before, to: .freeExplore))
        model.coordinator.discardLocalDraft()
        model.coordinator.prepare(before); XCTAssertNil(model.coordinator.confirmation)
        model.saveLocal(); model.changed(); model.review()
        controller.confirm(confirmation)
        controller.open(offsets: IndexSet(integer: 1), captured: confirmation.capture)
        controller.inspect(); XCTAssertEqual(controller.readbackResult, .removed)
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        controller.close(confirmation); controller.retire(); model.leave()
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(storage.data, envelope)
        XCTAssertEqual(model.draft, before); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testUnconfirmedLatchDoesNotFreezeOtherAccountsOrIndependentCoordinators() async throws {
        let (model, controller, owner, storage, _, _) = try await setup()
        let original = try XCTUnwrap(owner.session), confirmation = try open(controller)
        storage.failAt = storage.writes + 1
        controller.confirm(confirmation); storage.failAt = nil
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "chapter-removal")
        XCTAssertFalse(model.coordinator.hasUnconfirmedChapterRemoval)
        controller.retire(); await model.load(force: true)
        XCTAssertTrue(model.fullEdit); XCTAssertNotNil(controller.capture())
        let writes = storage.writes; model.saveLocal(); XCTAssertGreaterThan(storage.writes, writes)
        let (independent, other, _, _, _, _) = try await setup()
        XCTAssertFalse(independent.coordinator.hasUnconfirmedChapterRemoval)
        XCTAssertNotNil(other.capture())
        // Returning to the same original identity never clears its latch.
        owner.session = original
        await model.load(force: true)
        // No pointer was saved for account 901, so this load may allocate a new
        // independent identity. The captured original token still cannot be reused.
        XCTAssertEqual(model.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
    }
    func testUnconfirmedLatchRemainsForOriginalIdentityAfterReloadAndDoesNotClearOnReadback() async throws {
        let (model, controller, _, storage, _, _) = try await setup(existing: true)
        model.saveLocal()
        let identity = model.coordinator.identity, confirmation = try open(controller)
        storage.failAt = storage.writes + 1
        controller.confirm(confirmation); storage.failAt = nil
        controller.inspect(); XCTAssertEqual(controller.readbackResult, .original)
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        await model.load(force: true)
        XCTAssertEqual(model.coordinator.identity, identity)
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        let writes = storage.writes
        model.saveLocal(); model.leave()
        XCTAssertEqual(storage.writes, writes)
    }
    func testAnotherDraftIdentityInSameCoordinatorIsNotFrozen() async throws {
        let (model, controller, owner, storage, store, _) = try await setup()
        model.saveLocal()
        let originalIdentity = try XCTUnwrap(model.coordinator.identity), confirmation = try open(controller)
        storage.failAt = storage.writes + 1
        controller.confirm(confirmation); storage.failAt = nil
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        // Model another already-authorized writer selecting a different local draft.
        let otherIdentity = try ProjectEditDraftIdentity()
        var other = model.draft; other.name = "Another saved draft"
        try store.save(other, session: try XCTUnwrap(owner.session), identity: otherIdentity)
        await model.load(force: true); model.restore()
        XCTAssertNotEqual(model.coordinator.identity, originalIdentity)
        XCTAssertEqual(model.coordinator.identity, otherIdentity)
        XCTAssertFalse(model.coordinator.hasUnconfirmedChapterRemoval); XCTAssertTrue(model.fullEdit)
        let writes = storage.writes; model.saveLocal(); XCTAssertGreaterThan(storage.writes, writes)
        XCTAssertEqual(model.coordinator.inspectChapterRemoval(confirmation.readback), .stale)
    }
}
