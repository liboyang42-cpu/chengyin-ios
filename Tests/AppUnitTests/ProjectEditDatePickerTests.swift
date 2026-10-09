import XCTest
@testable import Questify

@MainActor final class ProjectEditDatePickerTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try! .init(accountID: 901, epoch: 1, storageNamespace: "date-picker")
    }
    private final class Clock {
        var zone = TimeZone(secondsFromGMT: -7 * 3600)!
        let now = ISO8601DateFormatter().date(from: "2030-05-03T02:15:00Z")!
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws { data[key] = value; writes += 1 }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(field: ProjectEditDateSelection.Field = .start) async throws -> (ProjectEditDatePickerController, Owner, Storage, Clock) {
        let owner = Owner(), storage = Storage(), clock = Clock()
        let draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service,
            store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session }))
        await model.load()
        let controller = ProjectEditDatePickerController(context: .init(model: model, field: field), timeZone: { clock.zone }, now: { clock.now })
        return (controller, owner, storage, clock)
    }
    private func open(_ controller: ProjectEditDatePickerController) throws -> ProjectEditDatePickerController.Presentation {
        controller.open(controller.capture()); return try XCTUnwrap(controller.presentation)
    }
    func testOpenCancelAndUnchangedConfirmationKeepRawBytesAndReview() async throws {
        let (controller, _, storage, _) = try await setup(), model = controller.context.model
        model.draft.startDate = " 2030-05-01T09:15:42 \n"; model.review()
        let review = try XCTUnwrap(model.confirmation), before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
        let first = try open(controller); controller.close(first)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        let next = try open(controller); controller.apply(next.initialDate, to: next, explicitlySelected: false)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertEqual(model.confirmation?.id, review.id); XCTAssertEqual(storage.writes, writes)
    }
    func testExplicitChoiceUsesBeijingValueAndOnlyWorkingDraftChanges() async throws {
        let (controller, _, storage, clock) = try await setup(), model = controller.context.model
        let original = try open(controller), before = model.draft
        controller.apply(clock.now, to: original, explicitlySelected: true)
        var expected = before; expected.startDate = "2030-05-03 10:15:00"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(storage.writes, 0); XCTAssertNil(controller.presentation)
    }
    func testUnknownStoredValueCannotOpenAndEmptyValueNeedsExplicitSelection() async throws {
        let (controller, _, storage, _) = try await setup(), model = controller.context.model
        model.draft.startDate = "unknown old date"; XCTAssertNil(controller.capture())
        controller.open(controller.capture()); XCTAssertNil(controller.presentation)
        XCTAssertEqual(model.draft.startDate, "unknown old date")
        model.draft.startDate = ""; let original = try open(controller)
        controller.apply(original.initialDate, to: original, explicitlySelected: false)
        XCTAssertEqual(model.draft.startDate, ""); XCTAssertNotNil(controller.presentation)
        controller.apply(original.initialDate, to: original, explicitlySelected: true)
        XCTAssertEqual(model.draft.startDate, "2030-05-03 10:15:00"); XCTAssertEqual(storage.writes, 0)
    }
    func testTimeZoneChangeAndChangeBackAfterNotificationRejectOldConfirmation() async throws {
        let (controller, _, _, clock) = try await setup(), model = controller.context.model
        let original = try open(controller), raw = model.draft.startDate, oldZone = clock.zone
        clock.zone = TimeZone(secondsFromGMT: 9 * 3600)!
        controller.apply(clock.now, to: original, explicitlySelected: true)
        XCTAssertEqual(model.draft.startDate, raw); XCTAssertFalse(controller.isCurrent(original))
        controller.retire() // The production timezone-change notification performs this retirement.
        clock.zone = oldZone; controller.apply(clock.now, to: original, explicitlySelected: true)
        XCTAssertEqual(model.draft.startDate, raw)
    }
    func testAccountEpochSameBytesABAAndRestoreRetireOldPicker() async throws {
        for action in ["account", "epoch", "signOut", "aba", "restore"] {
            let (controller, owner, storage, clock) = try await setup(), model = controller.context.model
            let original = try open(controller)
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "date-picker")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "date-picker")
            case "signOut": owner.session = nil
            case "aba": let same = model.draft; model.draft = same
            default: model.saveLocal(); await model.load(force: true); XCTAssertTrue(model.canRestore); model.restore()
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
            controller.apply(clock.now, to: original, explicitlySelected: true)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action)
            XCTAssertEqual(storage.writes, writes)
        }
    }
    func testInvalidRangeLeavesDraftAndPickerThenValidChoiceCanConfirm() async throws {
        let (controller, _, storage, clock) = try await setup(), model = controller.context.model
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(model.draft)
        let late = try XCTUnwrap(ISO8601DateFormatter().date(from: "2031-01-01T00:00:00Z"))
        controller.apply(late, to: original, explicitlySelected: true)
        XCTAssertTrue(controller.invalidRange); XCTAssertNotNil(controller.presentation)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        controller.apply(clock.now, to: original, explicitlySelected: true)
        XCTAssertNil(controller.presentation); XCTAssertEqual(storage.writes, 0)
    }
    func testOldDismissalCannotCloseNewPickerAndChangedSyncPreventsOldTicketChoice() async throws {
        let (controller, _, _, _) = try await setup()
        let first = try open(controller); controller.close(first)
        let second = try open(controller); controller.close(first)
        XCTAssertEqual(controller.presentation?.id, second.id)
        let model = controller.context.model, id = model.draft.tickets[0].id
        let ticket = ProjectEditDatePickerController(context: .init(model: model, field: .ticketStart(id)))
        let original = try open(ticket), before = model.draft.tickets[0].startTime
        model.draft.tickets[0].localMetadata["syncWithTheme"] = .bool(true)
        ticket.apply(original.initialDate.addingTimeInterval(60), to: original, explicitlySelected: true)
        XCTAssertEqual(model.draft.tickets[0].startTime, before); XCTAssertNil(ticket.capture())
    }
}
