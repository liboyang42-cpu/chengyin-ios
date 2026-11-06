import XCTest
@testable import Questify

final class MerchantCityPosterReadLifetimeTests: XCTestCase {
    private final class Owner {}
    func testBackgroundRetirementDoesNotReviveOnForegroundOrNewRequest() throws {
        let owner = Owner(), scope = UUID()
        var policy = MerchantCityPosterReadLifetime<String>()
        let old = try XCTUnwrap(policy.begin(owner: ObjectIdentifier(owner), scope: scope, source: "source", poiID: 1, active: true, authorized: true))
        XCTAssertTrue(policy.allows(old, owner: ObjectIdentifier(owner), scope: scope, source: "source", poiID: 1, active: true, authorized: true))
        policy.retire()
        XCTAssertFalse(policy.allows(old, owner: ObjectIdentifier(owner), scope: scope, source: "source", poiID: 1, active: true, authorized: true))
        let fresh = try XCTUnwrap(policy.begin(owner: ObjectIdentifier(owner), scope: scope, source: "source", poiID: 1, active: true, authorized: true))
        XCTAssertNotEqual(old, fresh)
        XCTAssertFalse(policy.allows(old, owner: ObjectIdentifier(owner), scope: scope, source: "source", poiID: 1, active: true, authorized: true))
    }
    func testSameScopeDenialSourceReplacementAndOwnerChangeRejectLateResult() throws {
        let owner = Owner(), replacement = Owner(), scope = UUID()
        var policy = MerchantCityPosterReadLifetime<String>()
        let ticket = try XCTUnwrap(policy.begin(owner: ObjectIdentifier(owner), scope: scope, source: "original", poiID: 1, active: true, authorized: true))
        XCTAssertFalse(policy.allows(ticket, owner: ObjectIdentifier(owner), scope: scope, source: "original", poiID: 1, active: true, authorized: false))
        XCTAssertFalse(policy.allows(ticket, owner: ObjectIdentifier(owner), scope: scope, source: "replaced", poiID: 1, active: true, authorized: true))
        XCTAssertFalse(policy.allows(ticket, owner: ObjectIdentifier(replacement), scope: scope, source: "original", poiID: 1, active: true, authorized: true))
        XCTAssertFalse(policy.allows(ticket, owner: ObjectIdentifier(owner), scope: scope, source: "original", poiID: 2, active: true, authorized: true))
        XCTAssertFalse(policy.allows(ticket, owner: ObjectIdentifier(owner), scope: UUID(), source: "original", poiID: 1, active: true, authorized: true))
        XCTAssertFalse(policy.allows(ticket, owner: ObjectIdentifier(owner), scope: scope, source: "original", poiID: 1, active: false, authorized: true))
    }
    func testUnavailableEntryNeverIssuesPermitAndRetiresPrevious() {
        let owner = Owner(), scope = UUID()
        var policy = MerchantCityPosterReadLifetime<Int>()
        XCTAssertNil(policy.begin(owner: ObjectIdentifier(owner), scope: scope, source: 1, poiID: 1, active: false, authorized: true))
        XCTAssertNil(policy.begin(owner: ObjectIdentifier(owner), scope: scope, source: 1, poiID: 1, active: true, authorized: false))
        XCTAssertNil(policy.begin(owner: ObjectIdentifier(owner), scope: scope, source: 1, poiID: 0, active: true, authorized: true))
        XCTAssertNil(policy.ticket)
    }
}
