import XCTest
@testable import QuestifyCore

final class OrderPageReadbackTests: XCTestCase {
    func testFirstJourneyOrderPageReadbackSameOrderRecoverOriginal() throws {
        let source = CountingOrderPageEvents(InMemoryOriginalEventSource()
            .add(OriginalAuditEvent(
                requestId: "c11-order-readback", targetType: "RUN", targetId: 7,
                action: "START", afterJson: "UNKNOWN"))
            .add(OriginalAuditEvent(
                requestId: "c11-order-readback", targetType: "ORDER", targetId: 501,
                action: "CREATE", afterJson: "UNKNOWN"))
            .add(OriginalAuditEvent(
                requestId: "c11-order-readback", targetType: "ORDER", targetId: 999,
                action: "OTHER", afterJson: "UNKNOWN")))
        let locator = SupportEventLocator(originalEvents: source)
        let projection = SupportCurrentProjection(
            requestId: "c11-order-readback",
            appliedState: SupportEventLocator.projectionAppliedSuccess)
        let located = try XCTUnwrap(locator.locateByOrderId(501, currentProjection: nil))
        XCTAssertEqual(source.orderLookups, 1)
        XCTAssertEqual(located.orderId, 501)
        XCTAssertEqual(located.originalOutcome, "UNKNOWN")
        XCTAssertNotEqual(located.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(OrderPageReadback.openedID(requested: 501, events: located.originalEvents), 501)
        XCTAssertNil(OrderPageReadback.openedID(requested: 999, events: located.originalEvents))
        XCTAssertNotEqual(OrderPageReadback.openedID(requested: 999, events: located.originalEvents), Int64?(999))
        XCTAssertEqual(source.orderLookups, 1)

        let recovered = try XCTUnwrap(locator.recoverOriginal(
            originalRequestID: "c11-order-readback", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(recovered.requestId, "c11-order-readback")
        XCTAssertEqual(OrderPageReadback.firstOrderID(recovered.originalEvents), 501)
        XCTAssertEqual(source.orderLookups, 1)
    }

    func testAnotherOrderIdDoesNotOpen() throws {
        let source = InMemoryOriginalEventSource()
            .add(OriginalAuditEvent(
                requestId: "c11-order-other", targetType: "ORDER", targetId: 999,
                action: "CREATE", afterJson: "UNKNOWN"))
            .add(OriginalAuditEvent(
                requestId: "c11-order-other", targetType: "ORDER", targetId: 501,
                action: "CREATE", afterJson: "UNKNOWN"))
        let locator = SupportEventLocator(originalEvents: source)
        XCTAssertThrowsError(try locator.locateByOrderId(501, currentProjection: nil)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ORDER:501"))
        }
        let events = source.findByRequestId("c11-order-other")
        XCTAssertNil(OrderPageReadback.openedID(requested: 501, events: events))
        XCTAssertNotEqual(OrderPageReadback.openedID(requested: 501, events: events), Int64?(999))
        XCTAssertNil(OrderPageReadback.openedID(requested: 0, events: events))
        XCTAssertNil(try locator.locateByOrderId(nil, currentProjection: nil))
        XCTAssertNil(try locator.locateByOrderId(0, currentProjection: nil))
    }
}

final class CountingOrderPageEvents: SupportEventLocator.OriginalEventSource {
    private let inner: InMemoryOriginalEventSource
    private(set) var orderLookups = 0

    init(_ inner: InMemoryOriginalEventSource) { self.inner = inner }

    func findByRequestId(_ requestId: String) -> [OriginalAuditEvent] {
        inner.findByRequestId(requestId)
    }

    func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent? {
        if targetType == "ORDER" { orderLookups += 1 }
        return inner.findByTarget(targetType: targetType, targetId: targetId)
    }
}
