import XCTest
@testable import Questify

@MainActor final class ClubProfileDraftVisitTests: XCTestCase {
    private final class Storage: ClubProfileLocalDraftStorage {
        func read(key: String) throws -> ClubProfileLocalDraftBytes? { XCTFail("Visit must not read storage"); return nil }
        func replace(key: String, expected: ClubProfileLocalDraftBytes?, data: Data?) throws -> ClubProfileLocalDraftBytes? { XCTFail("Visit must not write storage"); return nil }
    }
    private final class Access: ClubOperationsAccess {
        var identity: ClubReadIdentity? = .init(accountID: 7, epoch: 1)
        var profileDrafts: ClubProfileLocalDraftContext?
        var isConfigured: Bool { true }
        var writeAvailability: ClubOperationsWriteAvailability { .unverified }
        func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot { throw APIError.notConfigured }
        func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt { XCTFail("No writer"); throw APIError.notConfigured }
    }
    func testNilVisitPreservesLegacyModeAndDoesNotAdoptLaterContext() {
        let access = Access(), visit = ClubProfileDraftVisit()
        visit.bind(target: .club(9), identity: access.identity, access: access)
        XCTAssertFalse(visit.enabled)
        XCTAssertTrue(visit.matches(target: .club(9), identity: access.identity, access: access))
        access.profileDrafts = .init(store: .init(storage: Storage()), namespace: "test", identity: access.identity!, viewerRevision: 1, current: { true })
        visit.bind(target: .club(9), identity: access.identity, access: access)
        XCTAssertFalse(visit.enabled)
    }
    func testEnabledVisitCannotDowngradeOrReviveAfterRevocation() {
        let access = Access(), visit = ClubProfileDraftVisit()
        let context = ClubProfileLocalDraftContext(store: .init(storage: Storage()), namespace: "test", identity: access.identity!, viewerRevision: 1, current: { true })
        access.profileDrafts = context
        visit.bind(target: .club(9), identity: access.identity, access: access)
        XCTAssertTrue(visit.enabled)
        XCTAssertTrue(visit.matches(target: .club(9), identity: access.identity, access: access))
        access.profileDrafts = nil
        XCTAssertFalse(visit.matches(target: .club(9), identity: access.identity, access: access))
        visit.retire(); access.profileDrafts = context
        visit.bind(target: .club(9), identity: access.identity, access: access)
        XCTAssertTrue(visit.enabled)
        XCTAssertFalse(visit.matches(target: .club(9), identity: access.identity, access: access))
    }
}
