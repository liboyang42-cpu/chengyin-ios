import XCTest
@testable import QuestifyCore

final class NativeNavigationCompletionTests: XCTestCase {
    func testTeamInternalRouteDecodesOnceAndPreservesReturnID() throws {
        guard case .teamInvitation(let route) = NativeNavigationContract.parseInternal("/team/join?code=A%2BB&fromTeamId=71") else { return XCTFail() }
        XCTAssertEqual(route.code, "A+B"); XCTAssertEqual(route.fromTeamID, 71)
    }
    func testTeamRejectsDuplicateFieldsInvalidIDsAndInjectedRole() {
        for route in ["/team/join", "/team/join?code=", "/team/join?code=A&code=B", "/team/join?code=A&fromTeamId=0", "/team/join?code=A&fromTeamId=01", "/team/join?code=A&role=leader", "/team/%6aoin?code=A", "/team/join?code=A%0A", "//evil.example/team/join?code=A", "https://evil.example/team/join?code=A"] {
            XCTAssertNil(NativeNavigationContract.parseInternal(route), route)
        }
    }
    func testManualCodeDoesNotAcceptURLOrControlCharacters() {
        XCTAssertThrowsError(try TeamInvitationRoute(code: "https://evil.example/join"))
        XCTAssertThrowsError(try TeamInvitationRoute(code: "A\n"))
        XCTAssertThrowsError(try TeamInvitationRoute(code: String(repeating: "A", count: 513)))
        XCTAssertEqual(try TeamInvitationRoute(code: "  synthetic  ").code, "synthetic")
    }
    func testBadgeQueryRouteIsPresentationWithoutOwnershipClaim() {
        guard case .badge(let badge) = NativeNavigationContract.parseInternal("/badge?name=Synthetic&sub=Example&style=glow&rarity=9&img=javascript%3Aalert") else { return XCTFail() }
        XCTAssertEqual(badge.name, "Synthetic"); XCTAssertEqual(badge.rarity, 4); XCTAssertEqual(badge.style, "glow"); XCTAssertTrue(badge.image.isEmpty)
    }
    func testBadgeMalformedAndDuplicateFieldsFailClosed() {
        for route in ["/badge?name=A&name=B", "/badge?ownerId=1", "/badge?name=A%00", "/badge#fragment", "/badge?name=" + String(repeating: "x", count: 3000)] {
            XCTAssertNil(NativeNavigationContract.parseInternal(route))
        }
    }
    func testExternalNavigationNeedsExactApprovedHTTPSOrigin() {
        let good = URL(string: "https://example.test/team/join?code=SYNTHETIC")!
        XCTAssertNil(NativeEntryLinkPolicy().parse(good))
        let policy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
        guard case .teamInvitation = policy.parse(good) else { return XCTFail() }
        for raw in ["http://example.test/team/join?code=A", "custom://example.test/team/join?code=A", "https://example.test.evil/team/join?code=A", "https://user@example.test/team/join?code=A", "https://example.test:443/team/join?code=A", "https://example.test/team/join?code=A#x"] {
            XCTAssertNil(policy.parse(URL(string: raw)!))
        }
    }
    func testApprovedBadgeRouteAndUnknownPath() {
        let policy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
        guard case .badge = policy.parse(URL(string: "https://example.test/badge?name=Synthetic")!) else { return XCTFail() }
        XCTAssertNil(policy.parse(URL(string: "https://example.test/no-such-route")!))
    }
}
