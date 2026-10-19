import XCTest
@testable import QuestifyCore

final class ProfileOrderHistoryFilterTests: XCTestCase {
    private let now = OrderLifecycleTime.date("2026-10-11 12:00:00")!
    private func order(_ fields: String = "") throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data(("{\"id\":1" + (fields.isEmpty ? "" : "," + fields) + "}").utf8))
    }
    func testNineMiniFiltersInSourceOrder() { XCTAssertEqual(ProfileOrderHistoryFilter.allCases.map(\.rawValue), ["all","pendingPayment","notStarted","inProgress","completed","refunding","refunded","nonRefundable","manualRefund"]) }
    func testManualRefundHasHighestPriority() throws { XCTAssertEqual(try order(#""manualRefundCaseStatus":"REVIEW","refundApplication":{"payoutStatus":1},"registrationStatus":1"#).historyState(now: now), .manualRefund) }
    func testPayoutOneAndFourOnlyAreRefunded() throws {
        for code in [1,4] { XCTAssertEqual(try order("\"refundApplication\":{\"payoutStatus\":\(code),\"refundAmount\":0},\"registrationStatus\":3").historyState(now: now), .refunded) }
        for code in [2,3] { XCTAssertEqual(try order("\"refundApplication\":{\"payoutStatus\":\(code)},\"registrationStatus\":3").historyState(now: now), .refunding) }
    }
    func testCancellationDoesNotImplyRefund() throws { XCTAssertEqual(try order(#""registrationStatus":3"#).historyState(now: now), .cancelled) }
    func testRejectedOrZeroRefundFallsBack() throws {
        for refund in [#"{"status":2,"refundAmount":5}"#, #"{"status":0,"refundAmount":0}"#] { XCTAssertEqual(try order("\"refundApplication\":\(refund),\"registrationStatus\":1").historyState(now: now), .pendingPayment) }
    }
    func testEmptyRefundObjectIsDistinctFromAbsentAndNull() throws {
        XCTAssertEqual(try order(#""refundApplication":{}"#).historyState(now: now), .refunding)
        XCTAssertEqual(try order(#""refundApplication":null"#).historyState(now: now), .unknown)
        XCTAssertEqual(try order().historyState(now: now), .unknown)
    }
    func testQueuedAndApprovedAreRefundingNotRefunded() throws {
        for code in [0,5,6,77] { XCTAssertEqual(try order("\"refundApplication\":{\"status\":1,\"payoutStatus\":\(code),\"refundAmount\":5}").historyState(now: now), .refunding) }
    }
    func testRegistrationPrecedesVerification() throws { XCTAssertEqual(try order(#""registrationStatus":4,"verificationStatus":1"#).historyState(now: now), .expired) }
    func testVerificationCompletesRegisteredOrder() throws { XCTAssertEqual(try order(#""registrationStatus":2,"verificationStatus":1"#).historyState(now: now), .completed) }
    func testFirstScanRequiresPaidAndValidTime() throws {
        XCTAssertEqual(try order(#""registrationStatus":2,"paymentStatus":2,"firstSuccessfulScanAt":"2026-10-10 12:00:00""#).historyState(now: now), .completed)
        for field in [#""paymentStatus":1,"firstSuccessfulScanAt":"2026-10-10""#, #""paymentStatus":2,"firstSuccessfulScanAt":"invalid""#] { XCTAssertEqual(try order(#""registrationStatus":2,"# + field).historyState(now: now), .inProgress) }
    }
    func testFirstScanPrecedesNonRefundable() throws { XCTAssertEqual(try order(#""registrationStatus":2,"paymentStatus":2,"firstSuccessfulScanAt":"2026-10-10","refundInfo":{"refundable":false}"#).historyState(now: now), .completed) }
    func testOnlyExplicitAllZeroAmountsAreFree() throws {
        XCTAssertEqual(try order(#""registrationStatus":2,"totalAmount":0,"payableAmount":0,"refundInfo":{"refundable":false}"#).historyState(now: now), .inProgress)
        for extra in [#""payableAmount":0"#, #""totalAmount":0,"payableAmount":0,"pointPaymentAmount":1"#, #""totalAmount":0,"payableAmount":0,"wechatPaymentAmount":1"#] { XCTAssertEqual(try order(#""registrationStatus":2,"refundInfo":{"refundable":false},"# + extra).historyState(now: now), .nonRefundable) }
    }
    func testTotalZeroLiteralDoesNotAcceptNumericPrefix() throws {
        for value in [#""0invalid""#, #""""#, "null", #""1e-999""#] { XCTAssertFalse(try order("\"totalAmount\":\(value)").historyFacts.totalAmountIsZero) }
        for value in ["0", #"" 0.00 ""#, #""0e9""#] { XCTAssertTrue(try order("\"totalAmount\":\(value)").historyFacts.totalAmountIsZero) }
    }
    func testSourceBusinessStartEndBoundaries() throws {
        let row = try order(#""registrationStatus":2,"cmsTopic":{"startDate":"2026-10-11 12:00:00","endDate":"2026-10-11 13:00:00"}"#)
        XCTAssertEqual(row.historyState(now: now.addingTimeInterval(-1)), .notStarted)
        XCTAssertEqual(row.historyState(now: now), .inProgress)
        XCTAssertEqual(row.historyState(now: now.addingTimeInterval(3600)), .inProgress)
        XCTAssertEqual(row.historyState(now: now.addingTimeInterval(3601)), .completed)
    }
    func testOwnerFallbackAndPrecedence() throws {
        let row = try order(#""registrationStatus":2,"cmsActivity":{"startTime":"2026-10-12","endTime":"2026-10-13"},"cmsTopic":{"startDate":"2020-01-01"}"#)
        XCTAssertEqual(row.historyFacts.start,"2026-10-12"); XCTAssertEqual(row.historyState(now:now),.notStarted)
    }
    func testMissingEndFallsBackToStartAndMissingDatesStayInProgress() throws {
        XCTAssertEqual(try order(#""registrationStatus":2,"cmsTopic":{"startDate":"2026-10-10"}"#).historyState(now:now),.completed)
        XCTAssertEqual(try order(#""registrationStatus":2"#).historyState(now:now),.inProgress)
    }
    func testFilteringPreservesSourceOrderAndUnknownInAll() throws {
        let rows = try JSONDecoder().decode([ProfileOrder].self,from:Data(#"[{"id":8,"registrationStatus":1},{"id":2,"registrationStatus":99},{"id":4,"registrationStatus":1}]"#.utf8))
        XCTAssertEqual(ProfileOrderHistoryFilter.pendingPayment.orders(in:rows,now:now).map(\.id),[8,4])
        XCTAssertEqual(ProfileOrderHistoryFilter.all.orders(in:rows,now:now),rows)
        XCTAssertTrue(ProfileOrderHistoryFilter.refunded.orders(in:rows,now:now).isEmpty)
    }
    func testSelectionRejectsStaleRenderedOwner() {
        let reader = NSObject(); let a = owner(reader,1), b = owner(reader,2); var s = ProfileOrderFilterSelection()
        s.choose(.completed,rendered:a,current:a); XCTAssertEqual(s.value(for:a),.completed)
        XCTAssertEqual(s.value(for:b),.all); s.choose(.refunded,rendered:a,current:b); XCTAssertEqual(s.value(for:b),.all)
    }
    func testReaderReplacementRevocationAndRetirementResetSelection() {
        let reader = NSObject(); let a = owner(reader,1); var s = ProfileOrderFilterSelection(); s.choose(.refunding,rendered:a,current:a)
        let other = NSObject(); XCTAssertEqual(s.value(for:owner(other,1)),.all)
        let denied = ProfileOrderFilterOwner(readerID:ObjectIdentifier(reader),identity:a.identity,isConfigured:false)
        XCTAssertEqual(s.value(for:denied),.all); s.choose(.completed,rendered:denied,current:denied); XCTAssertEqual(s.value(for:denied),.all)
        s.retire(); XCTAssertEqual(s.value(for:a),.all)
    }
    private func owner(_ reader:NSObject,_ account:Int)->ProfileOrderFilterOwner { .init(readerID:ObjectIdentifier(reader),identity:.init(accountID:account,epoch:1),isConfigured:true) }
    func testSourceRowModeAndActualPaidAmount() throws {
        XCTAssertEqual(try order(#""cmsActivity":{"name":"A","productType":2}"#).sourceMode, .cityOrienteering)
        XCTAssertEqual(try order(#""cmsTopic":{"name":"T","productType":2}"#).sourceMode, .freeExplore)
        XCTAssertEqual(try order(#""cmsTopic":{"name":"T","productType":1}"#).sourceMode, .cityOrienteering)
        XCTAssertNil(try order(#""cmsTopic":{"name":"T"}"#).sourceMode)
        XCTAssertNil(try order(#""cmsTopic":{"name":"T","productType":7}"#).sourceMode)
        XCTAssertEqual(try order(#""payableAmount":30,"wechatPaymentAmount":12"#).actualPaidAmount, 12)
        XCTAssertEqual(try order(#""payableAmount":30"#).actualPaidAmount, 30)
        XCTAssertNil(try order().actualPaidAmount)
    }
}
