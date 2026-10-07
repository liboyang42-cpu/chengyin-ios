import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProjectMerchantDraftControllerTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 7, epoch: 1, storageNamespace: "merchant-draft-controller") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ data: Data, key: String) throws { self.data[key] = data }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private final class Reader: ProjectMerchantDraftReading {
        let identity = UUID()
        let owner: Owner
        let captured: ProjectEditSession?
        var enabled = true
        var pages: [ProjectMerchantDraftPage] = []
        var cursors: [Int?] = []
        var resolves = 0
        var holdList = false, holdResolve = false
        var started: XCTestExpectation?
        var pendingLists: [CheckedContinuation<ProjectMerchantDraftPage, Error>] = []
        var pendingResolve: CheckedContinuation<ProjectMerchantDraftResolution, Error>?
        var resolution: ProjectMerchantDraftResolution?
        var error: Error?
        init(_ owner: Owner) { self.owner = owner; captured = owner.session }
        func isCurrent(session: ProjectEditSession) -> Bool { enabled && captured == session && owner.session == session }
        func list(beforeSourceID: Int?, session: ProjectEditSession) async throws -> ProjectMerchantDraftPage {
            cursors.append(beforeSourceID); started?.fulfill()
            if holdList { return try await withCheckedThrowingContinuation { pendingLists.append($0) } }
            if let error { throw error }; return pages.removeFirst()
        }
        func resolve(_ choice: ProjectMerchantDraftChoice, merchantRowID: Int, session: ProjectEditSession) async throws -> ProjectMerchantDraftResolution {
            resolves += 1; started?.fulfill()
            if holdResolve { return try await withCheckedThrowingContinuation { pendingResolve = $0 } }
            if let error { throw error }
            return resolution ?? .init(ownerMemberID: session.accountID, merchantRowID: merchantRowID, choice: choice)
        }
    }
    private func row(_ id: Int = 50, template: Int = 61, available: Bool = true) -> ProjectMerchantDraftRow {
        let source = ProjectMerchantDraftSource(sourceID: id, contentHash: String(repeating: "a", count: 64))
        return .init(sourceID: id, memberTemplateID: template, choice: available ? .init(memberTemplateID: template, title: "Saved merchant draft", source: source, templateContentHash: String(repeating: "b", count: 64)) : nil)
    }
    private func page(_ rows: [ProjectMerchantDraftRow]? = nil, next: Int? = nil, merchant: Int = 8) -> ProjectMerchantDraftPage {
        .init(ownerMemberID: 7, merchantRowID: merchant, rows: rows ?? [row()], nextBeforeSourceID: next)
    }
    private func setup(_ initial: ProjectEditDraft? = nil, withReader: Bool = true) async throws -> (ProjectEditModel, Owner, Reader, ProjectEditLocalStore, ProjectEditSyntheticService) {
        let owner = try Owner(), reader = Reader(owner), store = ProjectEditLocalStore(storage: Storage())
        let draft = initial ?? ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let snapshot = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: snapshot)
        let coordinator = ProjectEditCoordinator(initial: snapshot, service: service, store: store, merchantDraftSource: withReader ? reader : nil, currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: coordinator); await model.load()
        return (model, owner, reader, store, service)
    }
    private func controller(_ model: ProjectEditModel) throws -> ProjectMerchantDraftController {
        let chapter = try XCTUnwrap(model.draft.chapters.first), nodeID = try XCTUnwrap(chapter.nodes.first?.id)
        let binding = Binding<ProjectEditNode>(get: { model.draft.chapters.first { $0.id == chapter.id }?.nodes.first { $0.id == nodeID } ?? .init() }, set: { value in
            guard model.fullEdit, let c = model.draft.chapters.firstIndex(where: { $0.id == chapter.id }),
                  let n = model.draft.chapters[c].nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            model.draft.chapters[c].nodes[n] = value
        })
        return .init(context: .init(model: model, node: binding, sourceID: "saved:\(chapter.id):\(nodeID)",
            nodeRevision: { model.draftMutationRevision }, isCurrent: { model.fullEdit && model.draft.chapters.contains { $0.id == chapter.id && $0.nodes.contains { $0.id == nodeID } } }))
    }
    private func ready(_ controller: ProjectMerchantDraftController, _ reader: Reader) async throws -> ProjectMerchantDraftController.Review {
        reader.pages = [page()]; controller.open(); let review = try XCTUnwrap(controller.review)
        await controller.refresh(review)?.value; XCTAssertEqual(controller.state, .ready); return review
    }
    func testDefaultUnconfiguredNeverOpensOrReads() async throws {
        let (model, _, reader, _, _) = try await setup(withReader: false), picker = try controller(model)
        XCTAssertFalse(picker.available); picker.open(); XCTAssertNil(picker.review); XCTAssertTrue(reader.cursors.isEmpty)
    }
    func testSelectionResolvesThenChangesOnlyTemplateAndExistingSaveRestores() async throws {
        let (model, owner, reader, store, service) = try await setup(), picker = try controller(model), initial = model.draft
        let review = try await ready(picker, reader); picker.select(row(), review: review)
        await picker.apply(try XCTUnwrap(picker.selection), review: review)?.value
        XCTAssertNil(picker.review); XCTAssertEqual(reader.resolves, 1)
        var expected = initial; expected.chapters[0].nodes[0].templateID = 61
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected)); XCTAssertTrue(service.submissions.isEmpty)
        model.saveLocal()
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: initial) else { return XCTFail("saved draft") }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(envelope.draft), ProjectEditPendingMaterials.exactData(expected))
    }
    func testFullListContinuesPastUnavailablePageAndEmptyIsNotFailure() async throws {
        let (model, _, reader, _, _) = try await setup(), picker = try controller(model)
        let first = (0..<20).map { row(100 - $0, template: 200 - $0, available: false) }
        let second = (0..<20).map { row(80 - $0, template: 180 - $0) }
        reader.pages = [page(first, next: 81), page(second, next: 61), page([row(60, template: 160), row(59, template: 159)])]
        picker.open(); let review = try XCTUnwrap(picker.review)
        await picker.refresh(review)?.value; picker.select(first[0], review: review); XCTAssertNil(picker.selection)
        await picker.loadMore(review)?.value; await picker.loadMore(review)?.value
        XCTAssertEqual(picker.rows.count, 42); XCTAssertNil(picker.nextBeforeSourceID); XCTAssertEqual(reader.cursors, [nil, 81, 61])
        reader.pages = [page([])]; await picker.refresh(review)?.value
        XCTAssertEqual(picker.state, .ready); XCTAssertTrue(picker.rows.isEmpty)
    }
    func testCrossPageDuplicatesOrMerchantReplacementInvalidateAllChoices() async throws {
        for changedMerchant in [false, true] {
            let (model, _, reader, _, _) = try await setup(), picker = try controller(model)
            reader.pages = [page([row()], next: 50), page([changedMerchant ? row(49, template: 62) : row()], merchant: changedMerchant ? 9 : 8)]
            picker.open(); let review = try XCTUnwrap(picker.review); await picker.refresh(review)?.value
            picker.select(row(), review: review); await picker.loadMore(review)?.value
            XCTAssertTrue(picker.rows.isEmpty); XCTAssertNil(picker.selection); XCTAssertNotEqual(picker.state, .ready)
        }
    }
    func testRepeatedOpenLoadAndApplyCannotResolveTwice() async throws {
        let (model, _, reader, _, _) = try await setup(), picker = try controller(model)
        let review = try await ready(picker, reader); picker.open(); XCTAssertEqual(picker.review?.id, review.id)
        picker.select(row(), review: review); let selected = try XCTUnwrap(picker.selection)
        reader.holdResolve = true; reader.started = expectation(description: "resolve started")
        let first = picker.apply(selected, review: review); XCTAssertNil(picker.apply(selected, review: review)); XCTAssertNil(picker.refresh(review))
        await fulfillment(of: [try XCTUnwrap(reader.started)], timeout: 2)
        reader.pendingResolve?.resume(returning: .init(ownerMemberID: 7, merchantRowID: 8, choice: selected.choice)); reader.pendingResolve = nil
        await first?.value; XCTAssertEqual(reader.resolves, 1)
    }
    func testCancelAndReopenDiscardLatePageAndOldDismissal() async throws {
        let (model, _, reader, _, _) = try await setup(), picker = try controller(model)
        reader.holdList = true; reader.started = expectation(description: "old list")
        picker.open(); let old = try XCTUnwrap(picker.review), pending = picker.refresh(old)
        await fulfillment(of: [try XCTUnwrap(reader.started)], timeout: 2); picker.cancel(old)
        reader.holdList = false; reader.started = nil; let current = try await ready(picker, reader)
        picker.cancel(old); reader.pendingLists.removeFirst().resume(returning: page([row(99, template: 999)])); await pending?.value
        XCTAssertEqual(picker.review?.id, current.id); XCTAssertEqual(picker.rows, [row()]); XCTAssertNil(picker.selection)
    }
    func testCancelledResolveCannotModifyNodeOrRecoveredDraft() async throws {
        let (model, _, reader, _, service) = try await setup(), picker = try controller(model), initial = model.draft
        let review = try await ready(picker, reader); picker.select(row(), review: review); let selected = try XCTUnwrap(picker.selection)
        reader.holdResolve = true; reader.started = expectation(description: "resolve")
        let pending = picker.apply(selected, review: review); await fulfillment(of: [try XCTUnwrap(reader.started)], timeout: 2)
        picker.cancel(review); reader.pendingResolve?.resume(returning: .init(ownerMemberID: 7, merchantRowID: 8, choice: selected.choice)); reader.pendingResolve = nil; await pending?.value
        XCTAssertEqual(model.draft, initial); XCTAssertNil(picker.review); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testStaleOrUnauthorizedResolveNeverBecomesLocalSuccess() async throws {
        let failures: [Error] = [APIError.unauthorized, ProjectMerchantDraftError.forbidden, ProjectMerchantDraftError.sourceChanged, ProjectMerchantDraftError.unavailable]
        for error in failures {
            let (model, _, reader, _, _) = try await setup(), picker = try controller(model), initial = model.draft
            let review = try await ready(picker, reader); picker.select(row(), review: review); reader.error = error
            await picker.apply(try XCTUnwrap(picker.selection), review: review)?.value
            XCTAssertEqual(model.draft, initial); XCTAssertNil(picker.selection); XCTAssertTrue(picker.rows.isEmpty); XCTAssertNotEqual(picker.state, .ready)
        }
    }
    func testOwnerEpochViewerConfigurationAndDraftABAInvalidateSelection() async throws {
        for action in ["account", "epoch", "viewer", "configuration", "draftABA", "nodeABA", "restore", "leave", "revoked"] {
            let (model, owner, reader, _, _) = try await setup(), picker = try controller(model)
            let review = try await ready(picker, reader); picker.select(row(), review: review); let selected = try XCTUnwrap(picker.selection)
            switch action {
            case "account": owner.session = try .init(accountID: 8, epoch: 1, storageNamespace: "merchant-draft-controller")
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "merchant-draft-controller")
            case "viewer": owner.session = try .init(accountID: 7, epoch: 1, storageNamespace: "merchant-draft-controller", viewerRevision: 1)
            case "configuration": owner.session = try .init(accountID: 7, epoch: 1, storageNamespace: "merchant-draft-controller", configurationRevision: 1)
            case "draftABA": let old = model.draft.name; model.draft.name = "temporary"; model.draft.name = old
            case "nodeABA": let old = model.draft.chapters[0].nodes[0].name; model.draft.chapters[0].nodes[0].name = "temporary"; model.draft.chapters[0].nodes[0].name = old
            case "restore": model.restore()
            case "leave": model.leave()
            default: reader.enabled = false
            }
            let current = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(picker.isCurrent(review), action); XCTAssertNil(picker.apply(selected, review: review), action)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), current); XCTAssertEqual(reader.resolves, 0)
        }
    }
    func testStarterCandidateABAAndDismissalAreFencedWithoutChangingExistingFinish() async throws {
        let (model, _, reader, _, _) = try await setup(ProjectEditDraft(product: .freeExplore)), starter = ProjectEditStarterController(model: model)
        starter.createChapter(lease: model.captureStarterLease(), name: "Chapter")
        let destination = try XCTUnwrap(starter.destination), binding = starter.node(for: destination)
        var named = binding.wrappedValue; named.name = "Local pending node"; binding.wrappedValue = named
        let picker = ProjectMerchantDraftController(context: .init(model: model, node: binding, sourceID: "starter:\(destination.id)", nodeRevision: { starter.candidateRevision }, isCurrent: { starter.isCurrent(destination) }))
        let old = try await ready(picker, reader); picker.select(row(), review: old); let selected = try XCTUnwrap(picker.selection)
        var changed = named; changed.name = "Temporary"; binding.wrappedValue = changed; binding.wrappedValue = named
        XCTAssertFalse(picker.isCurrent(old)); XCTAssertNil(picker.apply(selected, review: old)); picker.cancel(old)
        let current = try await ready(picker, reader); picker.select(row(), review: current)
        await picker.apply(try XCTUnwrap(picker.selection), review: current)?.value
        XCTAssertEqual(starter.candidate.templateID, 61); XCTAssertEqual(starter.candidate.name, named.name)
        starter.finish(destination); XCTAssertNil(starter.destination)
        XCTAssertEqual(model.draft.pendingMaterials?.first?.node.templateID, 61)
    }
    func testPendingCandidateABAAndExistingSavedEnvelopeRemainExact() async throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore), pending = ProjectEditNode(); pending.name = "Pending"; pending.localMetadata["future"] = .bool(true)
        draft.pendingMaterials = [.init(node: pending)]
        let (model, owner, reader, store, _) = try await setup(draft), editor = ProjectEditPendingController(model: model)
        editor.open(editor.capture(pending.id)); let destination = try XCTUnwrap(editor.destination), binding = editor.node(for: destination)
        let picker = ProjectMerchantDraftController(context: .init(model: model, node: binding, sourceID: "pending:\(destination.id)", nodeRevision: { editor.candidateRevision }, isCurrent: { editor.isCurrent(destination) }))
        let old = try await ready(picker, reader); var changed = pending; changed.name = "Temporary"; binding.wrappedValue = changed; binding.wrappedValue = pending
        XCTAssertFalse(picker.isCurrent(old)); picker.cancel(old)
        let current = try await ready(picker, reader); picker.select(row(), review: current); await picker.apply(try XCTUnwrap(picker.selection), review: current)?.value
        editor.save(destination); var expected = draft; expected.pendingMaterials?[0].node.templateID = 61
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: draft) else { return XCTFail("saved pending") }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(envelope.draft), ProjectEditPendingMaterials.exactData(expected))
    }
    func testOuterRouteRejectsQueryExtrasWrongMethodAndCrossRouteFields() throws {
        let base = URL(string: "https://example.com")!
        func request(_ path: String, _ body: [String: ProjectEditJSON], method: String = "POST") throws -> URLRequest {
            var value = URLRequest(url: base.appendingPathComponent(path)); value.httpMethod = method
            value.setValue("application/json", forHTTPHeaderField: "Content-Type"); value.httpBody = try JSONEncoder().encode(body); return value
        }
        let list = try request(ProjectMerchantDraftPath.list, ["beforeSourceId": .null])
        XCTAssertEqual(ApprovedReleaseCompositionRoute(request: list, baseURL: base)?.feature, .merchantDraftSelectionList)
        let resolve = try request(ProjectMerchantDraftPath.resolve, try XCTUnwrap(row().choice).resolveFields)
        XCTAssertEqual(ApprovedReleaseCompositionRoute(request: resolve, baseURL: base)?.feature, .merchantDraftSelectionResolve)
        var query = list; query.url = URL(string: list.url!.absoluteString + "?owner=7")
        XCTAssertNil(ApprovedReleaseCompositionRoute(request: query, baseURL: base))
        XCTAssertNil(ApprovedReleaseCompositionRoute(request: try request(ProjectMerchantDraftPath.list, ["beforeSourceId": .null, "ownerMemberId": .number(7)]), baseURL: base))
        XCTAssertNil(ApprovedReleaseCompositionRoute(request: try request(ProjectMerchantDraftPath.list, ["beforeSourceId": .null], method: "GET"), baseURL: base))
        XCTAssertNil(ApprovedReleaseCompositionRoute(request: try request(ProjectMerchantDraftPath.resolve, ["beforeSourceId": .null]), baseURL: base))
    }
}
