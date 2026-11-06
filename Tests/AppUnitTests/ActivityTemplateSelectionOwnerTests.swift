import XCTest
import Foundation
import SwiftUI
@testable import Questify

@MainActor private final class ActivityTemplateTransport: HTTPTransport {
    var reads = 0
    var fail = false
    var onRead: (() async -> Void)?
    var rows: [ProjectEditJSON] = [.object(["id": .number(17), "title": .string("Existing")]),
        .object(["id": .number(18), "title": .string("Story album"), "advancedConfigJson": .string("{\"album\":{\"enabled\":true}}")])]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        XCTAssertEqual(request.url?.path, "/api/template/my-list"); reads += 1
        if let onRead { await onRead() }; if fail { throw URLError(.networkConnectionLost) }
        return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(["rows": .array(rows)])]), 200)
    }
}
@MainActor private final class ActivityTemplateHarness {
    let session = PublishingSession(namespace: "template-choice-tests", accountID: 7, epoch: UUID(), role: "club", region: .china)
    let transport = ActivityTemplateTransport()
    var credentials: PublishingCredentials?
    var draft = ActivityPublishDraft()
    let draftID = UUID()
    let owner = ActivityTemplateSelectionOwner()
    lazy var service = PublishingService(configuration: try! APIConfiguration(baseURL: URL(string: "https://template.example.test")!),
        transport: transport, credentials: { [weak self] in self?.credentials })
    init() throws {
        credentials = try PublishingCredentials(session: session, token: "synthetic-template-token")
        draft.name = "Retain complete activity"; draft.description = "Unsaved e\u{301}"; draft.start = "not-yet-valid"
        owner.bind(session: session, draftID: draftID, draft: draft); owner.parentAppeared()
    }
    func begin() async {
        owner.begin(service: service, expected: owner.actionID, allowed: true); await read()
    }
    func read() async { await owner.read(owner.readID) }
    var binding: Binding<ActivityPublishDraft> { .init(get: { self.draft }, set: { self.draft = $0 }) }
}

