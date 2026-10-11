import XCTest
@testable import QuestifyCore

@MainActor final class ClubMerchantProfileSelectionTests: XCTestCase {
    private func ready() async throws -> (ClubMerchantDiscoveryModel, ProfileClubReader, ProfileDirectoryReader, ClubMerchantDiscoveryContext, ClubMerchantDiscoveryModel.Permit) {
        let model = ClubMerchantDiscoveryModel(), club = ProfileClubReader(), directory = ProfileDirectoryReader()
        let scope = ClubMerchantDiscoveryContext(club: club.value, clubReader: club, reader: directory)
        model.bind(scope)
        let permit = try XCTUnwrap(model.activate(scope))
        await model.load(clubReader: club, reader: directory, permit: permit)
        return (model, club, directory, scope, permit)
    }
    func testOwnerMemberIdentityNeverUsesMerchantOrPositionalID() throws {
        let row = try ClubMerchantDiscoveryRow(value: .object(["id": .id(8), "memberId": .id(41)]), index: 0)
        XCTAssertEqual(row.id, 0); XCTAssertEqual(row.ownerMemberID?.rawValue, 41)
        XCTAssertEqual(PublicMerchantHomeTarget.ownerMemberID(try XCTUnwrap(row.ownerMemberID)).fields, ["memberId": 41])
    }
    func testMissingAndMalformedOwnerMetadataKeepsReadableCardWithoutRoute() throws {
        for value in [CoopFlowJSON.null, .bool(true), .id(0), .id(-1), .number(1.5), .string("oops"), .string("1.5"), .string("99999999999999999999999")] {
            let row = try ClubMerchantDiscoveryRow(value: .object(["name": .string("Cafe"), "id": .id(8), "memberId": value]), index: 0)
            XCTAssertEqual(row.name, "Cafe"); XCTAssertNil(row.ownerMemberID)
        }
        let row = try ClubMerchantDiscoveryRow(value: .object(["memberId": .string("41")]), index: 7)
        XCTAssertEqual(row.ownerMemberID?.rawValue, 41)
    }
    func testAcceptedVisibleCardCreatesPublicSelectionWithoutExtraRead() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        let row = try XCTUnwrap(model.rows(in: scope).first)
        let target = try XCTUnwrap(model.profileSelection(row: row, permit: permit))
        XCTAssertEqual(target.owner.rawValue, 41)
        XCTAssertTrue(model.isCurrent(target, clubReader: club, reader: directory))
        XCTAssertEqual(club.reads, 1); XCTAssertEqual(directory.reads, 1)
    }
    func testFilteredOrForgedCardCannotCreateSelection() async throws {
        let (model, _, _, scope, permit) = try await ready()
        let row = try XCTUnwrap(model.rows(in: scope).first)
        model.setKeyword("missing", permit: permit)
        XCTAssertNil(model.profileSelection(row: row, permit: permit))
        model.setKeyword("", permit: permit)
        let forged = try ClubMerchantDiscoveryRow(value: .object(["name": .string("Cafe"), "memberId": .id(99)]), index: row.id)
        XCTAssertNil(model.profileSelection(row: forged, permit: permit))
    }
    func testSameRowsAfterRefreshRetireOldSelection() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        let target = try XCTUnwrap(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
        await model.load(clubReader: club, reader: directory, permit: permit)
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
        XCTAssertNotNil(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
    }
    func testLeavingAndReactivatingSameContextRetiresOldPermit() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        let target = try XCTUnwrap(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
        model.leave(scope)
        let next = try XCTUnwrap(model.activate(scope))
        await model.load(clubReader: club, reader: directory, permit: next)
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
        XCTAssertNil(model.profileSelection(row: target.row, permit: permit))
    }
    func testOwnerLossBindsBeforeOldCallbackCanDispatch() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        let target = try XCTUnwrap(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
        let changed = ClubMerchantDiscoveryContext(club: ProfileClubReader.record(owner: false), clubReader: club, reader: directory)
        model.bind(changed)
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
        XCTAssertNil(model.profileSelection(row: target.row, permit: permit))
    }
    func testAccountEpochAndReaderReplacementRetireSelection() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        let target = try XCTUnwrap(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
        XCTAssertFalse(model.isCurrent(target, clubReader: ProfileClubReader(), reader: directory))
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: ProfileDirectoryReader()))
        club.clubIdentity = .init(accountID: 1, epoch: 2)
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
        club.clubIdentity = .init(accountID: 2, epoch: 1)
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
    }
    func testTokenReplacementAndReadDisableRetireSelection() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        let target = try XCTUnwrap(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
        directory.session = try .init(accountID: 1, epoch: 1, token: "replacement")
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
        club.isClubConfigured = false
        XCTAssertFalse(model.isCurrent(target, clubReader: club, reader: directory))
    }
    func testSelectionAndReadOnlyReturnDoNotResetSearchOrDispatch() async throws {
        let (model, club, directory, scope, permit) = try await ready()
        model.setKeyword("cafe", permit: permit)
        let target = try XCTUnwrap(model.profileSelection(row: model.rows(in: scope)[0], permit: permit))
        XCTAssertTrue(model.isCurrent(target, clubReader: club, reader: directory))
        XCTAssertEqual(model.keyword(in: scope), "cafe"); XCTAssertEqual(model.rows(in: scope).count, 1)
        XCTAssertEqual(directory.reads, 1)
    }
}

@MainActor private final class ProfileClubReader: ClubReading {
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var isClubConfigured = true
    var reads = 0
    var value = ProfileClubReader.record()
    static func record(owner: Bool = true) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":9,\"isOwner\":\(owner)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return value }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
}
@MainActor private final class ProfileDirectoryReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID: 1, epoch: 1, token: "synthetic")
    var reads = 0
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        reads += 1
        return .array([.object(["id": .id(8), "memberId": .id(41), "name": .string("Cafe")])])
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
