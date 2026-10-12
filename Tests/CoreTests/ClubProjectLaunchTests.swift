import XCTest
@testable import QuestifyCore

@MainActor final class ClubProjectLaunchTests: XCTestCase {
    func testTwoModesKeepExactSourceValuesAndClubID() throws {
        let f = LaunchFixture()
        XCTAssertEqual(ProjectEditProduct.city.rawValue, 1); XCTAssertEqual(ProjectEditProduct.freeExplore.rawValue, 2)
        for product in ProjectEditProduct.allCases {
            let seed = try f.context.seed(product: product)
            XCTAssertEqual(seed.product, product); XCTAssertEqual(seed.clubID, 81)
        }
    }
    func testOnlyClubIDDiffersFromExistingDraftDefaults() throws {
        let f = LaunchFixture()
        for product in ProjectEditProduct.allCases {
            var expected = ProjectEditDraft(product: product); expected.clubID = 81
            XCTAssertEqual(try f.context.seed(product: product), expected)
        }
    }
    func testAdminOrMemberCannotMintOwnerSeed() {
        let f = LaunchFixture()
        for admin in [true, false] {
            f.reader.club = LaunchReader.record(owner: false, admin: admin)
            XCTAssertFalse(f.context.canRead); XCTAssertThrowsError(try f.context.seed(product: .city))
        }
    }
    func testSignedOutUnconfiguredAndMissingEditorContextCannotLaunch() {
        let f = LaunchFixture(); f.reader.clubIdentity = .init(accountID: nil, epoch: 1); XCTAssertFalse(f.context.canRead)
        f.reader.clubIdentity = .init(accountID: 701, epoch: 1); f.reader.isClubConfigured = false; XCTAssertFalse(f.context.canRead)
        f.reader.isClubConfigured = true; f.editorID = ""; XCTAssertFalse(f.context.canRead)
    }
    func testReaderIdentityEpochAndConfigurationContextMustMatch() {
        let f = LaunchFixture(), c = f.context
        XCTAssertTrue(c.matches(reader: f.reader, editorContextID: f.editorID))
        XCTAssertFalse(c.matches(reader: LaunchReader(), editorContextID: f.editorID))
        f.editorID = "new-config"; XCTAssertFalse(c.matches(reader: f.reader, editorContextID: f.editorID))
        f.reader.clubIdentity = .init(accountID: 701, epoch: 2); XCTAssertFalse(c.matches(reader: f.reader, editorContextID: c.editorContextID))
    }
    func testTargetNeedsMatchingProjectAccountAndEpoch() throws {
        let f = LaunchFixture(), target = try ClubProjectLaunchTarget(context: f.context, product: .city)
        XCTAssertTrue(target.matches(projectSession: try .init(accountID: 701, epoch: 1, storageNamespace: "synthetic")))
        XCTAssertFalse(target.matches(projectSession: try .init(accountID: 702, epoch: 1, storageNamespace: "synthetic")))
        XCTAssertFalse(target.matches(projectSession: try .init(accountID: 701, epoch: 2, storageNamespace: "synthetic")))
        XCTAssertFalse(target.matches(projectSession: nil))
    }
    func testSeparateSelectionsHaveSeparatePresentationIdentity() throws {
        let f = LaunchFixture(), a = try ClubProjectLaunchTarget(context: f.context, product: .city), b = try ClubProjectLaunchTarget(context: f.context, product: .city)
        XCTAssertNotEqual(a.id, b.id); XCTAssertEqual(a.seed, b.seed)
    }
    func testAnotherClubSeedNeverReusesOriginalClubID() throws {
        let f = LaunchFixture(), original = f.context
        f.reader.club = LaunchReader.record(id: 82)
        XCTAssertEqual(try original.seed(product: .city).clubID, 81)
        XCTAssertEqual(try f.context.seed(product: .freeExplore).clubID, 82)
        XCTAssertNotEqual(original, f.context)
    }
}
@MainActor private final class LaunchReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var club = LaunchReader.record()
    var reads = 0
    var failure = false
    var held = false
    var pending: [CheckedContinuation<ClubRecord, Error>] = []
    var entered: (() -> Void)?
    static func record(id: Int = 81, owner: Bool = true, admin: Bool = false) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner),\"viewerIsAdmin\":\(admin)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1; XCTAssertEqual(id, 81)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw CoopFlowFailure.unavailable }; return club
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class LaunchFixture {
    let reader = LaunchReader()
    var editorID = "session:1:config:1"
    var context: ClubProjectLaunchContext { .init(club: reader.club, reader: reader, editorContextID: editorID) }
}