@MainActor final class ActivityTemplateSelectionOwnerTests: XCTestCase {
    func testNormalOpenLoadsWithoutChangingOrAutomaticallySelectingDraft() async throws {
        let h = try ActivityTemplateHarness(); let before = ProjectEditPendingMaterials.exactData(h.draft); await h.begin()
        XCTAssertEqual(h.owner.status, .ready); XCTAssertEqual(h.owner.rows.count, 2); XCTAssertNil(h.owner.selected)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(h.draft), before); XCTAssertEqual(h.transport.reads, 1)
    }
    func testExplicitSelectApplyOnlyChangesTemplateReference() async throws {
        let h = try ActivityTemplateHarness(); let before = h.draft; await h.begin()
        h.owner.select(h.owner.rows[0], expected: h.owner.actionID)
        XCTAssertTrue(h.owner.apply(expected: h.owner.actionID, draft: h.binding, session: h.session, draftID: h.draftID, allowed: true))
        XCTAssertEqual(h.draft.playTemplateID?.rawValue, 17); h.draft.playTemplateID = before.playTemplateID
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(h.draft), ProjectEditPendingMaterials.exactData(before)); XCTAssertFalse(h.owner.open)
    }
    func testAlbumCannotBeSelectedOrConfirmed() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.select(h.owner.rows[1], expected: h.owner.actionID)
        XCTAssertNil(h.owner.selected); XCTAssertFalse(h.owner.canApply)
        XCTAssertFalse(h.owner.apply(expected: h.owner.actionID, draft: h.binding, session: h.session, draftID: h.draftID, allowed: true))
    }
    func testCancelPreservesExistingReferenceAndEveryUnsavedField() async throws {
        let h = try ActivityTemplateHarness(); h.draft.playTemplateID = .init(rawValue: 44)
        h.owner.bind(session: h.session, draftID: h.draftID, draft: h.draft); let before = ProjectEditPendingMaterials.exactData(h.draft)
        await h.begin(); h.owner.select(h.owner.rows[0], expected: h.owner.actionID); h.owner.close(h.owner.actionID)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(h.draft), before)
    }
    func testSearchInvalidatesOldSelectionBeforeTaskStarts() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.select(h.owner.rows[0], expected: h.owner.actionID)
        h.owner.keywordBinding().wrappedValue = "new"; XCTAssertFalse(h.owner.canApply)
        h.owner.requestRead(expected: h.owner.actionID); XCTAssertEqual(h.owner.status, .loading); XCTAssertNil(h.owner.selected)
        await h.read(); XCTAssertEqual(h.transport.reads, 2); XCTAssertNil(h.owner.selected)
    }
    func testFailedRefreshRetainsLabelsButNeverAllowsOldSelection() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); let old = h.owner.rows[0]
        h.owner.select(old, expected: h.owner.actionID); h.transport.fail = true; h.owner.requestRead(expected: h.owner.actionID); await h.read()
        XCTAssertEqual(h.owner.status, .failed); XCTAssertTrue(h.owner.rows.contains(old)); h.owner.select(old, expected: h.owner.actionID)
        XCTAssertNil(h.owner.selected); XCTAssertFalse(h.owner.canApply)
    }
    func testMissingReadConfigurationHasHonestUnavailableStateAndNoRequest() async throws {
        let h = try ActivityTemplateHarness(); h.owner.begin(service: nil, expected: h.owner.actionID, allowed: true); await h.read()
        XCTAssertEqual(h.owner.status, .unavailable); XCTAssertEqual(h.transport.reads, 0); XCTAssertFalse(h.owner.canApply)
    }
    func testCreateDoesNotMutateActivityAndReturnRequiresFreshExplicitSelection() async throws {
        let h = try ActivityTemplateHarness(); let before = ProjectEditPendingMaterials.exactData(h.draft); await h.begin()
        h.owner.select(h.owner.rows[0], expected: h.owner.actionID); h.owner.create(expected: h.owner.actionID, available: true)
        let route = try XCTUnwrap(h.owner.creation); XCTAssertNil(h.owner.selected)
        h.transport.rows.append(.object(["id": .number(90), "title": .string("Created elsewhere")]))
        h.owner.closeCreation(route); h.owner.creationDismissed(route); await h.read()
        XCTAssertEqual(h.transport.reads, 2); XCTAssertTrue(h.owner.rows.contains { $0.id.rawValue == 90 }); XCTAssertNil(h.owner.selected)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(h.draft), before); XCTAssertFalse(h.owner.canApply)
    }
    func testDismissBeforeParentVisibleQueuesOneFreshRead() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: true)
        let route = try XCTUnwrap(h.owner.creation)
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true); h.owner.closeCreation(route); h.owner.creationDismissed(route)
        await h.read(); XCTAssertEqual(h.transport.reads, 1)
        h.owner.parentAppeared(); await h.read(); await h.read(); XCTAssertEqual(h.transport.reads, 2)
    }
    func testParentVisibleBeforeDismissAlsoReadsExactlyOnce() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: true)
        let route = try XCTUnwrap(h.owner.creation)
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true); h.owner.closeCreation(route); h.owner.parentAppeared()
        await h.read(); XCTAssertEqual(h.transport.reads, 1)
        h.owner.creationDismissed(route); await h.read(); h.owner.creationDismissed(route); await h.read(); XCTAssertEqual(h.transport.reads, 2)
    }
    func testConcretePresenterRemainsUntilItsDismissalIsConsumed() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: true)
        let route = try XCTUnwrap(h.owner.creation), binding = h.owner.creationBinding(route)
        XCTAssertEqual(binding.wrappedValue?.id, route.id); binding.wrappedValue = nil
        XCTAssertEqual(h.owner.creation?.id, route.id); XCTAssertNil(binding.wrappedValue)
        h.owner.creationDismissed(route); XCTAssertNil(h.owner.creation)
    }
    func testOldCreationBindingReturnAndDismissCannotTouchNewCreation() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: true)
        let old = try XCTUnwrap(h.owner.creation), binding = h.owner.creationBinding(old)
        h.owner.closeCreation(old); h.owner.creationDismissed(old); await h.read()
        h.owner.create(expected: h.owner.actionID, available: true); let fresh = try XCTUnwrap(h.owner.creation)
        binding.wrappedValue = nil; h.owner.closeCreation(old); h.owner.creationDismissed(old)
        XCTAssertNil(binding.wrappedValue); XCTAssertEqual(h.owner.creation?.id, fresh.id)
    }
    func testOldKeywordBindingAndActionsCannotMutateReopenedSelection() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); let old = h.owner.actionID, binding = h.owner.keywordBinding(), row = h.owner.rows[0]
        h.owner.close(old); await h.begin(); h.owner.keywordBinding().wrappedValue = "fresh"
        binding.wrappedValue = "old"; h.owner.select(row, expected: old); h.owner.close(old); h.owner.requestRead(expected: old)
        XCTAssertEqual(binding.wrappedValue, ""); XCTAssertEqual(h.owner.keyword, "fresh"); XCTAssertTrue(h.owner.open); XCTAssertNil(h.owner.selected)
    }
    func testTrueDepartureRetiresEvenWhileCreationCoversParent() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: true)
        let route = try XCTUnwrap(h.owner.creation); h.owner.parentDisappeared(departing: true, coveredByPresentation: true)
        h.owner.creationDismissed(route); h.owner.parentAppeared(); await h.read()
        XCTAssertFalse(h.owner.open); XCTAssertNil(h.owner.creation); XCTAssertEqual(h.transport.reads, 1)
    }
    func testUnrelatedCoverAndBackgroundCannotResumeHiddenOwner() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.parentDisappeared(departing: false, coveredByPresentation: true)
        XCTAssertFalse(h.owner.open); h.owner.setActive(false); h.owner.setActive(true); await h.read(); XCTAssertEqual(h.transport.reads, 1)
    }
    func testDraftOrAccountChangeRetiresPendingCreationAndRejectsLateReturn() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: true)
        let route = try XCTUnwrap(h.owner.creation); h.owner.bind(session: nil, draftID: h.draftID, draft: h.draft)
        h.owner.closeCreation(route); h.owner.creationDismissed(route); XCTAssertFalse(h.owner.open); XCTAssertNil(h.owner.creation)
        XCTAssertEqual(h.transport.reads, 1)
    }
    func testChangedUnsavedInputRejectsApplyEvenBeforeParentRebind() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.select(h.owner.rows[0], expected: h.owner.actionID)
        h.draft.description = "New unsaved input"
        XCTAssertFalse(h.owner.apply(expected: h.owner.actionID, draft: h.binding, session: h.session, draftID: h.draftID, allowed: true))
        XCTAssertNil(h.draft.playTemplateID); XCTAssertEqual(h.draft.description, "New unsaved input")
    }
    func testLateReadCannotPopulateClosedOrReopenedOwner() async throws {
        let h = try ActivityTemplateHarness(); h.transport.onRead = { h.owner.close(h.owner.actionID) }
        await h.begin(); XCTAssertFalse(h.owner.open); XCTAssertTrue(h.owner.rows.isEmpty)
    }
    func testRevokedReaderCannotPublishRows() async throws {
        let h = try ActivityTemplateHarness(); h.transport.onRead = { h.credentials = nil }
        await h.begin(); XCTAssertFalse(h.owner.canApply); XCTAssertTrue(h.owner.rows.isEmpty)
    }
    func testAbsentCreationFactoryDoesNotOpenAnyRoute() async throws {
        let h = try ActivityTemplateHarness(); await h.begin(); h.owner.create(expected: h.owner.actionID, available: false)
        XCTAssertNil(h.owner.creation); XCTAssertEqual(h.transport.reads, 1)
    }
}
