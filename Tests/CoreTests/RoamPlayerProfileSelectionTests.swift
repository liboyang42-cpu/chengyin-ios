import XCTest
@testable import QuestifyCore

final class RoamPlayerProfileSelectionTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let presentation = UUID()
    private let lease = UUID()
    private func player(id: Int = 82, nickname: String = "Other player", latitude: Double = 1.234567) throws -> RoamPlayer {
        let data = try JSONSerialization.data(withJSONObject: ["memberId":id,"nickname":nickname,"lat":latitude,"lng":2.345678])
        return try JSONDecoder().decode(RoamPlayer.self, from: data)
    }
    private func scope(identity: RoamReadIdentity? = nil, area: RoamSearchArea? = nil,
                       presentation: UUID? = nil, readerID: ObjectIdentifier? = nil) throws -> RoamEventNavigationScope {
        try XCTUnwrap(.init(readerID: readerID ?? ObjectIdentifier(reader),
            identity: identity ?? .init(accountID: 7, epoch: 1, role: "player", areaRevision: 1, manualMapApprovalRevision: lease),
            area: area ?? .init(coordinate: .init(latitude: 10, longitude: 20)!, label: "Manual search"),
            presentationID: presentation ?? self.presentation, isConfigured: true))
    }
    func testOnlyReturnedMemberIDBecomesProfileTarget() throws {
        let player = try player(nickname: "999"), context = try scope()
        let selected = try XCTUnwrap(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: context, current: context))
        XCTAssertEqual(selected.memberID, 82); XCTAssertNotEqual(selected.memberID, context.identity.accountID)
        XCTAssertNotEqual(selected.memberID, 999)
        XCTAssertEqual(player.approximateCoordinate?.latitude, 1.234)
    }
    func testInvalidMemberOrMissingCurrentProjectionNeverBecomesProfile() throws {
        let context = try scope()
        for id in [0, -1] {
            let player = try player(id: id)
            XCTAssertNil(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: context, current: context))
        }
        let valid = try player()
        XCTAssertNil(RoamPlayerProfileSelection(player: valid, currentPlayer: nil, rendered: context, current: context))
        XCTAssertNil(RoamPlayerProfileSelection(player: valid, currentPlayer: valid, rendered: nil, current: nil))
    }
    func testChangedNicknameCoordinateOrMemberRejectsOldCapturedTap() throws {
        let original = try player(), context = try scope()
        for replacement in [try player(id: 83), try player(nickname: "Replacement"), try player(latitude: 3)] {
            XCTAssertNil(RoamPlayerProfileSelection(player: original, currentPlayer: replacement, rendered: context, current: context))
        }
    }
    func testNormalPushKeepsAcceptedReadButOldOverviewTapCannotBeReplayed() throws {
        let player = try player(), original = try scope(), retired = try scope(presentation: UUID())
        let selected = try XCTUnwrap(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: original))
        XCTAssertTrue(selected.mayRemainOpen(in: retired))
        XCTAssertNil(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: retired))
    }
    func testAccountRoleSessionAndApprovalChangesRevokeProfileReceipt() throws {
        let player = try player(), original = try scope()
        let selected = try XCTUnwrap(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: original))
        let identities = [RoamReadIdentity(accountID: 8, epoch: 1, role: "player", areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 2, role: "player", areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "merchant", areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", areaRevision: 2, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", areaRevision: 1, manualMapApprovalRevision: nil),
            .init(accountID: 7, epoch: 1, role: "player", areaRevision: 1, manualMapApprovalRevision: UUID())]
        for identity in identities {
            let changed = try scope(identity: identity)
            XCTAssertFalse(selected.mayRemainOpen(in: changed))
            XCTAssertNil(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: changed))
        }
    }
    func testReplacedReaderChangedManualAreaAndMissingScopeRetireSelection() throws {
        let player = try player(), original = try scope(), other = ReaderMarker()
        let selected = try XCTUnwrap(RoamPlayerProfileSelection(player: player, currentPlayer: player, rendered: original, current: original))
        XCTAssertFalse(selected.mayRemainOpen(in: try scope(readerID: ObjectIdentifier(other))))
        XCTAssertFalse(selected.mayRemainOpen(in: try scope(area: .init(coordinate: .init(latitude: 20, longitude: 30)!, label: "Elsewhere"))))
        XCTAssertFalse(selected.mayRemainOpen(in: nil))
    }
}
