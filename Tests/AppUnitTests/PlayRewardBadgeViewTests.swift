import XCTest
import SwiftUI
@testable import Questify

@MainActor final class PlayRewardBadgeViewTests: XCTestCase {
    func testReceiptRowsConstructWithoutReadingACollectionOrGrantingAReward() {
        let reader = RewardBadgeAppReader()
        let view = PlayRewardBadgeRows(targets: [PlayRewardBadgeTarget(code: "SYNTHETIC_BADGE", name: "Synthetic reward")!], destination: { target in
            AnyView(PlayRewardBadgeCollectionView(target: target, reader: reader))
        })
        _ = UIHostingController(rootView: NavigationStack { List { view } })
        XCTAssertEqual(reader.calls, 0, "Constructing a receipt must not read or award")
    }
    func testNoRewardRowsHaveNoIntrinsicContent() {
        let size = UIHostingController(rootView: PlayRewardBadgeRows(targets: []))
            .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        XCTAssertEqual(size.height, 0, accuracy: 0.1)
    }
    func testReceiptCopyGrowsAtAccessibilitySizeWithoutHorizontalOverflow() {
        let target = PlayRewardBadgeTarget(code: "SYNTHETIC_BADGE", name: String(repeating: "Synthetic badge / 测试徽章。", count: 8))!
        func measure(_ dynamicType: DynamicTypeSize) -> CGSize {
            UIHostingController(rootView: PlayRewardBadgeRows(targets: [target])
                .dynamicTypeSize(dynamicType)).sizeThatFits(in: CGSize(width: 300, height: 20_000))
        }
        let regular = measure(.large), maximum = measure(.accessibility5)
        XCTAssertGreaterThan(maximum.height, regular.height)
        XCTAssertLessThanOrEqual(maximum.width, 301)
    }
    func testIncompleteMissingAndLockedPresentationsRemainDistinct() throws {
        let locked = try JSONDecoder().decode(ProfileIdentityBadge.self, from: Data(#"{"badgeCode":"SYNTHETIC_BADGE","unlocked":false}"#.utf8))
        let cases: [PlayRewardBadgeFocus] = [.identity(locked), .missingFromWall, .incompleteWall, .ambiguous]
        for focus in cases {
            for language in ["en", "zh-Hans"] {
                let view = PlayRewardBadgeFocusContent(focus: focus)
                    .environment(\.locale, Locale(identifier: language)).dynamicTypeSize(.accessibility5)
                _ = UIHostingController(rootView: List { view })
            }
            XCTAssertNotEqual(focus.statusKey, "playBadge.confirmed")
        }
    }
}

@MainActor private final class RewardBadgeAppReader: ProfileReading {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 77, epoch: 1)
    var calls = 0
    func profileBadges() async throws -> ProfileBadgeWall { calls += 1; return .init(identities: [], medals: []) }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
}
