#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
import XCTest
@testable import Questify

@MainActor
final class SocialGraphAndProfilePrivacySectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesProfileEditSocialFourTabsAndVisibilityScopes() {
        let snapshot = SocialGraphAndProfilePrivacySnapshot.defaultReady

        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertEqual(snapshot.alertCount, 0)
        XCTAssertEqual(snapshot.rows.count, 3)

        let editRow = snapshot.row(for: .selfProfileEditRoundtrip)
        XCTAssertEqual(editRow?.referenceBadge, "w2-06")
        XCTAssertEqual(editRow?.status, .ready)

        let tabsRow = snapshot.row(for: .socialFourTabsParity)
        XCTAssertEqual(tabsRow?.verifiedTokens, ["following", "followers", "friends", "blacklist"])
        XCTAssertEqual(tabsRow?.status, .ready)

        let visibilityRow = snapshot.row(for: .profileVisibilityScopes)
        XCTAssertEqual(visibilityRow?.verifiedTokens, ["public", "friendsOnly", "private"])
        XCTAssertEqual(visibilityRow?.status, .ready)
    }

    func testMissingSocialTabOrVisibilityScopeTriggersAlertState() {
        let degradedSnapshot = SocialGraphAndProfilePrivacySnapshot(
            selfProfileRoundtripVerified: true,
            availableSocialTabs: ["following", "followers", "friends"],
            availableVisibilityScopes: ["public", "private"]
        )

        XCTAssertFalse(degradedSnapshot.isAllReady)
        XCTAssertEqual(degradedSnapshot.alertCount, 2)
        XCTAssertEqual(degradedSnapshot.row(for: .selfProfileEditRoundtrip)?.status, .ready)
        XCTAssertEqual(degradedSnapshot.row(for: .socialFourTabsParity)?.status, .alert)
        XCTAssertEqual(degradedSnapshot.row(for: .socialFourTabsParity)?.detailText.contains("blacklist"), true)
        XCTAssertEqual(degradedSnapshot.row(for: .profileVisibilityScopes)?.status, .alert)
        XCTAssertEqual(degradedSnapshot.row(for: .profileVisibilityScopes)?.detailText.contains("friendsOnly"), true)
    }

    func testMainActorViewBodyInstantiationAndRowSelectionCallback() throws {
        let snapshot = SocialGraphAndProfilePrivacySnapshot.defaultReady
        var selectedRow: SocialProfileParityRow?

        let view = SocialGraphAndProfilePrivacySectionView(
            snapshot: snapshot,
            onSelectRow: { row in
                selectedRow = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let targetRow = try XCTUnwrap(snapshot.row(for: .socialFourTabsParity))
        view.onSelectRow?(targetRow)
        XCTAssertEqual(selectedRow, targetRow)
    }
}
