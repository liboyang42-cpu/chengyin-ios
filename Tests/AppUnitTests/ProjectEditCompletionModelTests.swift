import XCTest
@testable import Questify

@MainActor final class ProjectEditCompletionModelTests: XCTestCase {
    func testThemeDateSyncReviewInvalidationCancelAndLocalRestore() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        // Keep the existing topic revision: replacing the whole draft with a new-topic
        // fixture drops it and correctly makes local restore a revision conflict.
        var initial = ProjectEditSyntheticFixtures.snapshot(); initial.draft.product = .freeExplore
        let service = ProjectEditSyntheticService(snapshot: initial); let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
        await model.load(); let id = model.draft.tickets[0].id
        model.ticketDateSync(id).wrappedValue = true; model.changed(); model.review()
        let frozen = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(frozen.payload["tickets"]?.array?.first?.object?["endTime"], .string("2030-05-30 23:59:59"))
        model.draft.endDate = "2030-06-30"; model.changed()
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(frozen.draft.tickets[0].schedule(in: frozen.draft).end, "2030-05-30 23:59:59")
        await model.submit(frozen); XCTAssertTrue(service.submissions.isEmpty)
        model.review(); let updated = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(updated.payload["tickets"]?.array?.first?.object?["endTime"], .string("2030-06-30 23:59:59"))
        model.cancelReview(); model.leave()
        let reopened = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
        await reopened.load(); XCTAssertTrue(reopened.canRestore); reopened.restore()
        XCTAssertEqual(reopened.draft.baseRevision, initial.draft.baseRevision)
        // Stored fields retain the toggle-time dates; effective dates follow the restored theme.
        XCTAssertEqual(reopened.draft.tickets[0].endTime, "2030-05-30")
        XCTAssertTrue(reopened.ticketDateSync(id).wrappedValue)
        XCTAssertEqual(reopened.draft.tickets[0].schedule(in: reopened.draft).end, "2030-06-30 23:59:59")
        reopened.ticketDateSync(id).wrappedValue = false
        XCTAssertEqual(reopened.draft.tickets[0].schedule(in: reopened.draft).end, "2030-06-30 23:59:59")
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testThemeDateSyncRestoreRejectsMissingOrChangedExistingTopicRevision() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        // Missing saved revision, missing current revision, and stale saved revision all fail closed.
        for (savedRevision, currentRevision) in [("", "fixture-r1"), ("fixture-r1", ""), ("fixture-r1", "fixture-r2"), ("", "")] {
            var initial = ProjectEditSyntheticFixtures.snapshot(); initial.draft.product = .freeExplore
            initial.draft.baseRevision = currentRevision
            var saved = initial.draft; saved.baseRevision = savedRevision
            var ticket = saved.tickets[0]; try ticket.setThemeDateSync(true, in: saved); saved.tickets[0] = ticket
            saved.endDate = "2030-06-30"
            let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
            let identity = try ProjectEditDraftIdentity(topicID: XCTUnwrap(initial.topicID))
            try store.save(saved, session: session, identity: identity)
            let service = ProjectEditSyntheticService(snapshot: initial)
            let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
            await model.load()
            guard case .revisionConflict(let envelope) = model.coordinator.restore else { return XCTFail("Expected existing-topic revision conflict") }
            XCTAssertEqual(envelope.draft, saved)
            XCTAssertFalse(model.canRestore); XCTAssertFalse(model.canEdit)
            let before = model.draft; model.restore()
            XCTAssertEqual(model.draft, before)
            XCTAssertFalse(model.ticketDateSync(ticket.id).wrappedValue)
            model.ticketDateSync(ticket.id).wrappedValue = true; model.saveLocal()
            XCTAssertEqual(model.draft, before)
            guard case .revisionConflict(let retained) = store.load(session: session, identity: identity, baseline: initial.draft) else { return XCTFail("Must retain the conflicted draft") }
            XCTAssertEqual(retained.draft, saved)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testSyncBindingRejectsWhitelistStaleSessionCityAndUnknownMetadata() async throws {
        for restriction in ["whitelist", "epoch", "city", "unknown", "deleted"] {
            var session: ProjectEditSession? = try .init(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
            var initial = ProjectEditSyntheticFixtures.snapshot(scope: restriction == "whitelist" ? .whitelist : .full)
            initial.draft = ProjectEditSyntheticFixtures.draft(product: restriction == "city" ? .city : .freeExplore)
            if restriction == "unknown" { initial.draft.tickets[0].localMetadata["syncWithTheme"] = .string("future") }
            let service = ProjectEditSyntheticService(snapshot: initial)
            let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
            await model.load(); let binding = model.ticketDateSync(model.draft.tickets[0].id)
            if restriction == "epoch" { session = try .init(accountID: 901, epoch: 2, storageNamespace: "fixture-cn") }
            if restriction == "deleted" { model.draft.tickets = [] }
            let before = model.draft; binding.wrappedValue = true
            XCTAssertEqual(model.draft, before); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testTicketSaleEditReviewCancelRestoreThroughExistingModel() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        let initial = ProjectEditSyntheticFixtures.snapshot(); let service = ProjectEditSyntheticService(snapshot: initial)
        let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
        await model.load(); let id = model.draft.tickets[0].id
        var ticket = model.ticket(id).wrappedValue; ticket.saleStartTime = "2030-04-01"; ticket.saleEndTime = "2030-04-30"
        model.ticket(id).wrappedValue = ticket; model.changed(); model.review()
        let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(review.payload["tickets"]?.array?.first?.object?["saleEndTime"], .string("2030-04-30 23:59:59"))
        model.cancelReview(); model.leave()
        let reopened = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
        await reopened.load(); XCTAssertTrue(reopened.canRestore); reopened.restore()
        XCTAssertEqual(reopened.draft.tickets[0].saleStartTime, "2030-04-01")
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testTicketSaleReviewIsImmutableAndCancelledReviewCannotDispatch() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        let service = ProjectEditSyntheticService(); let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: service.snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
        await model.load(); let id = model.draft.tickets[0].id
        var ticket = model.ticket(id).wrappedValue; ticket.saleEndTime = "2030-04-30"
        model.ticket(id).wrappedValue = ticket; model.changed(); model.review()
        let frozen = try XCTUnwrap(model.confirmation)
        ticket.saleEndTime = "2030-04-29"; model.ticket(id).wrappedValue = ticket; model.changed()
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(frozen.payload["tickets"]?.array?.first?.object?["saleEndTime"], .string("2030-04-30 23:59:59"))
        await model.submit(frozen); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testTicketSaleBindingRejectsWhitelistAndReplacedEpoch() async throws {
        var session: ProjectEditSession? = try .init(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        for scope in [ProjectEditScope.whitelist, .full] {
            let initial = ProjectEditSyntheticFixtures.snapshot(scope: scope); let service = ProjectEditSyntheticService(snapshot: initial)
            let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
            await model.load(); let binding = model.ticket(model.draft.tickets[0].id)
            if scope == .full { session = try .init(accountID: 901, epoch: 2, storageNamespace: "fixture-cn") }
            let before = model.draft; var edited = binding.wrappedValue; edited.saleStartTime = "2030-04-01"; binding.wrappedValue = edited
            XCTAssertEqual(model.draft, before); XCTAssertNil(model.confirmation); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testNormalModelLoadsEditsReviewsAndRestoresBingo() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        var initial = ProjectEditSyntheticFixtures.snapshot()
        initial.draft.preserved["completeRuleJson"] = .string(#"{"future":{"keep":true},"nodeCompletion":{"mode":"AT_LEAST","requiredCount":1}}"#)
        let storage = ProjectEditMemoryStorage(); let store = ProjectEditLocalStore(storage: storage)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let coordinator = ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session })
        let model = ProjectEditModel(coordinator: coordinator)
        await model.load(); XCTAssertTrue(model.fullEdit)
        XCTAssertEqual(model.completionRules.wrappedValue.mode, "AT_LEAST")
        var rules = model.completionRules.wrappedValue
        rules.bingoEnabled = true; rules.cells[5].label = "Sixth physical cell"; rules.cells[5].feedbackText = "A small celebration"
        model.completionRules.wrappedValue = rules; model.changed(); model.saveLocal(); model.review()
        let review = try XCTUnwrap(model.confirmation)
        let readback = ProjectEditCompletionRules(raw: review.payload["completeRuleJson"])
        XCTAssertEqual(readback.cells[5].feedbackText, "A small celebration")
        XCTAssertEqual(readback.mode, "AT_LEAST")
        model.cancelReview(); model.leave()
        let reopened = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
        await reopened.load(); XCTAssertTrue(reopened.canRestore); reopened.restore()
        XCTAssertEqual(reopened.completionRules.wrappedValue.cells, rules.cells)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testWhitelistAndUnsupportedSourceBindingsCannotMutateRules() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        for scope in [ProjectEditScope.full, .whitelist] {
            var snapshot = ProjectEditSyntheticFixtures.snapshot(scope: scope)
            if scope == .full { snapshot.draft.preserved["completeRuleJson"] = .string("{future malformed") }
            let service = ProjectEditSyntheticService(snapshot: snapshot)
            let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
            await model.load(); let before = model.draft
            var rules = model.completionRules.wrappedValue; rules.bingoEnabled = true; rules.cells[0].feedbackText = "attempt"
            model.completionRules.wrappedValue = rules
            XCTAssertEqual(model.draft, before)
        }
    }
    func testSessionReplacementClearsImportedRulesAndReview() async throws {
        var session: ProjectEditSession? = try .init(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        let service = ProjectEditSyntheticService()
        let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: service.snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
        await model.load()
        var rules = model.completionRules.wrappedValue; rules.bingoEnabled = true; rules.cells[0].feedbackText = "owner-only draft"
        model.completionRules.wrappedValue = rules; model.review(); XCTAssertNotNil(model.confirmation)
        session = nil; await model.load(force: true)
        XCTAssertNil(model.confirmation); XCTAssertNil(model.draft.completionRules); XCTAssertFalse(model.fullEdit)
        XCTAssertTrue(service.submissions.isEmpty)
    }
}
