import XCTest
import SwiftUI
@testable import Questify

/// Binding semantics only; these do not simulate NavigationStack or Apple callbacks.
@MainActor final class NativeChannelManagementRouteStateTests: XCTestCase {
    func testRootReflectsActualLinkState() {
        let root = NativeChannelManagementRouteState(), binding = root.binding
        XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = true
        XCTAssertTrue(root.isPresented)
        root.isPresented = false
        XCTAssertFalse(binding.wrappedValue)
    }
    func testRetainedDescendantDoesNotKeepRemovedRootAlive() {
        var root: NativeChannelManagementRouteState? = .init()
        root?.isPresented = true
        let binding = root!.binding
        weak var weakRoot = root
        XCTAssertTrue(binding.wrappedValue)
        root = nil
        XCTAssertNil(weakRoot)
        XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = true
        XCTAssertFalse(binding.wrappedValue)
    }
    func testChildPushRetainsLiveAncestorButAncestorPopClosesIt() {
        let root = NativeChannelManagementRouteState(), messages = NativeChannelManagementRouteState()
        let parent = root.binding
        let child = NativeChannelManagementRouteState.child(messages.binding, parentCurrent: { parent.wrappedValue })
        root.isPresented = true
        child.wrappedValue = true
        XCTAssertTrue(child.wrappedValue)
        XCTAssertTrue(parent.wrappedValue)
        root.isPresented = false
        XCTAssertFalse(child.wrappedValue)
        child.wrappedValue = true
        XCTAssertFalse(messages.isPresented)
    }
    func testSelectedChannelAndCurrentOwnerArePartOfTheSamePath() {
        let root = NativeChannelManagementRouteState(), messages = NativeChannelManagementRouteState()
        let parent = root.binding
        var selected = 9
        var ownerCurrent = true
        let child = NativeChannelManagementRouteState.child(messages.binding, parentCurrent: {
            parent.wrappedValue && selected == 9 && ownerCurrent
        })
        root.isPresented = true; child.wrappedValue = true
        XCTAssertTrue(child.wrappedValue)
        selected = 10; XCTAssertFalse(child.wrappedValue)
        selected = 9; ownerCurrent = false; XCTAssertFalse(child.wrappedValue)
        child.wrappedValue = true; XCTAssertFalse(messages.isPresented)
    }
    func testClosingChildDoesNotPopItsParent() {
        let root = NativeChannelManagementRouteState(), messages = NativeChannelManagementRouteState()
        root.isPresented = true; messages.isPresented = true
        let parent = root.binding
        let child = NativeChannelManagementRouteState.child(messages.binding, parentCurrent: { parent.wrappedValue })
        child.wrappedValue = false
        XCTAssertFalse(messages.isPresented)
        XCTAssertTrue(root.isPresented)
    }
}
