import XCTest
@testable import QuestifyCore

final class WebhookSsrfHopGuardTests: XCTestCase {
    private let guardRail = WebhookSsrfHopGuard()

    func testFirstJourneyPublicHttpsHopAllowedWithoutDnsRecoverOriginal() throws {
        let verdict = guardRail.inspect(WebhookSsrfHopGuard.publicHop())
        XCTAssertTrue(verdict.allowed())
        XCTAssertEqual(verdict.decision, .allow)
        let original = guardRail.recoverOriginal(
            originalRequestID: "evt-E", hops: [WebhookSsrfHopGuard.publicHop()])
        XCTAssertTrue(original.allowed)
        XCTAssertEqual(original.decision, .allow)
    }

    func testHttpSchemeAndUserinfoAndNon443AreRejected() {
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of("http://hooks.example.test/c09")).decision,
                       .rejectScheme)
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of(
            "https://user:pass@hooks.example.test/c09", WebhookSsrfHopGuard.publicTestNet())).decision,
                       .rejectUserinfo)
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of(
            "https://hooks.example.test:8443/c09", WebhookSsrfHopGuard.publicTestNet())).decision,
                       .rejectPort)
    }

    func testHostnameWithoutFixtureResolutionFailsClosed() {
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of("https://hooks.example.test/c09")).decision,
                       .rejectUnresolved)
    }

    func testLiteralLoopbackAndPrivateAndMetadataAreRejected() {
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of("https://127.0.0.1/hook")).decision,
                       .rejectPrivate)
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of(
            "https://hooks.example.test/c09", "10.0.0.1")).decision, .rejectPrivate)
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of(
            "https://hooks.example.test/c09", "169.254.169.254")).decision, .rejectPrivate)
        XCTAssertEqual(guardRail.inspect(WebhookSsrfHopGuard.Hop.of("https://224.0.0.1/hook")).decision,
                       .rejectPrivate)
    }

    func testEachRedirectHopIsInspectedIndependentlyWithoutFollowing() {
        let allowed = guardRail.inspectChain([WebhookSsrfHopGuard.publicHop()])
        XCTAssertTrue(allowed.allowed)
        let poisoned = guardRail.inspectChain([
            WebhookSsrfHopGuard.publicHop(),
            WebhookSsrfHopGuard.Hop.of("https://127.0.0.1/steal")
        ])
        XCTAssertFalse(poisoned.allowed)
        XCTAssertEqual(poisoned.decision, .rejectPrivate)
        XCTAssertThrowsError(try guardRail.assertSafeChain([
            WebhookSsrfHopGuard.publicHop(),
            WebhookSsrfHopGuard.Hop.of("https://10.0.0.1/x")
        ])) { error in
            XCTAssertEqual(error as? NotifyFailure, .ssrfRejected("私网/回环/链路本地/组播"))
        }
        XCTAssertEqual(guardRail.inspectChain([
            WebhookSsrfHopGuard.publicHop(),
            WebhookSsrfHopGuard.publicHop(),
            WebhookSsrfHopGuard.publicHop(),
            WebhookSsrfHopGuard.publicHop()
        ]).decision, .rejectHopLimit)
    }
}
