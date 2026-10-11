import XCTest
@testable import Questify

@MainActor final class ClubMerchantProfileReadTests: XCTestCase {
    private let owner = PublicMerchantOwnerID(41)!
    private func reader(_ base: MerchantProfileTestReader, current: @escaping () -> Bool = { true }) -> ClubMerchantProfileReader {
        .init(base: base, owner: owner, capturedScope: base.scope, isCurrent: current)
    }
    func testExactOwnerTargetAndReturnedIdentity() async throws {
        let base = MerchantProfileTestReader()
        let value = try await reader(base).home(.ownerMemberID(owner))
        XCTAssertEqual(value.memberId, 41); XCTAssertEqual(value.id, 8)
        XCTAssertEqual(base.targets, [.ownerMemberID(owner)])
    }
    func testWrongOwnerOrLegacyMerchantIDNeverDispatch() async {
        let base = MerchantProfileTestReader()
        let actual = reader(base)
        for target in [PublicMerchantHomeTarget.ownerMemberID(PublicMerchantOwnerID(42)!), .legacyMerchantRowID(PublicMerchantRowID(8)!)] {
            do { _ = try await actual.home(target); XCTFail("Unexpected read") } catch {}
        }
        XCTAssertTrue(base.targets.isEmpty)
    }
    func testWrongReturnedOwnerOrMissingMerchantIDIsRejected() async {
        for json in [#"{"id":8,"memberId":42}"#, #"{"memberId":41}"#, #"{"id":0,"memberId":41}"#, #"{"id":8}"#] {
            let base = MerchantProfileTestReader(); base.json = json
            do { _ = try await reader(base).home(.ownerMemberID(owner)); XCTFail("Unexpected identity") }
            catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .unavailable) }
        }
    }
    func testRetiredSelectionAndChangedReaderScopeCannotStartRead() async {
        let base = MerchantProfileTestReader()
        var current = true
        let scoped = reader(base, current: { current })
        current = false
        do { _ = try await scoped.home(.ownerMemberID(owner)); XCTFail("Retired read") } catch {}
        current = true; base.scope = UUID()
        do { _ = try await scoped.home(.ownerMemberID(owner)); XCTFail("Replaced reader") } catch {}
        XCTAssertTrue(base.targets.isEmpty)
    }
    func testLateSuccessAfterCloseCannotPublish() async throws {
        let base = MerchantProfileTestReader(); base.hold = true
        var current = true
        let scoped = reader(base, current: { current })
        let started = expectation(description: "public read started"); base.onRead = { started.fulfill() }
        let task = Task { try await scoped.home(.ownerMemberID(owner)) }
        await fulfillment(of: [started], timeout: 2)
        current = false; base.finish()
        do { _ = try await task.value; XCTFail("Late value escaped") }
        catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .unavailable) }
    }
    func testLateSuccessAfterReaderScopeReplacementCannotPublish() async throws {
        let base = MerchantProfileTestReader(); base.hold = true
        let scoped = reader(base)
        let started = expectation(description: "public read started"); base.onRead = { started.fulfill() }
        let task = Task { try await scoped.home(.ownerMemberID(owner)) }
        await fulfillment(of: [started], timeout: 2)
        base.scope = UUID(); base.finish()
        do { _ = try await task.value; XCTFail("Cross-scope value escaped") }
        catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .unavailable) }
    }
    func testCurrentFailureCanRetryButRetiredFailureCannotDispatchAgain() async throws {
        let base = MerchantProfileTestReader(); base.failure = .retryable
        var current = true
        let scoped = reader(base, current: { current })
        do { _ = try await scoped.home(.ownerMemberID(owner)); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
        base.failure = nil
        _ = try await scoped.home(.ownerMemberID(owner))
        current = false
        do { _ = try await scoped.home(.ownerMemberID(owner)); XCTFail("Retired retry") } catch {}
        XCTAssertEqual(base.targets.count, 2)
    }
    func testRepeatedTapCloseAndReopenCannotReactivateOldReadGate() throws {
        let route = try selection(), presentation = ClubMerchantProfilePresentation()
        presentation.open(route, isCurrent: { true })
        let first = try XCTUnwrap(presentation.selection)
        presentation.open(route, isCurrent: { true })
        XCTAssertEqual(presentation.selection?.id, first.id)
        presentation.close(); XCTAssertFalse(presentation.isCurrent(first))
        presentation.open(route, isCurrent: { true })
        let second = try XCTUnwrap(presentation.selection)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(presentation.isCurrent(first)); XCTAssertTrue(presentation.isCurrent(second))
    }
    func testPresentationAndContextRejectAuthorityOrHostRevisionLoss() throws {
        let route = try selection(), presentation = ClubMerchantProfilePresentation()
        var current = true
        presentation.open(route, isCurrent: { current })
        let opened = try XCTUnwrap(presentation.selection)
        current = false
        XCTAssertFalse(presentation.isCurrent(opened))
        presentation.close(); presentation.open(route, isCurrent: { false })
        XCTAssertNil(presentation.selection)
        let base = MerchantProfileTestReader()
        let profile = ClubMerchantProfileContext(key: .init(scope: base.scope, sessionRevision: 1, contentRevision: 2),
            home: .init(reader: base), isCurrent: { current })
        XCTAssertFalse(profile.canRead)
        current = true; XCTAssertTrue(profile.canRead)
        base.isConfigured = false; XCTAssertFalse(profile.canRead)
    }
    private func selection() throws -> ClubMerchantProfileSelection {
        let club = MerchantProfileTestClub(), directory = MerchantProfileTestDirectory(), model = ClubMerchantDiscoveryModel()
        let record = try JSONDecoder().decode(ClubRecord.self, from: Data(#"{"id":9,"isOwner":true}"#.utf8))
        let context = ClubMerchantDiscoveryContext(club: record, clubReader: club, reader: directory)
        model.bind(context)
        let permit = try XCTUnwrap(model.activate(context))
        let row = try ClubMerchantDiscoveryRow(value: .object(["memberId": .id(41)]), index: 0)
        return .init(row: row, owner: owner, permit: permit, generation: UUID())
    }
}

@MainActor private final class MerchantProfileTestReader: PublicMerchantHomeReading {
    var scope = UUID()
    var isConfigured = true
    let isOfflineExample = true
    var targets: [PublicMerchantHomeTarget] = []
    var json = #"{"id":8,"memberId":41,"name":"Cafe"}"#
    var failure: PublicMerchantHomeFailure?
    var hold = false
    var onRead: (() -> Void)?
    private var pending: CheckedContinuation<Void, Never>?
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        targets.append(target)
        if hold { await withCheckedContinuation { pending = $0; onRead?() } }
        else { onRead?() }
        if let failure { throw failure }
        return try JSONDecoder().decode(PublicMerchantHome.self, from: Data(json.utf8))
    }
    func finish() { let old = pending; pending = nil; old?.resume() }
}
@MainActor private final class MerchantProfileTestClub: ClubReading {
    let clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    let isClubConfigured = true
    func clubDetail(id: Int) async throws -> ClubRecord { throw CoopFlowFailure.unavailable }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class MerchantProfileTestDirectory: CoopFlowReading {
    let session: CoopFlowSession? = try! .init(accountID: 1, epoch: 1, token: "synthetic")
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { throw CoopFlowFailure.unavailable }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
