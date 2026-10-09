import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamPlayerProfileSelectionViewTests: XCTestCase {
    private func player() throws -> RoamPlayer {
        try JSONDecoder().decode(RoamPlayer.self, from: Data(#"{"memberId":82,"nickname":"Synthetic player","lat":1.234567,"lng":2.345678}"#.utf8))
    }
    func testOverviewDoesNotAutomaticallyOpenProfileOrPassLocationToFactory() throws {
        var memberIDs: [Int] = []
        let host = UIHostingController(rootView: RoamItemDetailView(item: .player(try player()), reader: RoamFixtureReader(),
            playerProfileDestination: { memberIDs.append($0); return AnyView(Text("Synthetic public profile")) }))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertTrue(memberIDs.isEmpty)
    }
    func testActualReaderSelectionExposesOnlyTargetMemberIDAndRejectsReplacementReader() throws {
        let reader = RoamFixtureReader(), other = RoamFixtureReader(), player = try player(), presentation = UUID()
        @MainActor func context(_ value: RoamFixtureReader) throws -> RoamEventNavigationScope {
            try XCTUnwrap(.init(readerID: ObjectIdentifier(value), identity: value.identity, area: value.searchArea,
                               presentationID: presentation, isConfigured: value.isConfigured))
        }
        let original = try context(reader), changed = try context(other)
        let selected = try XCTUnwrap(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: original))
        let profileArgument: Int = selected.memberID
        XCTAssertEqual(profileArgument, 82)
        XCTAssertNotEqual(profileArgument, original.identity.accountID)
        XCTAssertFalse(selected.mayRemainOpen(in: changed))
        XCTAssertNil(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: changed))
    }
}
