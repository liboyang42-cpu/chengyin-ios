import XCTest
import SwiftUI
import UIKit
import Combine
@testable import Questify

@MainActor final class QuickPublishingJourneyOwnerTests: XCTestCase {
    @MainActor private final class Client: PublishingAIDraftServing {
        var session: PublishingSession?
        var canGenerate = true
        var calls = 0
        init(_ session: PublishingSession?) { self.session = session }
        func cancel() {}
        func quota() async throws -> PublishingAIQuota { throw PublishModesError.unavailable }
        func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft { calls += 1; throw PublishModesError.unavailable }
    }
    @MainActor private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var writes = 0
        var fail = false
        func read(_ key: String) throws -> Data? { if fail { throw PublishModesError.storage }; return data[key] }
        func write(_ value: Data, key: String) throws { writes += 1; if fail { throw PublishModesError.storage }; data[key] = value }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func session(_ id: Int = 7) -> PublishingSession { .init(namespace: "quick-test", accountID: id, epoch: UUID(), role: "player", region: .china) }
    private func owner(account: PublishingSession?) -> QuickPublishingJourneyOwner {
        let owner = QuickPublishingJourneyOwner(); owner.bind(account: account); owner.appear(active: true); return owner
    }
    private func draft(_ title: String = "Synthetic walk", count: Int = 2) -> QuickPublishDraft {
        var value = QuickPublishDraft(); value.title = title; value.description = "  Exact e\u{301} story  "
        value.nodes = (0..<count).map { i in var n = QuickPublishNode(); n.name = "Stop \(i)"; n.description = "Unconfirmed task"; return n }
        return value
    }
    private func place(_ id: Int = 1) throws -> PublishingPlace { try .init(id: "synthetic-\(id)", name: "Chosen \(id)", address: "Exact local address", latitude: 31 + Double(id) / 100, longitude: 121) }
    private func openPlace(_ owner: QuickPublishingJourneyOwner, index: Int = 0) throws -> QuickPublishingJourneyOwner.Presentation {
        owner.openPlaceAction(owner.draft.nodes[index].id)(); return try XCTUnwrap(owner.presentation)
    }
    private func openAI(_ owner: QuickPublishingJourneyOwner, client: Client) throws -> QuickPublishingJourneyOwner.Presentation {
        owner.openAIAction(makeClient: { client })(); return try XCTUnwrap(owner.presentation)
    }
    func testNormalAIAdoptionThenEachExplicitPlaceAndProfessionalHandoff() throws {
        let account = session(), owner = owner(account: account), client = Client(account)
        let presentation = try openAI(owner, client: client); var candidate = draft(); candidate.aiTraceID = "synthetic-trace"
        XCTAssertTrue(owner.adopt(candidate, from: presentation)); XCTAssertTrue(owner.draft.nodes.allSatisfy { $0.confirmedPlace == nil })
        var seeds: [ProjectEditDraft] = []
        owner.handoffAction { seeds.append($0) }(); XCTAssertTrue(seeds.isEmpty); XCTAssertTrue(owner.problem)
        for i in owner.draft.nodes.indices { let capture = try openPlace(owner, index: i); XCTAssertTrue(owner.confirm(try place(i + 1), from: capture)) }
        let handoff = owner.handoffAction { seeds.append($0) }; handoff(); handoff()
        XCTAssertEqual(seeds.count, 1); XCTAssertEqual(seeds.first?.chapters.first?.nodes.count, 2)
        XCTAssertEqual(seeds.first?.chapters.first?.nodes.first?.latitude, String(try place().latitude))
        XCTAssertEqual(seeds.first?.preserved["aiTraceId"], .string("synthetic-trace")); XCTAssertEqual(client.calls, 0)
    }
    func testManualGuestCanEditConfirmAndEnterWithoutAIOrPersistence() throws {
        let owner = owner(account: nil); owner.draftBinding().wrappedValue = draft(count: 1)
        let capture = try openPlace(owner); XCTAssertTrue(owner.confirm(try place(), from: capture))
        var count = 0; owner.handoffAction { _ in count += 1 }(); XCTAssertEqual(count, 1)
    }
    func testAIResultNeverSuppliesAlreadyConfirmedCoordinates() throws {
        let account = session(), owner = owner(account: account), client = Client(account)
        let presentation = try openAI(owner, client: client); var candidate = draft(); candidate.nodes[0].confirmedPlace = try place()
        XCTAssertFalse(owner.adopt(candidate, from: presentation)); XCTAssertEqual(owner.draft, QuickPublishDraft())
        XCTAssertTrue(owner.isCurrent(presentation)); XCTAssertEqual(client.calls, 0)
    }
    func testMismatchedAIClientIsNotInstalledOrAccepted() throws {
        let account = session(), owner = owner(account: account), client = Client(session(9))
        let presentation = try openAI(owner, client: client)
        XCTAssertNil(presentation.client); XCTAssertFalse(owner.adopt(draft(), from: presentation)); XCTAssertEqual(client.calls, 0)
    }
    func testAIClientLosingSessionCannotAdoptLateCandidate() throws {
        let account = session(), owner = owner(account: account), client = Client(account)
        let presentation = try openAI(owner, client: client); client.session = nil
        XCTAssertFalse(owner.adopt(draft(), from: presentation)); XCTAssertEqual(owner.draft.title, "")
    }
    func testMalformedProductAndDuplicateNodeAICandidatesAreRejected() throws {
        let account = session(), owner = owner(account: account), client = Client(account)
        let presentation = try openAI(owner, client: client)
        var candidate = draft(); candidate.product = .freeExplore; XCTAssertFalse(owner.adopt(candidate, from: presentation))
        candidate = draft(); candidate.nodes[1] = candidate.nodes[0]; XCTAssertFalse(owner.adopt(candidate, from: presentation))
        candidate = draft(count: 4); XCTAssertFalse(owner.adopt(candidate, from: presentation))
        candidate = draft(""); XCTAssertFalse(owner.adopt(candidate, from: presentation)); XCTAssertEqual(owner.draft.title, "")
    }
    func testCancelledAILeavesAllOriginalInputAndNoSavedState() throws {
        let account = session(), owner = owner(account: account), client = Client(account)
        owner.draftBinding().wrappedValue = draft(); let before = ProjectEditPendingMaterials.exactData(owner.draft), identity = owner.draftID
        let presentation = try openAI(owner, client: client); owner.cancel(presentation)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(owner.draft), before); XCTAssertEqual(owner.draftID, identity)
        XCTAssertFalse(owner.adopt(draft("Late"), from: presentation)); XCTAssertEqual(client.calls, 0)
    }
    func testLatePlaceACannotWriteNewlyOpenedPointB() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let a = try openPlace(owner); owner.cancel(a); let b = try openPlace(owner, index: 1)
        XCTAssertFalse(owner.confirm(try place(), from: a)); XCTAssertNil(owner.draft.nodes[0].confirmedPlace); XCTAssertNil(owner.draft.nodes[1].confirmedPlace)
        XCTAssertTrue(owner.confirm(try place(2), from: b)); XCTAssertNil(owner.draft.nodes[0].confirmedPlace)
        XCTAssertEqual(owner.draft.nodes[1].confirmedPlace, try place(2))
    }
    func testOldModalGetterNilAndCancelCannotTouchNewPresentation() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let a = try openPlace(owner), binding = owner.presentationBinding(a); binding.wrappedValue = nil
        let b = try openPlace(owner, index: 1); binding.wrappedValue = nil; owner.cancel(a)
        XCTAssertNil(binding.wrappedValue); XCTAssertEqual(owner.presentation?.id, b.id)
    }
    func testPlaceConfirmationChangesOnlyChosenPoint() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let before = owner.draft, capture = try openPlace(owner); XCTAssertTrue(owner.confirm(try place(), from: capture))
        var expected = before; expected.nodes[0].confirmedPlace = try place()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(owner.draft), ProjectEditPendingMaterials.exactData(expected))
    }
    func testOwnModalCoverageAllowsExactConfirmationOnReturn() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let capture = try openPlace(owner); owner.parentDisappeared(departing: false, coveredByPresentation: true)
        XCTAssertTrue(owner.isCurrent(capture)); XCTAssertTrue(owner.confirm(try place(), from: capture))
        XCTAssertFalse(owner.canEdit); owner.parentAppeared(); XCTAssertTrue(owner.canEdit)
    }
    func testTrueDepartureWhileModalCoveredRetiresLateResultButKeepsDraft() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft(); let before = owner.draft
        let capture = try openPlace(owner); owner.parentDisappeared(departing: true, coveredByPresentation: true)
        XCTAssertFalse(owner.confirm(try place(), from: capture)); XCTAssertNil(owner.presentation)
        XCTAssertEqual(owner.draft, before); owner.appear(active: true); XCTAssertTrue(owner.canEdit)
    }
    func testUnrelatedCoverageDoesNotCreateVisibleEditingOwner() {
        let owner = owner(account: session()); owner.parentDisappeared(departing: false, coveredByPresentation: true)
        owner.setActive(true); owner.addNodeAction()(); XCTAssertTrue(owner.draft.nodes.isEmpty); XCTAssertFalse(owner.canEdit)
    }
    func testBackgroundRetiresAIAndHiddenForegroundDoesNotReopen() throws {
        let account = session(), owner = owner(account: account), client = Client(account)
        let capture = try openAI(owner, client: client); owner.disappear(); owner.setActive(true)
        XCTAssertFalse(owner.adopt(draft(), from: capture)); XCTAssertNil(owner.presentation); XCTAssertFalse(owner.canEdit)
    }
    func testVisibleBackgroundRejectsOldModalAndAllowsNewExplicitOpening() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft(); let capture = try openPlace(owner)
        owner.setActive(false); owner.setActive(true)
        XCTAssertFalse(owner.confirm(try place(), from: capture)); XCTAssertNil(owner.presentation)
        let next = try openPlace(owner); XCTAssertNotEqual(next.id, capture.id)
    }
    func testAccountSwitchClearsDraftAndOldBindingCannotReadOrWriteNewOwner() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let binding = owner.draftBinding(), capture = try openPlace(owner)
        owner.bind(account: session(8)); owner.draftBinding().wrappedValue = draft("New owner")
        XCTAssertEqual(binding.wrappedValue.title, ""); binding.wrappedValue = draft("Old owner callback")
        XCTAssertFalse(owner.confirm(try place(), from: capture)); XCTAssertEqual(owner.draft.title, "New owner")
    }
    func testDraftSameBytesABAInvalidatesOldOpenAndHandoff() {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let id = owner.draft.nodes[0].id, open = owner.openPlaceAction(id), before = owner.draft
        var value = before; value.title = "Other"; owner.draftBinding().wrappedValue = value; owner.draftBinding().wrappedValue = before
        open(); XCTAssertNil(owner.presentation)
        owner.openPlaceAction(id)(); XCTAssertNotNil(owner.presentation)
    }
    func testModalFreezesParentFieldsAndOldDeletionActions() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let binding = owner.draftBinding(), remove = owner.removeNodeAction(owner.draft.nodes[0].id), before = owner.draft
        _ = try openPlace(owner); binding.wrappedValue = draft("Overwriting"); remove()
        XCTAssertEqual(owner.draft, before)
    }
    func testExplicitSaveRestoreRetainsEveryConfirmedPlaceAndUTF8Input() throws {
        let account = session(), owner = owner(account: account), storage = Storage(), store = PublishingDraftStore(storage: storage)
        owner.draftBinding().wrappedValue = draft(count: 1); let capture = try openPlace(owner)
        XCTAssertTrue(owner.confirm(try place(), from: capture)); let before = owner.draft
        XCTAssertEqual(storage.writes, 0); owner.saveAction(store: store)(); XCTAssertEqual(storage.writes, 2)
        owner.draftBinding().wrappedValue = draft("Changed"); owner.restoreAction(store: store)()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(owner.draft), ProjectEditPendingMaterials.exactData(before))
        XCTAssertEqual(owner.storageMessage, "publishModes.restoredLocal")
    }
    func testRestoreSameSavedIdentityRetiresOldFieldBinding() {
        let owner = owner(account: session()), storage = Storage(), store = PublishingDraftStore(storage: storage)
        owner.draftBinding().wrappedValue = draft(); owner.saveAction(store: store)()
        let old = owner.draftBinding(), identity = owner.draftID; owner.restoreAction(store: store)()
        XCTAssertEqual(owner.draftID, identity); XCTAssertEqual(old.wrappedValue.title, "")
        old.wrappedValue = draft("Stale edit"); XCTAssertEqual(owner.draft.title, "Synthetic walk")
    }
    func testSaveAndRestoreFailureKeepUnsavedDraftAndShowExistingError() {
        let owner = owner(account: session()), storage = Storage(), store = PublishingDraftStore(storage: storage)
        owner.draftBinding().wrappedValue = draft(); let before = owner.draft; storage.fail = true
        owner.saveAction(store: store)(); XCTAssertEqual(owner.storageMessage, "publishModes.storageFailed"); XCTAssertEqual(owner.draft, before)
        owner.restoreAction(store: store)(); XCTAssertEqual(owner.storageMessage, "publishModes.storageFailed"); XCTAssertEqual(owner.draft, before)
    }
    func testGuestAndRetiredSaveCallbacksNeverWriteStore() {
        let storage = Storage(), store = PublishingDraftStore(storage: storage), guest = owner(account: nil)
        guest.draftBinding().wrappedValue = draft(); guest.saveAction(store: store)(); XCTAssertEqual(storage.writes, 0)
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft(); let save = owner.saveAction(store: store)
        owner.disappear(); save(); XCTAssertEqual(storage.writes, 0)
    }
    func testCancelledOpeningCallbackCannotReopenNewRound() throws {
        let owner = owner(account: session()); owner.draftBinding().wrappedValue = draft()
        let open = owner.openPlaceAction(owner.draft.nodes[0].id); open(); owner.cancel(try XCTUnwrap(owner.presentation)); open()
        XCTAssertNil(owner.presentation)
    }
    func testFirstAppearanceAndModalReturnPublishEditableStateToNormalHost() throws {
        let owner = QuickPublishingJourneyOwner(); owner.bind(account: session())
        var changes = 0
        let observation = owner.objectWillChange.sink { changes += 1 }
        XCTAssertFalse(owner.canEdit); owner.appear(active: true)
        XCTAssertTrue(owner.canEdit); XCTAssertGreaterThan(changes, 0)
        owner.draftBinding().wrappedValue = draft(); _ = try openPlace(owner)
        owner.parentDisappeared(departing: false, coveredByPresentation: true)
        owner.cancel(try XCTUnwrap(owner.presentation)); let before = changes
        owner.parentAppeared(); XCTAssertTrue(owner.canEdit); XCTAssertGreaterThan(changes, before)
        withExtendedLifetime(observation) {}
    }
    func testNormalQuickFormConstructsWithoutGeneratingOrSavingInBothLocales() {
        for language in ["en", "zh-Hans"] {
            let account = session(), client = Client(account), storage = Storage(), store = PublishingDraftStore(storage: storage)
            let host = UIHostingController(rootView: QuickPublishingView(placeSearch: nil, account: account, draftStore: store, makeAIDraft: { client }, openProfessional: { _ in XCTFail("Not explicitly chosen") })
                .environment(\.locale, Locale(identifier: language)))
            host.loadViewIfNeeded(); XCTAssertEqual(client.calls, 0); XCTAssertEqual(storage.writes, 0)
        }
    }
}
