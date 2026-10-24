import XCTest
@testable import QuestifyCore

final class ProfileOrderEventSourceInjectionTests: XCTestCase {
    func testFirstJourneyOpenedOrderPassesLoadedEventsAndRecoverOriginal() throws {
        let loaded = [
            OriginalAuditEvent(
                requestId: "c11-order-source", targetType: "ORDER", targetId: 501,
                action: "CREATE", afterJson: "UNKNOWN"),
            OriginalAuditEvent(
                requestId: "c11-order-source", targetType: "RUN", targetId: 77,
                action: "RUN_ATTACH", afterJson: "UNKNOWN"),
            OriginalAuditEvent(
                requestId: "c11-other-order", targetType: "RUN", targetId: 2,
                action: "START", afterJson: "PENDING"),
            OriginalAuditEvent(
                requestId: "c11-other-order", targetType: "ORDER", targetId: 9,
                action: "CREATE", afterJson: "PENDING"),
        ]
        var injection = ProfileOrderEventSourceInjection(events: loaded)
        let projection = SupportCurrentProjection(
            requestId: "c11-order-source",
            appliedState: SupportEventLocator.projectionAppliedSuccess)

        let opened = try XCTUnwrap(injection.lookupOpenedOrder(501, currentProjection: projection))
        XCTAssertEqual(opened, 501)
        XCTAssertEqual(injection.lookups, 1)
        XCTAssertEqual(injection.sends, 0)
        XCTAssertEqual(injection.events, loaded)

        let recovered = try XCTUnwrap(injection.recoverOriginal(
            requestID: "c11-order-source", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(recovered.orderId, 501)
        XCTAssertNotEqual(recovered.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(Self.firstOrderID(recovered.originalEvents), 501)
        XCTAssertEqual(injection.events, loaded)
        XCTAssertEqual(injection.sends, 0)

        XCTAssertThrowsError(try injection.lookupOpenedOrder(9, currentProjection: nil)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ORDER:9"))
        }
        XCTAssertEqual(injection.events, loaded)
        XCTAssertEqual(injection.sends, 0)
    }

    func testDifferentFirstOrderIDIsOriginalMissing() {
        let loaded = [
            OriginalAuditEvent(
                requestId: "c11-order-mixed", targetType: "ORDER", targetId: 9,
                action: "CREATE", afterJson: "UNKNOWN"),
            OriginalAuditEvent(
                requestId: "c11-order-mixed", targetType: "ORDER", targetId: 501,
                action: "ATTACH", afterJson: "UNKNOWN"),
        ]
        var injection = ProfileOrderEventSourceInjection(events: loaded)
        XCTAssertThrowsError(try injection.lookupOpenedOrder(501)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ORDER:501"))
        }
        XCTAssertEqual(injection.events, loaded)
        XCTAssertEqual(injection.sends, 0)
    }

    func testAbsentSourceStaysQuietAndDoesNotInventEvents() throws {
        var injection = ProfileOrderEventSourceInjection(events: nil)
        XCTAssertNil(injection.entry())
        XCTAssertNil(try injection.lookupOpenedOrder(501))
        XCTAssertNil(try injection.lookupOpenedOrder(0))
        XCTAssertNil(try injection.recoverOriginal(requestID: "c11-order-source", currentProjection: nil))
        XCTAssertNil(try injection.recoverOriginal(requestID: nil, currentProjection: nil))
        XCTAssertEqual(injection.lookups, 0)
        XCTAssertEqual(injection.sends, 0)
        XCTAssertNil(injection.events)
    }

    func testBlankRequestIDIsNotPromoted() throws {
        let loaded = [
            OriginalAuditEvent(requestId: nil, targetType: "ORDER", targetId: 501, action: "CREATE", afterJson: "UNKNOWN"),
            OriginalAuditEvent(requestId: "", targetType: "ORDER", targetId: 501, action: "CREATE", afterJson: "UNKNOWN"),
        ]
        var injection = ProfileOrderEventSourceInjection(events: loaded)
        XCTAssertThrowsError(try injection.lookupOpenedOrder(501)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ORDER:501"))
        }
        XCTAssertThrowsError(try injection.recoverOriginal(requestID: "ORDER:501", currentProjection: nil)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ORDER:501"))
        }
        XCTAssertEqual(injection.events, loaded)
        XCTAssertEqual(injection.sends, 0)
    }

    private static func firstOrderID(_ events: [OriginalAuditEvent]) -> Int64? {
        for event in events {
            guard event.targetType == "ORDER" else { continue }
            return event.targetId
        }
        return nil
    }
}
