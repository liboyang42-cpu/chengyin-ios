import XCTest
import SwiftUI
@testable import Questify

/// Pure owner/binding semantics. SwiftUI navigation callbacks and Apple builds are
/// not exercised by these tests; the normal views pass the same visit snapshots.
@MainActor final class NativeChannelManagementVisitIsolationTests: XCTestCase {
    func testInactiveBindingCanOpenItsInitialVisit() {
        let owner = NativeChannelManagementRouteState()
        let beforeOpening = owner.binding
        XCTAssertFalse(beforeOpening.wrappedValue)
        beforeOpening.wrappedValue = true
        XCTAssertTrue(beforeOpening.wrappedValue)
        XCTAssertTrue(owner.isPresented)
    }
    func testRootCloseReopenDoesNotReviveOldBindingWithoutIntermediateRead() {
        let owner = NativeChannelManagementRouteState()
        owner.isPresented = true
        let old = owner.binding
        owner.isPresented = false
        owner.isPresented = true
        XCTAssertFalse(old.wrappedValue)
        XCTAssertTrue(owner.binding.wrappedValue)
    }
    func testSwiftUIReacquiringBindingDoesNotChangeOldVisit() {
        let owner = NativeChannelManagementRouteState()
        let old = owner.binding
        old.wrappedValue = true
        XCTAssertTrue(owner.binding.wrappedValue)
        old.wrappedValue = false
        let next = owner.binding
        next.wrappedValue = true
        XCTAssertTrue(next.wrappedValue)
        XCTAssertFalse(old.wrappedValue)
    }
    func testStaleRootSetterCannotCloseOrReopenNewVisit() {
        let owner = NativeChannelManagementRouteState()
        let old = owner.binding
        old.wrappedValue = true
        old.wrappedValue = false
        let next = owner.binding
        next.wrappedValue = true
        old.wrappedValue = false
        XCTAssertTrue(next.wrappedValue)
        next.wrappedValue = false
        old.wrappedValue = true
        XCTAssertFalse(owner.isPresented)
    }
    func testChildCannotReviveAfterUnobservedAncestorCloseReopen() {
        let root = NativeChannelManagementRouteState(), child = NativeChannelManagementRouteState()
        let ancestor = root.binding
        let visit = NativeChannelManagementRouteState.child(child.binding, parentCurrent: { ancestor.wrappedValue })
        root.isPresented = true
        visit.wrappedValue = true
        root.isPresented = false
        root.isPresented = true
        XCTAssertFalse(visit.wrappedValue)
        visit.wrappedValue = true
        XCTAssertFalse(child.isPresented)
        XCTAssertTrue(root.isPresented)
    }
    func testSelectionAToBToAHasDistinctVisitsWithoutIntermediateRead() {
        let selection = NativeChannelManagementSelectionState<Int>()
        selection.selected = 9
        let first = selection.route(for: 9, parentCurrent: { true })
        selection.selected = 10
        selection.selected = 9
        XCTAssertFalse(first.wrappedValue)
        XCTAssertTrue(selection.route(for: 9, parentCurrent: { true }).wrappedValue)
    }
    func testSelectionDismissAndSameItemReopenDoesNotRevive() {
        let selection = NativeChannelManagementSelectionState<Int>()
        selection.selected = 9
        let first = selection.route(for: 9, parentCurrent: { true })
        first.wrappedValue = false
        selection.selected = 9
        XCTAssertFalse(first.wrappedValue)
        XCTAssertTrue(selection.route(for: 9, parentCurrent: { true }).wrappedValue)
    }
    func testStaleSelectionDismissCannotPopNewVisitOfSameItem() {
        let selection = NativeChannelManagementSelectionState<Int>()
        selection.selected = 9
        let old = selection.route(for: 9, parentCurrent: { true })
        let oldPath = selection.binding
        selection.selected = 10
        selection.selected = 9
        old.wrappedValue = false
        oldPath.wrappedValue = nil
        XCTAssertEqual(selection.selected, 9)
    }
    func testAssigningSameSelectionDoesNotManufactureNewVisit() {
        let selection = NativeChannelManagementSelectionState<Int>()
        selection.selected = 9
        let current = selection.route(for: 9, parentCurrent: { true })
        selection.selected = 9
        XCTAssertTrue(current.wrappedValue)
    }
    func testRetainedSelectionRouteDoesNotKeepOwnerAlive() {
        var selection: NativeChannelManagementSelectionState<Int>? = .init()
        selection?.selected = 9
        let route = selection!.route(for: 9, parentCurrent: { true })
        let path = selection!.binding
        weak var weakOwner = selection
        selection = nil
        XCTAssertNil(weakOwner)
        XCTAssertFalse(route.wrappedValue)
        XCTAssertNil(path.wrappedValue)
    }
    func testCoveredWelcomeMessageTracksEveryAncestor() {
        let directory = NativeChannelManagementRouteState(), onboarding = NativeChannelManagementRouteState()
        let welcome = NativeChannelManagementRouteState()
        let selection = NativeChannelManagementSelectionState<Int>()
        let directoryVisit = directory.binding
        let onboardingVisit = NativeChannelManagementRouteState.child(onboarding.binding, parentCurrent: { directoryVisit.wrappedValue })
        let welcomeVisit = NativeChannelManagementRouteState.child(welcome.binding, parentCurrent: { onboardingVisit.wrappedValue })
        directoryVisit.wrappedValue = true; onboardingVisit.wrappedValue = true; welcomeVisit.wrappedValue = true
        selection.selected = 9
        let messageVisit = selection.route(for: 9, parentCurrent: { welcomeVisit.wrappedValue })
        XCTAssertTrue(messageVisit.wrappedValue) // Covering push does not close a live ancestor.
        onboarding.isPresented = false
        onboarding.isPresented = true
        XCTAssertFalse(messageVisit.wrappedValue)
        XCTAssertTrue(directory.isPresented)
    }
    func testDirectWelcomeRouteRejectsRemovedDirectoryOwner() {
        var directory: NativeChannelManagementRouteState? = .init()
        let welcome = NativeChannelManagementRouteState()
        let directoryVisit = directory!.binding
        let welcomeVisit = NativeChannelManagementRouteState.child(welcome.binding, parentCurrent: { directoryVisit.wrappedValue })
        directoryVisit.wrappedValue = true; welcomeVisit.wrappedValue = true
        directory = nil
        XCTAssertFalse(welcomeVisit.wrappedValue)
    }
}
