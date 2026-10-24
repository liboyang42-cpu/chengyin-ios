import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ActivityPublishingTimeRangeTests: XCTestCase {
    @MainActor private final class Harness {
        let owner = ActivityPublishingTimeRangeOwner()
        var account: PublishingSession? = .init(namespace: "activity-range-fixture", accountID: 71, epoch: UUID(), role: "club_owner", region: .china)
        var draftID = UUID()
        var draft = ActivityPublishDraft()
        var allowed = true
        var zone = "Asia/Shanghai"
        var assignments = 0
        let now = Date(timeIntervalSince1970: 1_893_484_800)
        init() {
            draft.name = "Unsaved name"; draft.description = "Exact e\u{301} draft"
            draft.coverURL = "fixture://cover?raw=1"; draft.addressName = "Original address"
            draft.place = try? PublishingPlace(id: "place", name: "Place", address: "Address", latitude: 31, longitude: 121)
            draft.start = "2030-01-01 09:00:00"; draft.end = "2030-01-01 18:00:00"
            draft.playTemplateID = AuthoringPlayTemplateID(rawValue: 41)
            draft.categoryIDs = [3, 8]; draft.collaboratorMemberIDs = [71, 72]
            var ticket = ActivityPublishTicket(); ticket.name = "Ticket"; ticket.price = "0"; ticket.stock = "007"
            ticket.start = draft.start; ticket.end = draft.end; draft.tickets = [ticket]
            bind(); owner.appear(active: true)
        }
        func bind() { owner.bind(account: account, draftID: draftID, draft: draft, editable: allowed) }
        var binding: Binding<ActivityPublishDraft> {
            .init(get: { self.draft }, set: { self.assignments += 1; self.draft = $0; self.bind() })
        }
        func open() -> ActivityPublishingTimeRangeOwner.Presentation? {
            owner.open(account: account, draftID: draftID, draft: draft, now: now, timeZoneID: zone)
            return owner.presentation
        }
        func mounted() throws -> ActivityPublishingTimeRangeOwner.Presentation {
            let value = try XCTUnwrap(open()); owner.sheetAppeared(value, timeZoneID: zone); return value
        }
        func apply(_ value: ActivityPublishingTimeRangeDraft, _ original: ActivityPublishingTimeRangeOwner.Presentation) -> Bool {
            owner.apply(value, original: original, draft: binding, account: account, draftID: draftID, timeZoneID: zone, allowed: allowed)
        }
        func canOpen() -> Bool { owner.canOpen(account: account, draftID: draftID, draft: draft, now: now) }
    }
    @MainActor private final class Storage: ProjectEditDataStorage {
        var values: [String: Data] = [:]
        var writes = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { writes += 1; values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    private func bytes(_ value: ActivityPublishDraft) -> Data? { ProjectEditPendingMaterials.exactData(value) }
    private func date(_ value: String) throws -> Date { try XCTUnwrap(ProjectEditDateSelection.date(value, ending: false)) }

    func testOpenAndCancelLeaveEveryUnsavedByteUnchanged() throws {
        let h = Harness(), before = bytes(h.draft); let p = try h.mounted()
        var local = p.draft; local.start += 3600; local.end += 7200
        XCTAssertNotEqual(local.start, p.draft.start); XCTAssertEqual(bytes(h.draft), before)
        h.owner.close(p); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testExplicitApplyChangesOnlyBothActivityEndpointsInOneAssignment() throws {
        let h = Harness(); let p = try h.mounted(); var local = p.draft
        local.start -= 3600; local.end += 3600
        var expected = h.draft; expected.start = "2030-01-01 08:00:00"; expected.end = "2030-01-01 19:00:00"
        XCTAssertTrue(h.apply(local, p)); XCTAssertEqual(bytes(h.draft), bytes(expected)); XCTAssertEqual(h.assignments, 1)
        XCTAssertNil(h.owner.presentation); XCTAssertNoThrow(try h.draft.wire())
    }
    func testUnchangedDateOnlySpellingIsRetainedAndNoAssignmentOccurs() throws {
        let h = Harness(); h.draft.start = "2030-01-01"; h.draft.end = "2030-01-02"; h.bind()
        let before = bytes(h.draft), p = try h.mounted()
        XCTAssertEqual(p.draft.end, try date("2030-01-02 00:00:00"))
        XCTAssertTrue(h.apply(p.draft, p)); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testEditingOneEndpointPreservesExactOtherRawSpelling() throws {
        let h = Harness(); h.draft.start = "2030-01-01"; h.bind(); let p = try h.mounted(); var local = p.draft
        local.end += 3600; XCTAssertTrue(h.apply(local, p)); XCTAssertEqual(h.draft.start, "2030-01-01")
        XCTAssertEqual(h.draft.end, "2030-01-01 19:00:00")
    }
    func testEmptyDatesReceiveOnlyLocalDefaultsUntilExplicitApply() throws {
        let h = Harness(); h.draft.start = ""; h.draft.end = ""; h.bind(); let before = bytes(h.draft), p = try h.mounted()
        XCTAssertEqual(p.draft.end.timeIntervalSince(p.draft.start), 3600); XCTAssertEqual(bytes(h.draft), before)
        XCTAssertTrue(h.apply(p.draft, p)); XCTAssertFalse(h.draft.start.isEmpty); XCTAssertFalse(h.draft.end.isEmpty)
        XCTAssertEqual(h.assignments, 1)
    }
    func testUnsupportedExistingValuesAreNeverSilentlyReplaced() {
        for raw in ["tomorrow", "2030-02-30", "2030-01-01T09:00:00Z", "2030-01-01 25:00:00", "2030-01"] {
            let h = Harness(); h.draft.start = raw; h.bind(); let before = bytes(h.draft)
            XCTAssertFalse(h.canOpen(), raw); XCTAssertNil(h.open(), raw); XCTAssertEqual(bytes(h.draft), before)
        }
    }
    func testUnsupportedEndRejectsOpenWithoutChangingValidStart() {
        let h = Harness(); h.draft.end = "unknown"; h.bind(); let before = bytes(h.draft)
        XCTAssertNil(h.open()); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testEqualAndReversedSelectionsRejectWithoutClosingCurrentEditor() throws {
        let h = Harness(); let p = try h.mounted(); var local = p.draft; let before = bytes(h.draft)
        local.end = local.start; XCTAssertFalse(h.apply(local, p))
        local.end = local.start.addingTimeInterval(-1); XCTAssertFalse(h.apply(local, p))
        XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.owner.presentation?.id, p.id)
    }
    func testSubsecondIntervalWhichSerializesEqualCannotBecomeValid() throws {
        let h = Harness(); let p = try h.mounted(); var local = p.draft
        local.end = local.start.addingTimeInterval(0.1); XCTAssertFalse(h.apply(local, p)); XCTAssertEqual(h.assignments, 0)
    }
    func testInvalidDateInstantFailsWithoutChangingSource() throws {
        let h = Harness(); let p = try h.mounted(); var local = p.draft
        local.end = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(h.apply(local, p)); XCTAssertEqual(h.assignments, 0)
    }
    func testTicketRangeIsNotAutomaticallyChangedOrMadeValid() throws {
        let h = Harness(); let p = try h.mounted(); var local = p.draft; let tickets = h.draft.tickets
        local.start += 3600; XCTAssertTrue(h.apply(local, p)); XCTAssertEqual(h.draft.tickets, tickets)
        XCTAssertThrowsError(try h.draft.wire()) { XCTAssertEqual($0 as? PublishModesError, .invalidDraft) }
    }
    func testCurrentBindingReadsCapturedIDAndNilDismissesOnlyIt() throws {
        let h = Harness(); let p = try h.mounted(); let b = h.owner.binding(p, timeZoneID: { h.zone })
        XCTAssertEqual(b.wrappedValue?.id, p.id); b.wrappedValue = nil
        XCTAssertNil(h.owner.presentation); XCTAssertNil(b.wrappedValue); XCTAssertEqual(h.assignments, 0)
    }
    func testOldBindingCannotReadOrDismissNewPresentation() throws {
        let h = Harness(); let a = try h.mounted(); let old = h.owner.binding(a, timeZoneID: { h.zone }); h.owner.close(a)
        let b = try h.mounted(); XCTAssertNotEqual(a.id, b.id); XCTAssertNil(old.wrappedValue)
        old.wrappedValue = nil; XCTAssertEqual(h.owner.presentation?.id, b.id)
        XCTAssertEqual(h.owner.binding(b, timeZoneID: { h.zone }).wrappedValue?.id, b.id)
    }
    func testOldChildDisappearAndApplyCannotConsumeNewOwner() throws {
        let h = Harness(); let a = try h.mounted(); h.owner.close(a); let b = try h.mounted()
        h.owner.close(a); h.owner.sheetAppeared(a, timeZoneID: h.zone)
        XCTAssertFalse(h.apply(a.draft, a)); XCTAssertEqual(h.owner.presentation?.id, b.id)
        XCTAssertTrue(h.apply(b.draft, b))
    }
    func testApplyIsOneUseAndReopenStartsFromNewFormalDates() throws {
        let h = Harness(); let a = try h.mounted(); var local = a.draft; local.end += 3600
        XCTAssertTrue(h.apply(local, a)); XCTAssertFalse(h.apply(local, a)); XCTAssertEqual(h.assignments, 1)
        let b = try h.mounted(); XCTAssertEqual(b.draft.end, local.end); XCTAssertNotEqual(a.id, b.id)
    }
    func testUnboundUnsavedInputChangeRejectsOldApply() throws {
        let h = Harness(); let p = try h.mounted(); h.draft.description = "New unsaved description"; let before = bytes(h.draft)
        XCTAssertFalse(h.apply(p.draft, p)); XCTAssertEqual(bytes(h.draft), before); XCTAssertEqual(h.assignments, 0)
    }
    func testBoundDraftABAInvalidatesOriginalPresentationAndGetter() throws {
        let h = Harness(); let p = try h.mounted(); let old = h.owner.binding(p, timeZoneID: { h.zone }); let original = h.draft
        h.draft.description = "Changed"; h.bind(); h.draft = original; h.bind()
        XCTAssertNil(old.wrappedValue); XCTAssertFalse(h.apply(p.draft, p))
    }
    func testCanonicallyEqualButByteDifferentInputCannotBeOverwritten() throws {
        let h = Harness(); h.draft.name = "e\u{301}"; h.bind(); let p = try h.mounted(); h.draft.name = "é"
        XCTAssertFalse(h.apply(p.draft, p)); XCTAssertEqual(h.assignments, 0)
    }
    func testDifferentAccountAndDraftIDRejectEvenBeforeBind() throws {
        let h = Harness(); let p = try h.mounted(); let original = h.account
        h.account = nil; XCTAssertFalse(h.apply(p.draft, p)); h.account = original
        h.draftID = UUID(); XCTAssertFalse(h.apply(p.draft, p)); XCTAssertEqual(h.assignments, 0)
    }
    func testAccountABAAcrossBindCannotReviveOldEditor() throws {
        let h = Harness(); let p = try h.mounted(); let original = h.account
        h.account = nil; h.bind(); h.account = original; h.bind()
        XCTAssertFalse(h.owner.current(p, timeZoneID: h.zone)); XCTAssertFalse(h.apply(p.draft, p))
    }
    func testReadOnlyAndPendingParentReviewCannotOpenOrApply() throws {
        let h = Harness(); let p = try h.mounted(); h.allowed = false
        XCTAssertFalse(h.apply(p.draft, p)); h.bind(); XCTAssertFalse(h.owner.current(p, timeZoneID: h.zone))
        h.owner.retire(); XCTAssertNil(h.open()); XCTAssertEqual(h.assignments, 0)
    }
    func testNeverMountedSheetCannotApplyAndHiddenPendingOpenCannotMountLate() throws {
        let h = Harness(); let p = try XCTUnwrap(h.open())
        XCTAssertFalse(h.apply(p.draft, p)); h.owner.disappear(); h.owner.sheetAppeared(p, timeZoneID: h.zone)
        XCTAssertFalse(h.owner.current(p, timeZoneID: h.zone)); XCTAssertFalse(h.apply(p.draft, p)); XCTAssertFalse(h.canOpen())
    }
    func testMountedSheetMayCoverParentWithoutLosingItsOwnDraft() throws {
        let h = Harness(); let p = try h.mounted()
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true)
        XCTAssertTrue(h.owner.current(p, timeZoneID: h.zone)); XCTAssertFalse(h.canOpen())
        XCTAssertTrue(h.apply(p.draft, p)); XCTAssertFalse(h.canOpen())
    }
    func testSheetDisappearRetiresHiddenOwnerAndForegroundCannotReopenIt() throws {
        let h = Harness(); let p = try h.mounted(); h.owner.disappear(); h.owner.close(p)
        h.owner.setActive(false); h.owner.setActive(true)
        XCTAssertNil(h.open()); XCTAssertFalse(h.apply(p.draft, p))
        h.owner.appear(active: true); XCTAssertNotNil(h.open())
    }
    func testBackgroundRetiresEditorAndRepeatedAppearDoesNotBorrowOldOwner() throws {
        let h = Harness(); let p = try h.mounted(); h.owner.setActive(false); h.owner.setActive(true)
        XCTAssertFalse(h.apply(p.draft, p)); XCTAssertNil(h.owner.binding(p, timeZoneID: { h.zone }).wrappedValue)
        let fresh = try h.mounted(); h.owner.appear(active: true); h.owner.appear(active: true)
        XCTAssertTrue(h.owner.current(fresh, timeZoneID: h.zone)); XCTAssertTrue(h.apply(fresh.draft, fresh))
    }
    func testTimeZoneChangeRejectsOldBindingAndApplyWithoutReinterpretingDates() throws {
        let h = Harness(); let p = try h.mounted(); let old = h.owner.binding(p, timeZoneID: { h.zone }); let before = bytes(h.draft)
        h.zone = "America/Los_Angeles"; XCTAssertNil(old.wrappedValue); XCTAssertFalse(h.apply(p.draft, p))
        XCTAssertEqual(bytes(h.draft), before)
    }
    func testInvalidTimeZoneCannotOpenAndExplicitGuestLocalEditingRemainsAvailable() throws {
        let h = Harness(); h.zone = "Not/AZone"; XCTAssertNil(h.open())
        h.zone = "Asia/Shanghai"; h.account = nil; h.bind(); let p = try h.mounted()
        var local = p.draft; local.end += 3600; XCTAssertTrue(h.apply(local, p)); XCTAssertNil(h.account)
    }
    func testNonBeijingPickerUsesSameInstantsAndWritesBeijingWireValues() throws {
        let h = Harness(); h.zone = "America/Los_Angeles"; let p = try h.mounted()
        XCTAssertEqual(p.draft.start, try date("2030-01-01 09:00:00"))
        var local = p.draft; local.start -= 3600; XCTAssertTrue(h.apply(local, p))
        XCTAssertEqual(h.draft.start, "2030-01-01 08:00:00"); XCTAssertEqual(h.draft.end, "2030-01-01 18:00:00")
    }
    func testCancelThenReopenRestartsFromFormalPairRatherThanAbandonedInput() throws {
        let h = Harness(); let a = try h.mounted(); var abandoned = a.draft; abandoned.end += 7200
        h.owner.close(a); let b = try h.mounted()
        XCTAssertEqual(b.draft.end, a.draft.end); XCTAssertNotEqual(b.draft.end, abandoned.end)
        XCTAssertEqual(h.assignments, 0)
    }
    func testApplyDoesNotPersistUntilExistingExplicitSaveAndRestoreIsExact() throws {
        let h = Harness(), storage = Storage(), original = h.draft
        let account = try XCTUnwrap(h.account), store = PublishingDraftStore(storage: storage)
        try store.saveActive(PublishingLocalDraft(session: account, identity: h.draftID, activity: original), session: account)
        let writes = storage.writes, p = try h.mounted(); var local = p.draft; local.end += 3600
        XCTAssertTrue(h.apply(local, p)); XCTAssertEqual(storage.writes, writes)
        XCTAssertEqual(try store.loadActive(activity: true, session: account)?.activity, original)
        try store.saveActive(PublishingLocalDraft(session: account, identity: h.draftID, activity: h.draft), session: account)
        XCTAssertEqual(try store.loadActive(activity: true, session: account)?.activity, h.draft)
    }

    func testCoverageBeforeChildAppearKeepsConcreteRouteButDoesNotPermitEarlyApply() throws {
        let h = Harness(); let p = try XCTUnwrap(h.open()), before = bytes(h.draft)
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true)
        XCTAssertTrue(h.owner.current(p, timeZoneID: h.zone)); XCTAssertFalse(h.apply(p.draft, p))
        XCTAssertEqual(bytes(h.draft), before); XCTAssertFalse(h.canOpen())
        h.owner.sheetAppeared(p, timeZoneID: h.zone)
        XCTAssertTrue(h.apply(p.draft, p)); XCTAssertEqual(h.assignments, 0)
    }
    func testRealDepartureWinsOverMountedModalCoverageAndLateChildCallbacks() throws {
        let h = Harness(); let p = try h.mounted(), old = h.owner.binding(p, timeZoneID: { h.zone })
        h.owner.parentDisappeared(departing: true, coveredByPresentation: true)
        h.owner.sheetAppeared(p, timeZoneID: h.zone); h.owner.setActive(false); h.owner.setActive(true)
        XCTAssertNil(old.wrappedValue); XCTAssertNil(h.owner.presentation); XCTAssertFalse(h.canOpen())
        XCTAssertFalse(h.apply(p.draft, p)); XCTAssertEqual(h.assignments, 0)
        h.owner.parentAppeared(); let fresh = try h.mounted()
        h.owner.close(p); old.wrappedValue = nil
        XCTAssertEqual(h.owner.presentation?.id, fresh.id); XCTAssertTrue(h.apply(fresh.draft, fresh))
    }
    func testDisappearanceWithoutUIKitCoverageRetiresEvenWhenSheetWasMounted() throws {
        let h = Harness(); let p = try h.mounted()
        h.owner.parentDisappeared(departing: false, coveredByPresentation: false)
        XCTAssertNil(h.owner.presentation); XCTAssertFalse(h.apply(p.draft, p))
        h.owner.setActive(true); XCTAssertFalse(h.canOpen()); XCTAssertEqual(h.assignments, 0)
    }
    func testCoveredParentReturnKeepsCurrentEditorButCannotReviveCancelledOne() throws {
        let h = Harness(); let p = try h.mounted()
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true)
        h.owner.parentAppeared(); XCTAssertTrue(h.owner.current(p, timeZoneID: h.zone))
        h.owner.close(p); h.owner.parentAppeared()
        XCTAssertNil(h.owner.binding(p, timeZoneID: { h.zone }).wrappedValue)
        XCTAssertFalse(h.apply(p.draft, p)); XCTAssertTrue(h.canOpen())
    }
    func testCoverageCannotBorrowChangedSourceOrBackgroundRetiredPresentation() throws {
        let h = Harness(); let p = try h.mounted(); h.draft.description = "new unsaved bytes"; h.bind()
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true)
        XCTAssertNil(h.owner.presentation); XCTAssertFalse(h.apply(p.draft, p))
        h.owner.parentAppeared(); let second = try h.mounted(); h.owner.setActive(false)
        h.owner.parentDisappeared(departing: false, coveredByPresentation: true); h.owner.setActive(true)
        h.owner.sheetAppeared(second, timeZoneID: h.zone)
        XCTAssertFalse(h.apply(second.draft, second)); XCTAssertFalse(h.canOpen()); XCTAssertEqual(h.assignments, 0)
    }

    @MainActor private struct RangeHost: View {
        @ObservedObject var owner: ActivityPublishingTimeRangeOwner
        let harness: Harness
        var body: some View {
            Form {
                Button("Open activity dates") { _ = harness.open() }
                Text("Unsaved activity")
            }
            .onAppear { owner.setActive(true) }
            .background { ActivityPublishingTimeRangeLifetimeAnchor(owner: owner).frame(width: 0, height: 0) }
            .background {
                if let original = owner.presentation {
                    ActivityPublishingTimeRangePresenter(owner: owner, original: original) { selected in
                        harness.apply(selected, original)
                    }.id(original.id)
                }
            }
        }
    }
    private enum HostWaitError: Error { case timedOut }
    private func waitForHost(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                             _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), description, file: file, line: line)
        if !condition() { throw HostWaitError.timedOut }
    }
    func testHostedInitiallyNilRouteReallyPresentsThenAppliesWithoutAutoSaving() async throws {
        let h = Harness(); h.zone = TimeZone.autoupdatingCurrent.identifier; h.owner.disappear(); h.owner.setActive(true)
        let original = bytes(h.draft), sceneWindow = try HostedNavigationSceneWindow()
        let host = UIHostingController(rootView: AnyView(RangeHost(owner: h.owner, harness: h)))
        sceneWindow.window.rootViewController = host; sceneWindow.window.makeKeyAndVisible()
        defer { sceneWindow.retire() }
        XCTAssertNil(h.owner.presentation)
        try await waitForHost("real stable parent appears before first open") { h.canOpen() }
        let p = try XCTUnwrap(h.open()); XCTAssertEqual(bytes(h.draft), original)
        try await waitForHost("concrete first route presents a real sheet") {
            host.presentedViewController?.viewIfLoaded?.window != nil && host.presentedViewController?.isBeingPresented == false
        }
        var local = p.draft; local.end += 3600
        XCTAssertTrue(h.apply(local, p)); XCTAssertEqual(h.assignments, 1)
        XCTAssertEqual(h.draft.end, "2030-01-01 19:00:00")
        try await waitForHost("apply dismisses its real sheet") { host.presentedViewController == nil }
        XCTAssertNil(h.owner.presentation); XCTAssertFalse(h.apply(local, p))
    }
    func testHostedParentRemovalRetiresAttachedSheetAndOldBindingCannotTouchReopen() async throws {
        let h = Harness(); h.zone = TimeZone.autoupdatingCurrent.identifier; h.owner.disappear(); h.owner.setActive(true)
        let original = bytes(h.draft), sceneWindow = try HostedNavigationSceneWindow()
        let host = UIHostingController(rootView: AnyView(RangeHost(owner: h.owner, harness: h)))
        sceneWindow.window.rootViewController = host; sceneWindow.window.makeKeyAndVisible()
        defer { sceneWindow.retire() }
        try await waitForHost("first real parent visible") { h.canOpen() }
        let p = try XCTUnwrap(h.open()), old = h.owner.binding(p, timeZoneID: { h.zone })
        try await waitForHost("first child attached") {
            host.presentedViewController?.viewIfLoaded?.window != nil && host.presentedViewController?.isBeingPresented == false
        }
        host.rootView = AnyView(Text("Departed activity"))
        try await waitForHost("actual parent removal retires owner and sheet") {
            h.owner.presentation == nil && host.presentedViewController == nil
        }
        XCTAssertFalse(h.canOpen()); XCTAssertNil(old.wrappedValue)
        h.owner.sheetAppeared(p, timeZoneID: h.zone); h.owner.setActive(false); h.owner.setActive(true)
        XCTAssertFalse(h.apply(p.draft, p)); XCTAssertEqual(bytes(h.draft), original)
        host.rootView = AnyView(RangeHost(owner: h.owner, harness: h))
        try await waitForHost("real returned parent permits fresh opening") { h.canOpen() }
        let fresh = try XCTUnwrap(h.open()); XCTAssertNotEqual(fresh.id, p.id)
        try await waitForHost("fresh child attached") {
            host.presentedViewController?.viewIfLoaded?.window != nil && host.presentedViewController?.isBeingPresented == false
        }
        old.wrappedValue = nil; h.owner.close(p); h.owner.sheetAppeared(p, timeZoneID: h.zone)
        XCTAssertEqual(h.owner.presentation?.id, fresh.id); XCTAssertFalse(h.apply(p.draft, p))
        XCTAssertTrue(h.apply(fresh.draft, fresh)); XCTAssertEqual(bytes(h.draft), original); XCTAssertEqual(h.assignments, 0)
    }
}
