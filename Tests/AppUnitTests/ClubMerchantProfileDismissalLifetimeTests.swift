import XCTest
@testable import Questify

/// Independent regressions: retain actual sheet bindings across close/reopen.
/// Existing read fixtures and business assertions remain unchanged.
@MainActor final class ClubMerchantProfileDismissalLifetimeTests: XCTestCase {
    func testOldSheetDismissalDoesNotCloseReopenedMerchant() throws {
        let presentation = ClubMerchantProfilePresentation(), route = try route()
        presentation.open(route, isCurrent: { true })
        let first = try XCTUnwrap(presentation.selection)
        let oldBinding = presentation.selectionBinding
        oldBinding.wrappedValue = nil
        XCTAssertNil(presentation.selection)
        XCTAssertFalse(presentation.isCurrent(first))
        presentation.open(route, isCurrent: { true })
        let second = try XCTUnwrap(presentation.selection)
        oldBinding.wrappedValue = nil
        XCTAssertEqual(presentation.selection?.id, second.id)
        XCTAssertTrue(presentation.isCurrent(second))
        presentation.selectionBinding.wrappedValue = nil
        XCTAssertNil(presentation.selection)
        XCTAssertFalse(presentation.isCurrent(second))
    }

    func testOldDestinationCloseCannotRetireNewVisit() throws {
        let presentation = ClubMerchantProfilePresentation(), route = try route()
        presentation.open(route, isCurrent: { true })
        let first = try XCTUnwrap(presentation.selection)
        let oldDestinationClose = { presentation.close(id: first.id) }
        presentation.close()
        presentation.open(route, isCurrent: { true })
        let second = try XCTUnwrap(presentation.selection)
        oldDestinationClose()
        XCTAssertEqual(presentation.selection?.id, second.id)
        XCTAssertFalse(presentation.isCurrent(first))
        XCTAssertTrue(presentation.isCurrent(second))
        presentation.close(id: second.id)
        XCTAssertNil(presentation.selection)
    }

    func testEmptyBindingCannotDismissLaterVisitAndRevocationStillWins() throws {
        let presentation = ClubMerchantProfilePresentation(), route = try route()
        let emptyBinding = presentation.selectionBinding
        var authorized = true
        presentation.open(route, isCurrent: { authorized })
        let opened = try XCTUnwrap(presentation.selection)
        emptyBinding.wrappedValue = nil
        XCTAssertTrue(presentation.isCurrent(opened))
        authorized = false
        XCTAssertFalse(presentation.isCurrent(opened))
        presentation.close()
        XCTAssertNil(presentation.selection)
        presentation.open(route, isCurrent: { authorized })
        XCTAssertNil(presentation.selection)
    }

    private func route() throws -> ClubMerchantProfileSelection {
        let club = DismissalClubReader(), directory = DismissalDirectoryReader()
        let record = try JSONDecoder().decode(ClubRecord.self, from: Data(#"{"id":9,"isOwner":true}"#.utf8))
        let context = ClubMerchantDiscoveryContext(club: record, clubReader: club, reader: directory)
        let model = ClubMerchantDiscoveryModel()
        model.bind(context)
        let permit = try XCTUnwrap(model.activate(context))
        let row = try ClubMerchantDiscoveryRow(value: .object(["memberId": .id(41)]), index: 0)
        return .init(row: row, owner: PublicMerchantOwnerID(41)!, permit: permit, generation: UUID())
    }
}

@MainActor private final class DismissalClubReader: ClubReading {
    let clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    let isClubConfigured = true
    func clubDetail(id: Int) async throws -> ClubRecord { throw CoopFlowFailure.unavailable }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class DismissalDirectoryReader: CoopFlowReading {
    let session: CoopFlowSession? = try! .init(accountID: 1, epoch: 1, token: "synthetic")
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { throw CoopFlowFailure.unavailable }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
