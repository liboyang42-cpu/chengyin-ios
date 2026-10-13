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
