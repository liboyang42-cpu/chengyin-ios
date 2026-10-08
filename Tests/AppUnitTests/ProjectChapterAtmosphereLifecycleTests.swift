import XCTest
@testable import Questify

@MainActor final class ProjectChapterAtmosphereLifecycleTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "chapter-atmosphere") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var writes = 0
        var failAt: Int?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            writes += 1
            if writes == failAt { throw ProjectEditError.persistenceUnavailable }
            data[key] = value
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(scope: ProjectEditScope = .full, product: ProjectEditProduct = .city) async throws -> (ProjectEditModel, ProjectChapterAtmosphereController, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var initial = ProjectEditSnapshot(scope: scope, draft: ProjectEditSyntheticFixtures.draft(product: product))
        initial.draft.chapters[0].preserved["atmospherePreset"] = .string("NIGHT")
        initial.draft.chapters[0].preserved["future"] = .object(["retained": .bool(true)])
        var other = initial.draft.chapters[0]; other.id = "other-chapter"; other.name = "Another chapter"
        other.nodes[0].id = "other-node"; initial.draft.chapters.append(other)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load()
        return (model, .init(model: model, chapterID: model.draft.chapters[0].id), owner, store, storage, service)
    }
    private func stored(_ model: ProjectEditModel, _ owner: Owner, _ store: ProjectEditLocalStore) throws -> ProjectEditDraft {
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: try XCTUnwrap(model.coordinator.snapshot).draft) else { throw ProjectEditError.persistenceUnavailable }
        return envelope.draft
    }
    func testShowingClosingAndReopeningNeverRewriteLegacyOrWriteStorage() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let before = model.draft, writes = storage.writes
        XCTAssertNotNil(controller.capture())
        XCTAssertEqual(controller.chapter.flatMap { ProjectChapterAtmosphere.selected(in: $0) }, .blue)
        controller.retire(); XCTAssertNotNil(controller.capture())
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testExplicitSelectionPersistsOnlyTargetAndColdRestoresIntoExistingPayload() async throws {
        let (model, controller, owner, store, storage, service) = try await setup()
        let before = model.draft, tap = try XCTUnwrap(controller.capture())
        controller.select(.yellow, captured: tap)
        var expected = before; expected.chapters[0].preserved["atmospherePreset"] = .string("YELLOW")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(try stored(model, owner, store), expected)
        let writes = storage.writes
        controller.select(.red, captured: tap) // queued second tap on the retired render
        controller.select(.yellow, captured: controller.capture()) // current already-canonical no-op
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(storage.writes, writes)
        let fresh = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service, store: store, currentSession: { owner.session }))
        await fresh.load(); fresh.restore(); XCTAssertEqual(fresh.draft, expected)
        fresh.review(); let review = try XCTUnwrap(fresh.confirmation)
        XCTAssertEqual(review.payload["chapters"]?.array?.first?.object?["atmospherePreset"], .string("YELLOW"))
        XCTAssertEqual(review.payload["chapters"]?.array?[1].object?["atmospherePreset"], .string("NIGHT"))
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testExplicitlyChoosingDisplayedAliasCanonicalizesOnlyOnTap() async throws {
        let (model, controller, _, _, storage, _) = try await setup()
        XCTAssertEqual(model.draft.chapters[0].preserved["atmospherePreset"], .string("NIGHT"))
        let writes = storage.writes
        controller.select(.blue, captured: controller.capture())
        XCTAssertEqual(model.draft.chapters[0].preserved["atmospherePreset"], .string("BLUE"))
        XCTAssertGreaterThan(storage.writes, writes)
        XCTAssertEqual(model.draft.chapters[1].preserved["atmospherePreset"], .string("NIGHT"))
    }
    func testDeleteReorderSameBytesAndHostDisappearanceRetireQueuedSelection() async throws {
        for mutation in ["delete", "reorder", "deleteABA", "contentABA", "retire"] {
            let (model, controller, _, _, storage, service) = try await setup()
            let initial = model.draft, tap = try XCTUnwrap(controller.capture())
            switch mutation {
            case "delete": model.draft.chapters.removeFirst()
            case "reorder": model.draft.chapters.reverse()
            case "deleteABA": model.draft.chapters.removeFirst(); model.draft.chapters = initial.chapters
            case "contentABA": model.draft.chapters[0].name = "Temporary"; model.draft.chapters[0].name = initial.chapters[0].name
            default: controller.retire()
            }
            let before = model.draft, writes = storage.writes
            controller.select(.white, captured: tap)
            XCTAssertFalse(controller.isCurrent(tap), mutation)
            XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
            if mutation == "reorder" {
                controller.select(.red, captured: controller.capture())
                XCTAssertEqual(model.draft.chapters.first(where: { $0.id == controller.hostIdentity.chapterID })?.preserved["atmospherePreset"], .string("RED"))
                XCTAssertEqual(model.draft.chapters[0], before.chapters[0])
            }
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testSessionRestoreDiscardVisitAndProductChangesRetireCapturedTap() async throws {
        for mutation in ["account", "signOut", "leave", "restore", "discard", "visit", "product"] {
            let (model, controller, owner, _, storage, service) = try await setup()
            let tap = try XCTUnwrap(controller.capture())
            switch mutation {
            case "account": owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "chapter-atmosphere")
            case "signOut": owner.session = nil
            case "leave": model.leave()
            case "restore": model.restore()
            case "discard": model.discard()
            case "visit": model.coordinator.beginEditorVisit(UUID())
            default: model.draft.product = .freeExplore
            }
            let before = model.draft, writes = storage.writes
            controller.select(.white, captured: tap)
            XCTAssertFalse(controller.isCurrent(tap), mutation)
            XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistFreeExploreAndDuplicateChapterCannotSelectUnknownRequiresExplicitChoice() async throws {
        let (_, limited, _, _, _, _) = try await setup(scope: .whitelist)
        XCTAssertNil(limited.capture())
        let (_, free, _, _, _, _) = try await setup(product: .freeExplore)
        XCTAssertNil(free.capture())
        let (model, controller, _, _, storage, _) = try await setup()
        for raw in [ProjectEditJSON.string("FUTURE"), .object(["color": .string("BLUE")])] {
            model.draft.chapters[0].preserved["atmospherePreset"] = raw
            let before = model.draft, writes = storage.writes
            let tap = try XCTUnwrap(controller.capture()); controller.select(.black, captured: nil)
            XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
            controller.select(.white, captured: tap)
            XCTAssertEqual(model.draft.chapters[0].preserved["atmospherePreset"], .string("WHITE"))
        }
        model.draft.chapters[0].preserved["atmospherePreset"] = .string("BLUE")
        model.draft.chapters[1].id = model.draft.chapters[0].id
        XCTAssertNil(controller.capture())
    }
    func testFailedEnvelopeOrPointerSaveKeepsDisplayedValueAndAllowsSameChoiceRetry() async throws {
        for offset in [1, 2] {
            let (model, controller, owner, store, storage, service) = try await setup()
            model.saveLocal(); let before = model.draft, tap = try XCTUnwrap(controller.capture())
            storage.failAt = storage.writes + offset
            controller.select(.red, captured: tap)
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(model.draft, before)
            if offset == 1 { XCTAssertEqual(try stored(model, owner, store), before) }
            else { XCTAssertEqual(try stored(model, owner, store).chapters[0].preserved["atmospherePreset"], .string("RED")) }
            storage.failAt = nil; controller.select(.red, captured: tap)
            XCTAssertFalse(controller.saveUnconfirmed)
            XCTAssertEqual(model.draft.chapters[0].preserved["atmospherePreset"], .string("RED"))
            XCTAssertEqual(try stored(model, owner, store), model.draft)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testReplacementModelAndChapterCannotReuseCapturedTap() async throws {
        let (first, old, owner, _, storage, service) = try await setup()
        let tap = try XCTUnwrap(old.capture())
        let second = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(first.coordinator.snapshot), service: service,
            store: .init(storage: Storage()), currentSession: { owner.session }))
        await second.load()
        let replacement = ProjectChapterAtmosphereController(model: second, chapterID: old.hostIdentity.chapterID)
        XCTAssertFalse(old.matchesHost(model: second, chapterID: old.hostIdentity.chapterID))
        let firstBefore = first.draft, secondBefore = second.draft, writes = storage.writes
        replacement.select(.red, captured: tap)
        XCTAssertEqual(second.draft, secondBefore)
        old.retire(); old.select(.white, captured: tap)
        XCTAssertEqual(first.draft, firstBefore); XCTAssertEqual(storage.writes, writes)
        let other = ProjectChapterAtmosphereController(model: second, chapterID: "other-chapter")
        other.select(.yellow, captured: replacement.capture())
        XCTAssertEqual(second.draft, secondBefore)
        replacement.select(.white, captured: replacement.capture())
        XCTAssertEqual(second.draft.chapters[0].preserved["atmospherePreset"], .string("WHITE"))
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testPendingSubmissionRetiresTapAndCannotChangePreparedOperation() async throws {
        let (model, controller, _, _, storage, service) = try await setup()
        let tap = try XCTUnwrap(controller.capture())
        service.scenario = .unknown
        model.coordinator.prepare(model.draft)
        let review = try XCTUnwrap(model.coordinator.confirmation)
        await model.coordinator.confirm(review)
        let before = model.draft, writes = storage.writes, operation = model.coordinator.pending
        controller.select(.red, captured: tap)
        XCTAssertFalse(controller.isCurrent(tap)); XCTAssertNil(controller.capture())
        XCTAssertEqual(model.draft, before); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(model.coordinator.pending?.operationID, operation?.operationID)
        XCTAssertEqual(service.submissions.count, 1) // Only the explicit synthetic confirm above.
    }
    func testUnknownAuthoritativeValueColdRestoresAndCannotPrepareUntilExplicitReplacement() async throws {
        for raw in [ProjectEditJSON.string("FUTURE"), .object(["palette": .string("MIDNIGHT")]),
                    .string(""), .string("\u{FEFF}BLUE"), .string("\u{00A0}BLUE"), .string("NIGHT\u{00A0}")] {
            var envelope = try JSONDecoder().decode([String: ProjectEditJSON].self, from: ProjectEditRemoteFixtures.detail(product: .city))
            var body = try XCTUnwrap(envelope["data"]?.object), chapter = try XCTUnwrap(body["chapters"]?.array?.first?.object)
            chapter["atmospherePreset"] = raw; body["chapters"] = .array([.object(chapter)]); envelope["data"] = .object(body)
            let snapshot = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(envelope), expectedTopicID: 71, owner: .personal)
            let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
            let service = ProjectEditSyntheticService(snapshot: snapshot)
            let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: store, currentSession: { owner.session }))
            await model.load(); model.saveLocal()
            XCTAssertEqual(try stored(model, owner, store).chapters[0].preserved["atmospherePreset"], raw)
            let fresh = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: store, currentSession: { owner.session }))
            await fresh.load(); fresh.restore()
            XCTAssertEqual(fresh.draft.chapters[0].preserved["atmospherePreset"], raw)
            fresh.review(); XCTAssertNil(fresh.confirmation)
            XCTAssertEqual(fresh.draft.chapters[0].preserved["atmospherePreset"], raw)
            let controller = ProjectChapterAtmosphereController(model: fresh, chapterID: fresh.draft.chapters[0].id)
            XCTAssertNil(controller.chapter.flatMap {
                ProjectChapterAtmosphere.canSubmit($0) ? ProjectChapterAtmosphere.selected(in: $0) : nil
            })
            controller.select(.blue, captured: controller.capture())
            fresh.review(); let prepared = try XCTUnwrap(fresh.confirmation)
            XCTAssertEqual(prepared.payload["chapters"]?.array?.first?.object?["atmospherePreset"], .string("BLUE"))
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
}
