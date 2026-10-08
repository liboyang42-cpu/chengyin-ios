import XCTest
@testable import Questify

@MainActor final class ProjectTicketMeetingPointTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "ticket-meeting-point") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var writes = 0
        var failWrites = false
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            writes += 1; if failWrites { throw ProjectEditError.persistenceUnavailable }; data[key] = value
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(scope: ProjectEditScope = .full, product: ProjectEditProduct = .city) async throws -> (ProjectEditModel, ProjectTicketMeetingPointController, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var initial = ProjectEditSnapshot(scope: scope, draft: ProjectEditSyntheticFixtures.draft(product: product))
        initial.draft.tickets[0].localMetadata = ["gatherLng": .number(121), "gatherLat": .number(31), "future": .string("preserved")]
        var other = initial.draft.tickets[0]; other.id = "other-ticket"; other.name = "Another ticket"
        initial.draft.tickets.append(other)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load()
        return (model, .init(model: model, ticketID: model.draft.tickets[0].id), owner, store, storage, service)
    }
    private func open(_ controller: ProjectTicketMeetingPointController) throws -> ProjectTicketMeetingPointController.Presentation {
        controller.open(try XCTUnwrap(controller.capture())); return try XCTUnwrap(controller.presentation)
    }
    private func changed(_ original: ProjectTicketMeetingPointController.Presentation) -> ProjectTicketMeetingPoint {
        var value = original.initial; value.name = "Fixture east gate"; value.address = "Fixture east boardwalk"
        value.longitude = "0"; value.latitude = "0"; return value
    }
    func testOpenCancelAndNoOpDoNotWriteWorkingDraftStorageOrRemote() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision, writes = storage.writes
        let first = try open(controller); controller.close(first)
        controller.apply(changed(first), to: first)
        let second = try open(controller); controller.apply(second.initial, to: second)
        XCTAssertNil(controller.presentation)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertEqual(model.draftMutationRevision, revision); XCTAssertEqual(storage.writes, writes)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testApplyChangesOnlyCapturedTicketThenExistingSaveColdRestoreAndReviewKeepIt() async throws {
        let (model, controller, owner, store, storage, service) = try await setup()
        let before = model.draft, writes = storage.writes, first = try open(controller), edit = changed(first)
        controller.apply(edit, to: first)
        var expected = before; expected.tickets[0] = try edit.applying(to: before.tickets[0])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(storage.writes, writes) // Apply itself is not a durable-save claim.
        let revision = model.draftMutationRevision
        controller.apply(first.initial, to: first)
        XCTAssertEqual(model.draftMutationRevision, revision); XCTAssertNil(controller.presentation)
        model.saveLocal()
        let fresh = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service,
            store: store, currentSession: { owner.session }))
        await fresh.load(); fresh.restore(); XCTAssertEqual(fresh.draft, expected)
        fresh.review(); let review = try XCTUnwrap(fresh.confirmation)
        let wire = try XCTUnwrap(review.payload["tickets"]?.array?.first?.object)
        XCTAssertEqual(wire["gatherLng"], .number(0)); XCTAssertEqual(wire["gatherLat"], .number(0))
        XCTAssertEqual(wire["meetingPointAddress"], .string(edit.address)); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testDraftMutationDeleteReorderAndSameByteABARetireEditor() async throws {
        for mutation in ["delete", "reorder", "deleteABA", "contentABA", "sameBytes", "retire"] {
            let (model, controller, _, _, storage, service) = try await setup()
            let initial = model.draft, original = try open(controller)
            switch mutation {
            case "delete": model.draft.tickets.removeFirst()
            case "reorder": model.draft.tickets.reverse()
            case "deleteABA": model.draft.tickets.removeFirst(); model.draft = initial
            case "contentABA": model.draft.name = "Temporary"; model.draft.name = initial.name
            case "sameBytes": model.draft = initial
            default: controller.retire()
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
            controller.apply(changed(original), to: original)
            XCTAssertFalse(controller.isCurrent(original), mutation)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.writes, writes)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testAccountEpochLogoutRestoreDiscardVisitAndModeRetireCapturedCallbacks() async throws {
        for mutation in ["account", "epoch", "logout", "restore", "discard", "leave", "visit", "product"] {
            let (model, controller, owner, _, storage, service) = try await setup()
            let original = try open(controller)
            switch mutation {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "ticket-meeting-point")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "ticket-meeting-point")
            case "logout": owner.session = nil
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            case "visit": model.coordinator.beginEditorVisit(UUID())
            default: model.draft.product = .freeExplore
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
            controller.apply(changed(original), to: original)
            XCTAssertFalse(controller.isCurrent(original), mutation)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.writes, writes)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistFreeExploreDuplicateAndUnsupportedTicketCannotOpen() async throws {
        let (_, limited, _, _, _, _) = try await setup(scope: .whitelist)
        XCTAssertNil(limited.capture())
        let (_, free, _, _, _, _) = try await setup(product: .freeExplore)
        XCTAssertNil(free.capture())
        let (model, controller, _, _, storage, _) = try await setup()
        model.draft.tickets[0].localMetadata["gatherLng"] = .string("121")
        let before = model.draft, writes = storage.writes
        XCTAssertNil(controller.capture()); controller.open(nil); XCTAssertNil(controller.presentation)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        model.draft.tickets[0].localMetadata["gatherLng"] = .number(121)
        model.draft.tickets[1].id = model.draft.tickets[0].id
        XCTAssertNil(controller.ticket); XCTAssertNil(controller.capture())
    }
    func testWrongControllerReplacementHostAndOldDismissalCannotAffectNewSheet() async throws {
        let (model, first, owner, _, storage, service) = try await setup()
        let old = try open(first)
        let other = ProjectTicketMeetingPointController(model: model, ticketID: "other-ticket")
        other.open(old.capture); XCTAssertNil(other.presentation)
        first.close(old); let current = try open(first)
        first.close(old); XCTAssertEqual(first.presentation?.id, current.id)
        first.apply(changed(old), to: old); XCTAssertEqual(first.presentation?.id, current.id)
        let secondModel = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service,
            store: .init(storage: Storage()), currentSession: { owner.session }))
        await secondModel.load()
        XCTAssertFalse(first.matchesHost(model: secondModel, ticketID: first.ticketID))
        let replacement = ProjectTicketMeetingPointController(model: secondModel, ticketID: first.ticketID)
        replacement.open(current.capture); XCTAssertNil(replacement.presentation)
        let before = model.draft, writes = storage.writes
        first.retire(); first.apply(changed(current), to: current)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
    }
    func testInvalidCoordinateApplyStaysOpenAndReviewIsInvalidatedOnlyByActualChange() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let original = try open(controller), writes = storage.writes, before = model.draft
        var invalid = changed(original); invalid.latitude = ""
        controller.apply(invalid, to: original)
        XCTAssertEqual(controller.presentation?.id, original.id); XCTAssertEqual(model.draft, before)
        XCTAssertEqual(storage.writes, writes)
        model.review(); let review = try XCTUnwrap(model.confirmation)
        let frozen = review.payload
        controller.apply(changed(original), to: original)
        XCTAssertNil(model.confirmation); XCTAssertEqual(review.payload, frozen)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testUnconfirmedChapterRemovalFreezeBlocksOpenAndQueuedTicketApply() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let ticketOpening = try open(controller)
        let removal = ProjectChapterRemovalController(model: model)
        removal.open(offsets: IndexSet(integer: 0), captured: removal.capture())
        let confirmation = try XCTUnwrap(removal.confirmation)
        storage.failWrites = true; removal.confirm(confirmation)
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval); XCTAssertFalse(model.fullEdit)
        let before = model.draft, writes = storage.writes
        controller.apply(changed(ticketOpening), to: ticketOpening)
        XCTAssertNil(controller.capture()); XCTAssertFalse(controller.isCurrent(ticketOpening))
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testUnknownSubmissionLocksWorkingDraftAndPreparedPayload() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let original = try open(controller)
        service.scenario = .unknown; model.coordinator.prepare(model.draft)
        await model.coordinator.confirm(try XCTUnwrap(model.coordinator.confirmation))
        let before = model.draft, writes = storage.writes, pending = model.coordinator.pending
        controller.apply(changed(original), to: original)
        XCTAssertNil(controller.capture()); XCTAssertFalse(controller.isCurrent(original))
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(model.coordinator.pending?.operationID, pending?.operationID)
        XCTAssertEqual(service.submissions.count, 1) // Only the explicit synthetic confirm above.
    }
}
