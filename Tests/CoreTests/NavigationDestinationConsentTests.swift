import XCTest
@testable import QuestifyCore

final class NavigationDestinationConsentTests: XCTestCase {
    private func destination() throws -> InAppNavigationDestination {
        InAppNavigationDestination(reference: try WalkingTargetReference(kind: .cityNode, id: 88))
    }
    func testNavigationPurposeDoesNotImplyLocationShare() throws {
        var consent = NavigationDestinationConsent()
        XCTAssertFalse(consent.allowsNavigationDestination)
        XCTAssertFalse(consent.allowsLocationShare)
        consent.grant(.inAppNavigationDestination)
        XCTAssertTrue(consent.allows(.inAppNavigationDestination))
        XCTAssertFalse(consent.allows(.locationShare))
        let destination = try destination()
        XCTAssertNoThrow(try consent.startInAppNavigation(destination))
        XCTAssertThrowsError(try consent.publishLocationShare(destination)) { error in
            XCTAssertEqual(error as? NavigationConsentFailure, .locationShareConsentRequired)
        }
        XCTAssertThrowsError(try consent.sharePayload(from: destination)) { error in
            XCTAssertEqual(error as? NavigationConsentFailure, .destinationIsNotSharePayload)
        }
    }
    func testLocationShareDoesNotImplyNavigationDestination() throws {
        var share = NavigationDestinationConsent()
        share.grant(.locationShare)
        XCTAssertTrue(share.allowsLocationShare)
        XCTAssertFalse(share.allowsNavigationDestination)
        let destination = try destination()
        XCTAssertNoThrow(try share.publishLocationShare(destination))
        XCTAssertThrowsError(try share.startInAppNavigation(destination)) { error in
            XCTAssertEqual(error as? NavigationConsentFailure, .navigationDestinationConsentRequired)
        }
        var navigation = NavigationDestinationConsent()
        navigation.grant(.inAppNavigationDestination)
        XCTAssertNoThrow(try NavigationDestinationConsent.split(navigation, share: share))
        share.grant(.inAppNavigationDestination)
        XCTAssertThrowsError(try NavigationDestinationConsent.split(navigation, share: share)) { error in
            XCTAssertEqual(error as? NavigationConsentFailure, .purposeMismatch)
        }
        navigation.revoke(.inAppNavigationDestination)
        XCTAssertFalse(navigation.allowsNavigationDestination)
    }
}
