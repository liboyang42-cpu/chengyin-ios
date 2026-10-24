import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ActivityPublishingLocalClearTests: XCTestCase {
    @MainActor private final class Harness {
        let owner = ActivityPublishingLocalClearOwner()
        var account: PublishingSession? = .init(namespace: "activity-local-fixture", accountID: 71, epoch: UUID(), role: "club_owner", region: .china)
        var draftID = UUID()
        var draft: ActivityPublishDraft
        var allowed = true
        var assignments = 0
        init() {
            var value = ActivityPublishDraft()
            value.name = "Original name"; value.description = "Unsaved description e\u{301}"
            value.coverURL = "fixture://cover/original?exact=1"; value.addressName = "Original place"
            value.place = try? PublishingPlace(id: "fixture-place", name: "Place", address: "Exact address", latitude: 31, longitude: 121)
            value.start = "2030-01-01 09:00:00"; value.end = "2030-01-01 18:00:00"
            value.playTemplateID = AuthoringPlayTemplateID(rawValue: 41)
            value.categoryIDs = [3, 8]; value.collaboratorMemberIDs = [71, 72]
            for number in 1...2 {
                var ticket = ActivityPublishTicket()
                ticket.name = "Ticket \(number)"; ticket.price = "0"; ticket.stock = "007"
                ticket.start = value.start; ticket.end = value.end
                value.tickets.append(ticket)
            }
            draft = value; bind(); owner.appear(active: true)
        }
        func bind() { owner.bind(account: account, draftID: draftID, draft: draft, editable: allowed) }
        var binding: Binding<ActivityPublishDraft> {
            .init(get: { self.draft }, set: { self.assignments += 1; self.draft = $0; self.bind() })
        }
        func action(_ field: ActivityPublishingLocalClearOwner.Field) -> () -> Void {
            owner.action(field, draft: binding, account: account, draftID: draftID, allowed: { self.allowed })
        }
    }
    @MainActor private final class Storage: ProjectEditDataStorage {
        var values: [String: Data] = [:]
        var writes = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { writes += 1; values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    private func bytes(_ value: ActivityPublishDraft) -> Data? { ProjectEditPendingMaterials.exactData(value) }
    func testNameClearChangesOnlyNameAndKeepsUnsavedDraftBytes() {
        let h = Harness(); var expected = h.draft; expected.name = ""
        h.action(.name)(); XCTAssertEqual(bytes(h.draft), bytes(expected)); XCTAssertEqual(h.assignments, 1)
    }
    func testDescriptionClearChangesOnlyDescription() {
        let h = Harness(); var expected = h.draft; expected.description = ""
        h.action(.description)(); XCTAssertEqual(bytes(h.draft), bytes(expected)); XCTAssertEqual(h.assignments, 1)
    }
    func testTicketNameClearUsesStableUUIDAndPreservesOtherTicketAndPrice() {
        let h = Harness(), id = h.draft.tickets[1].id; var expected = h.draft; expected.tickets[1].name = ""
        h.action(.ticketName(id))(); XCTAssertEqual(bytes(h.draft), bytes(expected)); XCTAssertEqual(h.assignments, 1)
    }
    func testTicketStockClearWritesStringZeroAndPreservesEveryOtherField() {
        let h = Harness(), id = h.draft.tickets[0].id; var expected = h.draft; expected.tickets[0].stock = "0"
        h.action(.ticketStock(id))(); XCTAssertEqual(bytes(h.draft), bytes(expected)); XCTAssertEqual(h.assignments, 1)
    }
    func testAllFourClearedRequiredFieldsRemainRejectedByExistingWire() throws {
        for selection in 0..<4 {
            let h = Harness(); _ = try h.draft.wire()
            let fields: [ActivityPublishingLocalClearOwner.Field] = [.name, .description, .ticketName(h.draft.tickets[0].id), .ticketStock(h.draft.tickets[0].id)]
            h.action(fields[selection])()
            XCTAssertThrowsError(try h.draft.wire()) { XCTAssertEqual($0 as? PublishModesError, .invalidDraft) }
        }
    }
    func testAlreadyEmptyNameDescriptionAndZeroStockDoNotAssign() {
        let h = Harness(); h.draft.name = ""; h.draft.description = ""; h.draft.tickets[0].stock = "0"; h.bind()
        h.action(.name)(); h.action(.description)(); h.action(.ticketStock(h.draft.tickets[0].id))()
        XCTAssertEqual(h.assignments, 0)
    }
    func testEmptyAndPartialStockCanExplicitlyClearToInvalidZero() {
        for raw in ["", "-", "7.", " 7 "] {
            let h = Harness(); h.draft.tickets[0].stock = raw; h.bind()
            h.action(.ticketStock(h.draft.tickets[0].id))(); XCTAssertEqual(h.draft.tickets[0].stock, "0")
            XCTAssertThrowsError(try h.draft.wire())
        }
    }
    func testMissingOrDuplicateTicketUUIDCannotChooseAnArbitraryRow() {
        let h = Harness(); h.action(.ticketName(UUID()))(); XCTAssertEqual(h.assignments, 0)
        let id = h.draft.tickets[0].id; h.draft.tickets[1].id = id; h.bind(); let before = bytes(h.draft)
        h.action(.ticketName(id))(); h.action(.ticketStock(id))()
        XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testRemovedTicketCallbackCannotClearNextRowAtSameIndex() {
        let h = Harness(); let old = h.action(.ticketName(h.draft.tickets[0].id))
        h.draft.tickets.removeFirst(); h.bind(); let before = bytes(h.draft); old()
        XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
        h.action(.ticketName(h.draft.tickets[0].id))(); XCTAssertEqual(h.draft.tickets[0].name, "")
    }
    func testCapturedActionConsumesOnlyOnce() {
        let h = Harness(), old = h.action(.name); old(); old()
        XCTAssertEqual(h.assignments, 1); XCTAssertEqual(h.draft.name, "")
    }
    func testOneClearRetiresOtherCapturedFieldActionButFreshActionWorks() {
        let h = Harness(), oldDescription = h.action(.description); let description = h.draft.description
        h.action(.name)(); oldDescription(); XCTAssertEqual(h.draft.description, description)
        h.action(.description)(); XCTAssertEqual(h.draft.description, ""); XCTAssertEqual(h.assignments, 2)
    }
    func testUnsavedInputChangeRejectsOldCallbackEvenBeforeBind() {
        let h = Harness(), old = h.action(.name)
        h.draft.description = "New unsaved edit"; let before = bytes(h.draft); old()
        XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
        h.bind(); h.action(.name)(); XCTAssertEqual(h.draft.description, "New unsaved edit"); XCTAssertEqual(h.draft.name, "")
    }
    func testExactUnicodeSourceChangeRejectsCanonicallyEqualOldCallback() {
        let h = Harness(); h.draft.name = "e\u{301}"; h.bind(); let old = h.action(.name)
        h.draft.name = "\u{e9}"; XCTAssertEqual(h.draft.name, "e\u{301}")
        old(); XCTAssertEqual(Array(h.draft.name.utf8), Array("\u{e9}".utf8)); XCTAssertEqual(h.assignments, 0)
    }
    func testDraftMutationABACannotReviveCapturedAction() {
        let h = Harness(), original = h.draft, old = h.action(.name)
        h.draft.description = "Temporary"; h.bind(); h.draft = original; h.bind(); old()
        XCTAssertEqual(bytes(h.draft), bytes(original)); XCTAssertEqual(h.assignments, 0)
    }
    func testNewDraftIdentityRejectsOldActionAndAllowsNewAction() {
        let h = Harness(), old = h.action(.name); h.draftID = UUID(); h.bind(); let before = bytes(h.draft)
        old(); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
        h.action(.name)(); XCTAssertEqual(h.draft.name, "")
    }
    func testSwitchAccountEpochAndNamespaceRejectsOldAction() {
        for change in 0..<3 {
            let h = Harness(), old = h.action(.name), account = h.account!
            h.account = .init(namespace: change == 2 ? "other" : account.namespace, accountID: change == 0 ? 72 : account.accountID,
                              epoch: change == 1 ? UUID() : account.epoch, role: account.role, region: account.region)
            h.bind(); let before = bytes(h.draft); old(); XCTAssertEqual(bytes(h.draft), before)
            h.action(.name)(); XCTAssertEqual(h.draft.name, "")
        }
    }
    func testSignOutAndBackToOriginalAccountDoesNotReviveOldAction() {
        let h = Harness(), old = h.action(.name), account = h.account, before = bytes(h.draft)
        h.account = nil; h.bind(); h.account = account; h.bind(); old()
        XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testHiddenAndReopenedOwnerRejectsOldActionAndAcceptsFreshAction() {
        let h = Harness(), old = h.action(.description), before = bytes(h.draft)
        h.owner.retire(); old(); XCTAssertEqual(bytes(h.draft), before)
        h.owner.appear(active: true); old(); XCTAssertEqual(bytes(h.draft), before)
        h.action(.description)(); XCTAssertEqual(h.draft.description, ""); XCTAssertEqual(h.assignments, 1)
    }
    func testForegroundWhileHiddenCannotRestoreAnAction() {
        let h = Harness(), before = bytes(h.draft)
        h.owner.retire(); h.owner.setActive(false); h.owner.setActive(true); h.bind()
        h.action(.name)(); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testInactiveAppearAndCurrentBackgroundCallbacksStayClosed() {
        let h = Harness(), old = h.action(.name), before = bytes(h.draft)
        h.owner.setActive(false); old(); h.owner.retire(); h.owner.appear(active: false); h.action(.name)()
        XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
        h.owner.setActive(true); h.action(.name)(); XCTAssertEqual(h.draft.name, "")
    }
    func testDuplicateActiveAppearDoesNotRetireCurrentAction() {
        let h = Harness(), current = h.action(.name)
        h.owner.appear(active: true); h.owner.appear(active: true); current()
        XCTAssertEqual(h.draft.name, ""); XCTAssertEqual(h.assignments, 1)
    }
    func testVisibleReviewPickerBusyOrOutcomeLockGateRejectsCapturedAction() {
        let h = Harness(), old = h.action(.name), before = bytes(h.draft)
        h.allowed = false; h.bind(); old(); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
        h.allowed = true; h.bind(); old(); XCTAssertEqual(bytes(h.draft), before)
        h.action(.name)(); XCTAssertEqual(h.draft.name, "")
    }
    func testRestoreOfSameBytesStillRetiresOldAction() {
        let h = Harness(), old = h.action(.name), before = bytes(h.draft)
        h.owner.invalidate(); h.bind(); old(); XCTAssertEqual(bytes(h.draft), before)
        h.action(.name)(); XCTAssertEqual(h.draft.name, "")
    }
    func testClearDoesNotPersistUntilExistingExplicitSaveAndRestoreRemainsAvailable() throws {
        let h = Harness(), storage = Storage(), original = h.draft
        let account = try XCTUnwrap(h.account), store = PublishingDraftStore(storage: storage)
        try store.saveActive(PublishingLocalDraft(session: account, identity: h.draftID, activity: original), session: account)
        let writes = storage.writes; h.action(.name)()
        XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(try store.loadActive(activity: true, session: account)?.activity, original)
        try store.saveActive(PublishingLocalDraft(session: account, identity: h.draftID, activity: h.draft), session: account)
        XCTAssertEqual(try store.loadActive(activity: true, session: account)?.activity?.name, "")
        XCTAssertThrowsError(try h.draft.wire())
    }
    func testNilServiceLocalDraftCanClearWithoutNetworkOrGrant() {
        let h = Harness(); h.account = nil; h.bind(); h.action(.name)()
        XCTAssertEqual(h.draft.name, ""); XCTAssertEqual(h.assignments, 1)
    }
    func testActivityFormConstructsInBothLocalesWithoutSendingOrSaving() {
        for language in ["en", "zh-Hans"] {
            let host = UIHostingController(rootView: ActivityPublishingView(service: nil, account: nil, placeSearch: nil)
                .environment(\.locale, Locale(identifier: language)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded()
        }
    }
}

/// Result routing regressions share the existing app-unit source and registration.
@MainActor final class ActivityPublishingSubmissionOwnerTests: XCTestCase {
    private func account(_ role: String = "club", epoch: UUID = UUID()) -> PublishingSession {
        .init(namespace: "activity-result-fixture", accountID: 71, epoch: epoch, role: role, region: .china)
    }
    private func owner(account: PublishingSession? = nil, draftID: UUID = UUID(), draft: ActivityPublishDraft = .init(), service: PublishingService? = nil) -> ActivityPublishingSubmissionOwner {
        let value = ActivityPublishingSubmissionOwner()
        value.bind(account: account, draftID: draftID, draft: draft, service: service)
        value.appeared(); return value
    }
    func testAcknowledgmentLocksCreationAndOffersOnlyAccountReadback() throws {
        let value = owner(account: account()), operation = try XCTUnwrap(value.begin(allowCovered: false, submitting: true))
        XCTAssertTrue(value.receive(.acknowledged, operation: operation)); XCTAssertEqual(value.outcome, .acknowledged)
        XCTAssertTrue(value.canReadProjects); XCTAssertNil(value.begin(allowCovered: false))
        XCTAssertFalse(value.receive(.notSent, operation: operation))
    }
    func testUnknownLocksCreationAndRemainsUnknownAfterReadbackReturn() throws {
        let value = owner(account: account()), operation = try XCTUnwrap(value.begin(allowCovered: false, submitting: true))
        XCTAssertTrue(value.receive(.unknown, operation: operation))
        value.disappeared(departing: true, coveredByPresentation: false)
        XCTAssertFalse(value.canReadProjects); value.appeared()
        XCTAssertEqual(value.outcome, .unknown); XCTAssertTrue(value.canReadProjects)
        XCTAssertNil(value.begin(allowCovered: false))
    }
    func testRejectedAndNotSentRemainDistinctAndAllowExplicitNewReview() throws {
        for outcome in [PublishingWriteOutcome.rejected("Exact server reason"), .notSent] {
            let value = owner(account: account()), operation = try XCTUnwrap(value.begin(allowCovered: false, submitting: true))
            XCTAssertTrue(value.receive(outcome, operation: operation)); XCTAssertEqual(value.outcome, outcome)
            XCTAssertNotNil(value.begin(allowCovered: false))
        }
    }
    func testBusyRejectsRepeatedTapAndOldCompletionCannotFinishNewOperation() throws {
        let value = owner(), old = try XCTUnwrap(value.begin(allowCovered: false))
        XCTAssertNil(value.begin(allowCovered: false)); value.finish(old)
        let current = try XCTUnwrap(value.begin(allowCovered: false))
        value.finish(old); XCTAssertTrue(value.busy); XCTAssertFalse(value.receive(.acknowledged, operation: old))
        XCTAssertTrue(value.isCurrent(current))
    }
    func testAccountRoleAndEpochChangesRejectOldCompletion() throws {
        let original = account(), id = UUID()
        for replacement in [account("merchant", epoch: original.epoch), account(), nil] as [PublishingSession?] {
            let value = owner(account: original, draftID: id), old = try XCTUnwrap(value.begin(allowCovered: false))
            value.bind(account: replacement, draftID: id, draft: .init(), service: nil)
            XCTAssertFalse(value.receive(.acknowledged, operation: old)); XCTAssertNil(value.outcome)
        }
    }
    func testDraftChangeAndSameBytesNewDraftIdentityRetirePreparation() throws {
        let session = account(), id = UUID(), value = owner(account: session, draftID: id)
        let old = try XCTUnwrap(value.begin(allowCovered: false))
        var edited = ActivityPublishDraft(); edited.name = "Changed"
        value.bind(account: session, draftID: id, draft: edited, service: nil)
        XCTAssertFalse(value.isCurrent(old))
        let newer = try XCTUnwrap(value.begin(allowCovered: false))
        value.bind(account: session, draftID: UUID(), draft: edited, service: nil)
        XCTAssertFalse(value.isCurrent(newer))
    }
    func testLeaveReopenAndInactiveRejectSuspendedPreparation() throws {
        let value = owner(), old = try XCTUnwrap(value.begin(allowCovered: false))
        value.disappeared(departing: true, coveredByPresentation: false); value.appeared()
        XCTAssertFalse(value.receive(.acknowledged, operation: old))
        let current = try XCTUnwrap(value.begin(allowCovered: false))
        value.setActive(false); value.setActive(true)
        XCTAssertFalse(value.receive(.acknowledged, operation: current)); XCTAssertFalse(value.busy)
    }
    func testReviewCoveragePreservesOccurrenceButCannotStartAnotherPreparation() throws {
        let value = owner(), preparation = try XCTUnwrap(value.begin(allowCovered: false))
        value.finish(preparation); value.disappeared(departing: false, coveredByPresentation: true)
        XCTAssertNil(value.begin(allowCovered: false))
        let submission = try XCTUnwrap(value.begin(allowCovered: true, submitting: true))
        value.appeared(); XCTAssertTrue(value.receive(.acknowledged, operation: submission))
    }
    func testInterruptedSubmissionStaysUnknownAndRejectsLateAcknowledgment() throws {
        let session = account(), id = UUID(), value = owner(account: session, draftID: id)
        let sent = try XCTUnwrap(value.begin(allowCovered: true, submitting: true))
        value.setActive(false); value.setActive(true)
        XCTAssertEqual(value.outcome, .unknown); XCTAssertFalse(value.receive(.acknowledged, operation: sent))
        XCTAssertNil(value.begin(allowCovered: false))
        var changed = ActivityPublishDraft(); changed.name = "Changed"
        value.bind(account: session, draftID: id, draft: changed, service: nil)
        XCTAssertEqual(value.outcome, .unknown); XCTAssertNil(value.begin(allowCovered: false))
    }
    private final class Wire: HTTPTransport {
        var sends = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) { sends += 1; throw URLError(.unsupportedURL) }
    }
    private final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        var failRead = false
        var writes = 0
        var clears = 0
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            if failRead { throw PublishModesError.storage }
            guard record?.ownerKey == ownerKey, record?.targetKey == targetKey else { return nil }; return record
        }
        func write(_ value: OperationPendingRecord) throws { writes += 1; record = value }
        func clear(_ value: OperationPendingRecord) throws { clears += 1; record = nil }
    }
    private func service(_ session: PublishingSession, wire: Wire, journal: Journal) throws -> PublishingService {
        let credential = try PublishingCredentials(session: session, token: "synthetic-result-token")
        return try PublishingService(configuration: APIConfiguration(baseURL: URL(string: "https://example.test")!),
                                     transport: wire, journal: journal, credentials: { credential })
    }
    func testRecreatedOwnerReadsExistingUnknownLockWithoutAnySendClearOrWrite() throws {
        let session = account(), wire = Wire(), journal = Journal()
        let record = OperationPendingRecord(operationID: UUID(), ownerKey: session.storageKey, targetKey: "publishModes:activity:create")
        journal.record = record
        let api = try service(session, wire: wire, journal: journal)
        for _ in 0..<2 {
            let value = owner(account: session, service: api)
            XCTAssertEqual(value.outcome, .unknown); XCTAssertTrue(value.canReadProjects)
            XCTAssertNil(value.begin(allowCovered: true, submitting: true))
        }
        XCTAssertEqual(journal.record, record); XCTAssertEqual(journal.writes, 0); XCTAssertEqual(journal.clears, 0)
        XCTAssertEqual(wire.sends, 0); XCTAssertFalse(api.mutationsConfigured)
    }
    func testUnreadablePersistentLockFailsClosedWithoutSending() throws {
        let session = account(), wire = Wire(), journal = Journal(); journal.failRead = true
        let value = owner(account: session, service: try service(session, wire: wire, journal: journal))
        XCTAssertTrue(value.lockUnavailable); XCTAssertNil(value.begin(allowCovered: false)); XCTAssertEqual(wire.sends, 0)
    }
    func testServiceReplacementRejectsOldPreparationEvenWithSameAccountAndDraft() throws {
        let session = account(), id = UUID(), wire = Wire(), journal = Journal()
        let first = try service(session, wire: wire, journal: journal), second = try service(session, wire: wire, journal: journal)
        let value = owner(account: session, draftID: id, service: first), old = try XCTUnwrap(value.begin(allowCovered: false))
        value.bind(account: session, draftID: id, draft: .init(), service: second)
        XCTAssertFalse(value.receive(.acknowledged, operation: old)); XCTAssertEqual(wire.sends, 0)
    }
    func testNoAccountCannotOpenOwnedReadback() throws {
        let value = owner(), operation = try XCTUnwrap(value.begin(allowCovered: false))
        XCTAssertTrue(value.receive(.notSent, operation: operation)); XCTAssertFalse(value.canReadProjects)
    }
    func testReadOnlyDestinationAndExistingManagementDefaultRemainSeparate() throws {
        var opened: [PublishedResource] = []
        let management = PublishingProjectsView(service: nil, account: nil, openResource: { opened.append($0) })
        let readback = PublishingProjectsView(service: nil, account: nil, openResource: { opened.append($0) }, readOnly: true)
        let resource = try PublishedResource(kind: .activity, value: 41)
        readback.openProject(resource); XCTAssertTrue(opened.isEmpty)
        management.openProject(resource); XCTAssertEqual(opened, [resource])
        XCTAssertFalse(management.readOnly); XCTAssertTrue(readback.readOnly)
        let host = UIHostingController(rootView: readback); host.loadViewIfNeeded()
    }
    func testPreparationFailuresDoNotMislabelNetworkOrPermissionAsDraftValidation() {
        XCTAssertEqual(ActivityPublishingSubmissionOwner.preparationMessage(PublishModesError.invalidDraft), "publishModes.invalid")
        XCTAssertEqual(ActivityPublishingSubmissionOwner.preparationMessage(URLError(.networkConnectionLost)), "publishModes.readFailed")
        XCTAssertEqual(ActivityPublishingSubmissionOwner.preparationMessage(PublishModesError.invalidContract), "publishModes.readFailed")
        XCTAssertEqual(ActivityPublishingSubmissionOwner.preparationMessage(PublishModesError.forbidden), "publishModes.clubOnly")
        XCTAssertEqual(ActivityPublishingSubmissionOwner.preparationMessage(PublishModesError.storage), "publishModes.storageFailed")
        XCTAssertEqual(ActivityPublishingSubmissionOwner.preparationMessage(PublishModesError.rejected("denied")), "publishModes.rejected")
        XCTAssertNil(ActivityPublishingSubmissionOwner.preparationMessage(PublishModesError.changedSession))
        XCTAssertNil(ActivityPublishingSubmissionOwner.preparationMessage(CancellationError()))
    }

}
