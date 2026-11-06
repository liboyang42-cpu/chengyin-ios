import Foundation
import XCTest
@testable import QuestifyCore

@MainActor
final class OpsAuditTrailTests: XCTestCase {
    func testTrailIsBoundedAndKeepsNewestEvents() {
        let trail = OpsAuditTrail(capacity: 3, now: { Date(timeIntervalSince1970: 1) })
        for _ in 0..<5 { trail.record(.readTimedOut) }
        trail.record(.writeOutcomeUnknown)
        XCTAssertEqual(trail.events.count, 3)
        XCTAssertEqual(trail.events.last?.kind, .writeOutcomeUnknown)
    }

    func testDecisionRecordingIsTransparentAndProceedIsNotLogged() {
        let trail = OpsAuditTrail()
        let theme = OpsKillSwitchTarget(layer: .theme, identifier: "12")!
        XCTAssertEqual(trail.record(OpsGateDecision.proceed), .proceed)
        XCTAssertTrue(trail.events.isEmpty)
        XCTAssertEqual(trail.record(OpsGateDecision.blocked(theme, .aiDisabled)), .blocked(theme, .aiDisabled))
        XCTAssertEqual(trail.events.first?.layer, .theme)
        XCTAssertEqual(trail.events.first?.targetIdentifier, "12")
        XCTAssertEqual(trail.events.first?.incident, .aiDisabled)
        trail.record(OpsGateDecision.preserved)
        XCTAssertEqual(trail.events.last?.kind, .preservedServiceAllowed)
        trail.clear()
        XCTAssertTrue(trail.events.isEmpty)
    }

    func testCapacityIsClamped() {
        XCTAssertEqual(OpsAuditTrail(capacity: 0).capacity, 1)
        XCTAssertEqual(OpsAuditTrail(capacity: 10_000).capacity, 512)
    }
}
