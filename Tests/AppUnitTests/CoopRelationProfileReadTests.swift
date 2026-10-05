import XCTest
@testable import Questify

@MainActor final class CoopRelationProfileReadTests: XCTestCase {
    func testMerchantAdapterRejectsRowNamespaceBeforeAnyRead() async throws {
        let base = RelationMerchantBase(), owner = PublicMerchantOwnerID(41)!
        let reader = CoopRelationMerchantReader(base: base, owner: owner, isCurrent: { true })
        do { _ = try await reader.home(.legacyMerchantRowID(PublicMerchantRowID(41)!)); XCTFail() } catch { }
        do { _ = try await reader.home(.ownerMemberID(PublicMerchantOwnerID(8)!)); XCTFail() } catch { }
        XCTAssertEqual(base.reads, 0)
        let home = try await reader.home(.ownerMemberID(owner))
        XCTAssertEqual(home.memberId, 41); XCTAssertEqual(base.reads, 1)
    }
    func testMerchantAdapterRejectsMissingMismatchedAndStaleReturnedIdentity() async throws {
        let owner = PublicMerchantOwnerID(41)!
        for json in [#"{"id":8,"memberId":8}"#, #"{"id":8}"#, #"{"memberId":41}"#, #"{"id":0,"memberId":41}"#] {
            let base = RelationMerchantBase(); base.json = json
            let reader = CoopRelationMerchantReader(base: base, owner: owner, isCurrent: { true })
            do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail("Unverified owner accepted") } catch { }
        }
        let base = RelationMerchantBase(); var current = true
        base.hook = { current = false }
        let reader = CoopRelationMerchantReader(base: base, owner: owner, isCurrent: { current })
        do { _ = try await reader.home(.ownerMemberID(owner)); XCTFail() } catch { }
        XCTAssertFalse(reader.isConfigured)
    }
    func testClubAdapterAllowsOnlySelectedReadAndRejectsStaleReadback() async throws {
        let base = RelationClubBase(); var current = true
        let reader = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { current })
        do { _ = try await reader.clubDetail(id: 41); XCTFail() } catch { }
        do { _ = try await reader.clubHome(); XCTFail() } catch { }
        XCTAssertEqual(base.reads, 0)
        let club = try await reader.clubDetail(id: 9)
        XCTAssertEqual(club.id, 9)
        base.hook = { current = false }
        do { _ = try await reader.clubDetail(id: 9); XCTFail() } catch { }
        XCTAssertFalse(reader.isClubConfigured)
    }
    func testOlderClubRefreshUnauthorizedCannotExpireNewerSuccessfulRead() async throws {
        let wire = RelationSuspendedWire()
        let session = try ClubReadSession(accountID: 1, epoch: 1, token: "same")
        var expired = 0
        let service = ClubService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire)
        let base = ClubSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        let reader = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { true })
        let old = Task { try await reader.clubDetail(id: 9) }
        await wire.waitForFirst()
        let newer = try await reader.clubDetail(id: 9)
        XCTAssertEqual(newer.id, 9)
        await wire.finishOldUnauthorized()
        do { _ = try await old.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    func testClubAdapterRejectsWrongReturnedClub() async throws {
        let base = RelationClubBase(); base.returnedID = 41
        let reader = CoopRelationClubProfileReader(base: base, clubID: 9, isCurrent: { true })
        do { _ = try await reader.clubDetail(id: 9); XCTFail() } catch { }
    }
}
@MainActor private final class RelationMerchantBase: PublicMerchantHomeReading {
    let scope = UUID(), isConfigured = true, isOfflineExample = true
    var reads = 0
    var json = #"{"id":8,"memberId":41}"#
    var hook: (() -> Void)?
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        reads += 1; hook?()
        return try JSONDecoder().decode(PublicMerchantHome.self, from: Data(json.utf8))
    }
}
@MainActor private final class RelationClubBase: ClubReading {
    let isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var returnedID = 9
    var reads = 0
    var hook: (() -> Void)?
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1; hook?()
        return try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(returnedID)}".utf8))
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}

private actor RelationSuspendedWire: HTTPTransport {
    private var count = 0
    private var first: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        count += 1
        if count == 1 { return try await withCheckedThrowingContinuation { first = $0 } }
        return (Data(#"{"code":200,"data":{"id":9}}"#.utf8), 200)
    }
    func waitForFirst() async { while first == nil { await Task.yield() } }
    func finishOldUnauthorized() { first?.resume(returning: (Data(#"{"code":401}"#.utf8), 401)); first = nil }
}
