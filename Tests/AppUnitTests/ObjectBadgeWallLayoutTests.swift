import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ObjectBadgeWallLayoutTests: XCTestCase {
    private final class ReaderOwner {}
    private func owner(_ reader: ReaderOwner, account: Int = 7, epoch: UInt64 = 1,
                       signedIn: Bool = true, configured: Bool = true) -> ObjectBadgeWallLayoutOwner {
        .init(readerID: ObjectIdentifier(reader), identity: signedIn ? .init(accountID: account, epoch: epoch) : nil,
              isConfigured: configured)
    }
    func testDefaultAndExplicitModesUseOnlyLocalSelection() {
        let reader = ReaderOwner(), current = owner(reader)
        var selection = ObjectBadgeWallLayoutSelection()
        XCTAssertEqual(selection.value(for: current), .list)
        selection.choose(.wall, rendered: current, current: current)
        XCTAssertEqual(selection.value(for: current), .wall)
        selection.choose(.list, rendered: current, current: current)
        XCTAssertEqual(selection.value(for: current), .list)
        XCTAssertEqual(ObjectBadgeWallLayout.allCases.map(\.rawValue), ["list", "wall"])
    }
    func testRepeatedSelectionDoesNotToggleOrInventAnotherMode() {
        let reader = ReaderOwner(), current = owner(reader)
        var selection = ObjectBadgeWallLayoutSelection()
        for _ in 0..<3 { selection.choose(.wall, rendered: current, current: current) }
        XCTAssertEqual(selection.value(for: current), .wall)
        XCTAssertEqual(ObjectBadgeWallLayout.wall.titleKey, "objects.badgeLayout.wall")
    }
    func testAccountEpochSignOutAndConfigurationLossResolveToList() {
        let reader = ReaderOwner(), original = owner(reader)
        for replacement in [owner(reader, account: 8), owner(reader, epoch: 2),
                            owner(reader, signedIn: false), owner(reader, configured: false)] {
            var selection = ObjectBadgeWallLayoutSelection()
            selection.choose(.wall, rendered: original, current: original)
            XCTAssertEqual(selection.value(for: replacement), .list)
            selection.retire()
            XCTAssertEqual(selection.value(for: original), .list)
        }
    }
    func testReplacementReaderWithSameAccountDoesNotInheritLayout() {
        let first = ReaderOwner(), second = ReaderOwner(), original = owner(first), replacement = owner(second)
        var selection = ObjectBadgeWallLayoutSelection()
        selection.choose(.wall, rendered: original, current: original)
        XCTAssertEqual(selection.value(for: replacement), .list)
        selection.choose(.wall, rendered: replacement, current: replacement)
        XCTAssertEqual(selection.value(for: replacement), .wall)
        XCTAssertEqual(selection.value(for: original), .list)
    }
    func testOldRenderedControlCannotChangeCurrentOwnersChoice() {
        let reader = ReaderOwner(), old = owner(reader), current = owner(reader, epoch: 2)
        var selection = ObjectBadgeWallLayoutSelection()
        selection.choose(.wall, rendered: current, current: current)
        selection.choose(.list, rendered: old, current: current)
        XCTAssertEqual(selection.value(for: current), .wall)
        XCTAssertEqual(selection.value(for: old), .list)
    }
    func testUnavailableOwnerCannotStoreAChoice() {
        let reader = ReaderOwner()
        for current in [owner(reader, signedIn: false), owner(reader, configured: false)] {
            var selection = ObjectBadgeWallLayoutSelection()
            selection.choose(.wall, rendered: current, current: current)
            XCTAssertEqual(selection.value(for: current), .list)
            XCTAssertEqual(selection.value(for: owner(reader)), .list)
        }
    }
    func testRetirementNeedsAnotherExplicitCurrentSelection() {
        let reader = ReaderOwner(), current = owner(reader)
        var selection = ObjectBadgeWallLayoutSelection()
        selection.choose(.wall, rendered: current, current: current)
        selection.retire(); selection.retire()
        XCTAssertEqual(selection.value(for: current), .list)
        selection.choose(.wall, rendered: current, current: current)
        XCTAssertEqual(selection.value(for: current), .wall)
    }
    func testBilingualLargeTextLabelsAndControlConstructInBothLayouts() throws {
        let locked = try JSONDecoder().decode(ProfileIdentityBadge.self, from: Data(#"{"badgeName":"Long city identity 城市身份卡名称与保留的原文","unlocked":false}"#.utf8))
        let unlocked = try JSONDecoder().decode(ProfileMedal.self, from: Data(#"{"medalName":"Long earned medal 已获得的纪念章","kind":"achievement"}"#.utf8))
        for locale in ["en", "zh-Hans"] {
            for layout in ObjectBadgeWallLayout.allCases {
                let host = UIHostingController(rootView: ScrollView {
                    VStack(alignment: .leading) {
                        ObjectBadgeWallLayoutControl(selection: .constant(layout))
                        ObjectBadgeWallBadgeLabel(badge: .identity(locked), layout: layout)
                        ObjectBadgeWallBadgeLabel(badge: .medal(unlocked), layout: layout)
                    }
                }.environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
                host.loadViewIfNeeded()
                XCTAssertNotNil(host.view)
            }
        }
        XCTAssertFalse(locked.unlocked)
        XCTAssertTrue(unlocked.isAchievement)
    }
}
