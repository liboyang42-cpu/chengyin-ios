import XCTest
@testable import Questify

final class NativeChannelNotificationGlobalNavigationTests: XCTestCase {
    func testCurrentOriginalAccountDefaultAndOverrideCanOpen() throws {
        for type in [1, 2, 4] {
            let scope = try NativeChannelNotificationScope(type: type, value: "11")
            var navigation = NativeChannelNotificationGlobalNavigation()
            navigation.open(scope, currentScopes: [scope], canOpen: true)
            XCTAssertEqual(navigation.selection?.scope, scope)
        }
    }
    func testMissingOriginalScopeCannotBeSynthesizedFromTypedID() throws {
        let scope = try NativeChannelNotificationScope(type: 1, value: "9012")
        var navigation = NativeChannelNotificationGlobalNavigation()
        navigation.open(scope, currentScopes: [], canOpen: true)
        XCTAssertNil(navigation.selection)
    }
    func testClosedBusyBackgroundOrStaleScreenCannotSelect() throws {
        let scope = try NativeChannelNotificationScope(type: 1, value: "9012")
        var navigation = NativeChannelNotificationGlobalNavigation()
        navigation.open(scope, currentScopes: [scope], canOpen: false)
        XCTAssertNil(navigation.selection)
    }
    func testParentDirectoryPurgeDoesNotEraseExistingChildRoute() throws {
        let scope = try NativeChannelNotificationScope(type: 1, value: "9012")
        var navigation = NativeChannelNotificationGlobalNavigation()
        navigation.open(scope, currentScopes: [scope], canOpen: true)
        let original = try XCTUnwrap(navigation.selection)
        // Parent coordinator deactivation clears directory and current availability.
        // That presentation state is separate from the child's independently fenced flow.
        navigation.open(scope, currentScopes: [], canOpen: false)
        XCTAssertEqual(navigation.selection, original)
        navigation.close(original.id)
        XCTAssertNil(navigation.selection)
    }
    func testSecondTapCannotReplaceExistingChild() throws {
        let first = try NativeChannelNotificationScope(type: 1, value: "9012")
        let second = try NativeChannelNotificationScope(type: 2, value: "42")
        var navigation = NativeChannelNotificationGlobalNavigation()
        navigation.open(first, currentScopes: [first, second], canOpen: true)
        let original = navigation.selection
        navigation.open(second, currentScopes: [first, second], canOpen: true)
        XCTAssertEqual(navigation.selection, original)
    }
    func testLateDismissCannotCloseNewPresentationOfSameScope() throws {
        let scope = try NativeChannelNotificationScope(type: 4, value: "11")
        var navigation = NativeChannelNotificationGlobalNavigation()
        navigation.open(scope, currentScopes: [scope], canOpen: true)
        let first = try XCTUnwrap(navigation.selection)
        navigation.close(first.id)
        navigation.open(scope, currentScopes: [scope], canOpen: true)
        let second = try XCTUnwrap(navigation.selection)
        XCTAssertNotEqual(first.id, second.id)
        navigation.close(first.id)
        XCTAssertEqual(navigation.selection, second)
    }
    func testReturnRequiresFreshOriginalScopesToOpenAgain() throws {
        let scope = try NativeChannelNotificationScope(type: 1, value: "9012")
        var navigation = NativeChannelNotificationGlobalNavigation()
        navigation.open(scope, currentScopes: [scope], canOpen: true)
        navigation.close(navigation.selection?.id)
        navigation.open(scope, currentScopes: [], canOpen: true)
        XCTAssertNil(navigation.selection)
    }
}
