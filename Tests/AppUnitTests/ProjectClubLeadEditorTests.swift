import XCTest
@testable import Questify

@MainActor final class ProjectClubLeadEditorTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "club-lead") }
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
    private func setup(scope: ProjectEditScope = .full, product: ProjectEditProduct = .city) async throws -> (ProjectEditModel, ProjectClubLeadController, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var initial = ProjectEditSnapshot(scope: scope, draft: ProjectEditSyntheticFixtures.draft(product: product))
        initial.draft.preserved["future"] = .object(["opaque": .string("retain")])
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load()
        return (model, .init(model: model), owner, store, storage, service)
    }
    func testNoOpPreservesBytesRevisionAndStorage() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let capture = try XCTUnwrap(controller.capture()), before = model.draft, revision = model.draftMutationRevision, writes = storage.writes
        controller.binding(capture).wrappedValue = true
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.draftMutationRevision, revision)
        XCTAssertEqual(storage.writes, writes); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testChoiceChangesOnlyExistingFieldAndSaveColdRestoreReviewRetainIt() async throws {
        let (model, controller, owner, store, storage, service) = try await setup()
        let capture = try XCTUnwrap(controller.capture()), before = model.draft, writes = storage.writes
        controller.apply(false, captured: capture)
        let expected = try ProjectClubLead.applying(false, to: before)
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(storage.writes, writes)
        controller.apply(true, captured: capture); XCTAssertEqual(model.draft, expected)
        model.saveLocal()
        let fresh = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service,
            store: store, currentSession: { owner.session }))
        await fresh.load(); fresh.restore(); XCTAssertEqual(fresh.draft, expected)
        fresh.review(); XCTAssertEqual(fresh.confirmation?.payload["openClubPool"], .number(0))
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testCapturedBindingCannotMutateAfterDraftABAAndEligibilityChanges() async throws {
        for mutation in ["content", "sameBytes", "contentABA", "club", "clubABA", "product", "owner", "revision", "retire"] {
            let (model, controller, _, _, storage, service) = try await setup()
            let captured = try XCTUnwrap(controller.capture()), original = model.draft
            let binding = controller.binding(captured)
            switch mutation {
            case "content": model.draft.name = "Changed"
            case "sameBytes": model.draft = original
            case "contentABA": model.draft.name = "Changed"; model.draft = original
            case "club": model.draft.clubID = 9
            case "clubABA": model.draft.clubID = 9; model.draft.clubID = nil
            case "product": model.draft.product = .freeExplore
            case "owner": model.draft.owner = .merchant
            case "revision": model.draft.baseRevision = "another"
            default: controller.retire()
            }
            let before = model.draft, writes = storage.writes
            binding.wrappedValue = false
            XCTAssertFalse(controller.isCurrent(captured), mutation)
            XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testAccountEpochLogoutRestoreDiscardAndVisitRetireCallbacks() async throws {
        for mutation in ["account", "epoch", "logout", "restore", "discard", "leave", "visit"] {
            let (model, controller, owner, _, storage, service) = try await setup()
            let captured = try XCTUnwrap(controller.capture())
            switch mutation {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "club-lead")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "club-lead")
            case "logout": owner.session = nil
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            default: model.coordinator.beginEditorVisit(UUID())
            }
            let before = model.draft, writes = storage.writes
            controller.apply(false, captured: captured)
            XCTAssertFalse(controller.isCurrent(captured), mutation)
            XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistFreeExploreClubAndUnsupportedSettingCannotCapture() async throws {
        let (_, limited, _, _, _, _) = try await setup(scope: .whitelist); XCTAssertNil(limited.capture())
        let (_, free, _, _, _, _) = try await setup(product: .freeExplore); XCTAssertNil(free.capture())
        let (model, controller, _, _, _, _) = try await setup()
        model.draft.clubID = 9; XCTAssertNil(controller.capture())
        model.draft.clubID = nil; model.draft.preserved["openClubPool"] = .string("1")
        let before = model.draft; XCTAssertNil(controller.capture())
        controller.apply(false, captured: nil); XCTAssertEqual(model.draft, before)
    }
    func testWrongControllerAndReplacementModelRejectCapture() async throws {
        let (model, controller, _, _, _, _) = try await setup()
        let capture = try XCTUnwrap(controller.capture())
        let other = ProjectClubLeadController(model: model), before = model.draft
        other.apply(false, captured: capture); XCTAssertEqual(model.draft, before)
        let (replacement, _, _, _, _, _) = try await setup()
        XCTAssertFalse(controller.matchesHost(replacement))
        let replacementController = ProjectClubLeadController(model: replacement)
        replacementController.apply(false, captured: capture)
        XCTAssertTrue(ProjectClubLead.isSelected(replacement.draft))
    }
    func testChangedChoiceInvalidatesReviewButFrozenPreparedPayloadStaysImmutable() async throws {
        let (model, controller, _, _, _, service) = try await setup()
        model.review(); let frozen = try XCTUnwrap(model.confirmation)
        let capture = try XCTUnwrap(controller.capture())
        controller.apply(true, captured: capture); XCTAssertNotNil(model.confirmation)
        controller.apply(false, captured: capture); XCTAssertNil(model.confirmation)
        XCTAssertEqual(frozen.payload["openClubPool"], .number(1)); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testFailedLocalSaveIsNotReportedAsSavedAndDoesNotDispatch() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        controller.apply(false, captured: controller.capture()); storage.failWrites = true; model.saveLocal()
        XCTAssertEqual(model.coordinator.messageKey, "projectEdit.localFailed")
        XCTAssertFalse(ProjectClubLead.isSelected(model.draft)); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testUnconfirmedChapterRemovalBlocksPreviouslyCapturedToggle() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let capture = try XCTUnwrap(controller.capture())
        let removal = ProjectChapterRemovalController(model: model)
        removal.open(offsets: IndexSet(integer: 0), captured: removal.capture())
        let confirmation = try XCTUnwrap(removal.confirmation)
        storage.failWrites = true; removal.confirm(confirmation)
        XCTAssertTrue(model.coordinator.hasUnconfirmedChapterRemoval)
        let before = model.draft, writes = storage.writes
        controller.apply(false, captured: capture)
        XCTAssertNil(controller.capture()); XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testUnknownSubmissionLocksToggleAndRetainsPendingIdentity() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let capture = try XCTUnwrap(controller.capture())
        service.scenario = .unknown; model.coordinator.prepare(model.draft)
        await model.coordinator.confirm(try XCTUnwrap(model.coordinator.confirmation))
        let before = model.draft, writes = storage.writes, pending = model.coordinator.pending
        controller.apply(false, captured: capture)
        XCTAssertNil(controller.capture()); XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(model.coordinator.pending?.operationID, pending?.operationID)
        XCTAssertEqual(service.submissions.count, 1) // Only the explicit synthetic confirm above.
    }
}
