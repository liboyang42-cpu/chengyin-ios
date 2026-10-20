import XCTest
@testable import QuestifyCore

/// Source mycanyu/mycanyuinfo status, filters, cancel visibility and copy keys. Synthetic rows only.
final class ParticipationParityTests: XCTestCase {
    private struct OfflineFailure: Error {}
    private let paid = #"{"id":71,"ownerType":1,"ownerId":91,"registrationStatus":2,"paymentStatus":2,"verificationStatus":0,"totalAmount":10,"payableAmount":10,"cmsTopic":{"id":91,"name":"Synthetic route","startDate":"2099-01-01 10:00:00","endDate":"2099-01-02 10:00:00"},"refundInfo":{"refundable":true}}"#
    private let early = Date(timeIntervalSince1970: 0)
    private func record(_ json: String) throws -> ParticipationRecord { try JSONDecoder().decode(ParticipationRecord.self, from: Data(json.utf8)) }
    private func detail(_ json: String) throws -> ParticipationDetail { try JSONDecoder().decode(ParticipationDetail.self, from: Data(json.utf8)) }

    func testActivityCancelTimeOutranksRegistrationStateButNotRefundProgress() throws {
        let activity = #"{"id":5,"ownerType":2,"registrationStatus":1,"cmsActivity":{"id":8,"name":"A","cancelTime":"2026-10-01 10:00:00"}}"#
        let status = try record(activity).participationStatus(now: early)
        XCTAssertEqual(status.state, .cancelled); XCTAssertTrue(status.activityCancelled)
        XCTAssertEqual(status.labelKey, "playerJourney.parity.state.activityCancelled")
        let refunding = activity.replacingOccurrences(of: #""registrationStatus":1"#, with: #""registrationStatus":2,"refundApplication":{"payoutStatus":1}"#)
        XCTAssertEqual(try record(refunding).participationStatus(now: early).state, .refunded)
        let blank = activity.replacingOccurrences(of: "2026-10-01 10:00:00", with: "")
        XCTAssertEqual(try record(blank).participationStatus(now: early).state, .pendingPayment)
    }

    func testPaidFirstScanCompletesBeforeStart() throws {
        let scanned = String(paid.dropLast()) + #","firstSuccessfulScanAt":"2026-10-01 10:00:00"}"#
        XCTAssertEqual(try record(scanned).participationStatus(now: early).state, .completed)
        XCTAssertEqual(try record(paid).participationStatus(now: early).state, .notStarted)
        let unpaidScan = scanned.replacingOccurrences(of: #""paymentStatus":2"#, with: #""paymentStatus":1"#)
        XCTAssertEqual(try record(unpaidScan).participationStatus(now: early).state, .notStarted)
    }

    func testFreeOrdersSkipNonRefundableButPaidOrdersDoNot() throws {
        let locked = paid.replacingOccurrences(of: #""refundable":true"#, with: #""refundable":false"#)
        XCTAssertEqual(try record(locked).participationStatus(now: early).state, .nonRefundable)
        let free = locked.replacingOccurrences(of: #""totalAmount":10,"payableAmount":10"#, with: #""totalAmount":"0.00","payableAmount":0"#)
        XCTAssertTrue(try record(free).parity.isFree)
        XCTAssertEqual(try record(free).participationStatus(now: early).state, .notStarted)
        let pointsPaid = String(free.dropLast()) + #","pointPaymentAmount":3}"#
        XCTAssertFalse(try record(pointsPaid).parity.isFree)
        let missingTotal = free.replacingOccurrences(of: #""totalAmount":0,"#, with: "")
        XCTAssertFalse(try record(missingTotal).parity.isFree)
    }

    func testFilterTabsUseParticipationStatusAndDistinctEmptyCopy() throws {
        let scanned = try record(String(paid.dropLast()) + #","firstSuccessfulScanAt":"2026-10-01 10:00:00"}"#)
        XCTAssertTrue(ParticipationFilter.completed.matches(scanned, now: early))
        XCTAssertFalse(ParticipationFilter.notStarted.matches(scanned, now: early))
        XCTAssertTrue(ParticipationFilter.all.matches(scanned, now: early))
        XCTAssertEqual(ParticipationFilter.all.emptyTitleKey, "playerJourney.empty")
        XCTAssertEqual(ParticipationFilter.all.emptyDetailKey, "playerJourney.parity.emptyDetail")
        for filter in [ParticipationFilter.notStarted, .inProgress, .completed] {
            XCTAssertEqual(filter.emptyTitleKey, "playerJourney.parity.filteredEmpty")
            XCTAssertEqual(filter.emptyDetailKey, "playerJourney.parity.filteredEmptyDetail")
        }
    }

    func testSourceCancelVisibilityRequiresPendingOrRefundEligibility() throws {
        XCTAssertTrue(try detail(paid).sourceCanCancel(now: early))
        let verified = paid.replacingOccurrences(of: #""verificationStatus":0"#, with: #""verificationStatus":1"#)
        XCTAssertFalse(try detail(verified).sourceCanCancel(now: early)); XCTAssertTrue(try detail(verified).showsContactService(now: early))
        let unknownPolicy = paid.replacingOccurrences(of: #","refundInfo":{"refundable":true}"#, with: "")
        XCTAssertFalse(try detail(unknownPolicy).sourceCanCancel(now: early))
        let applied = String(paid.dropLast()) + #","refundApplication":{"status":0,"refundAmount":10}}"#
        XCTAssertFalse(try detail(applied).sourceCanCancel(now: early))
        let pending = paid.replacingOccurrences(of: #""registrationStatus":2,"paymentStatus":2"#, with: #""registrationStatus":1,"paymentStatus":1"#)
        XCTAssertTrue(try detail(pending).sourceCanCancel(now: early))
        let modify = String(paid.dropLast()) + #","displayStatus":"需修改"}"#
        XCTAssertFalse(try detail(modify).sourceCanCancel(now: early)); XCTAssertFalse(try detail(modify).showsContactService(now: early))
    }

    func testStatisticsShowZeroForUnknownAndTwoSourceCells() throws {
        let unknown = try detail(String(paid.dropLast()) + #","status":1,"totalOrderNum":2,"verifiedNum":3}"#)
        XCTAssertEqual([unknown.pendingText, unknown.verifiedText, unknown.totalText], ["0", "0", "0"])
        let known = try detail(String(paid.dropLast()) + #","status":1,"totalOrderNum":5,"verifiedNum":2}"#)
        XCTAssertEqual([known.pendingText, known.verifiedText, known.totalText], ["3", "2", "5"])
    }

    func testLoadIssueKeepsServerTextAndUsesSourceFallbacks() {
        let rejected = ParticipationLoadIssue(PlayerJourneyFailure(code: 500, message: "服务端原文"), detail: false)
        XCTAssertEqual(rejected.titleKey, "playerJourney.parity.listFailed"); XCTAssertEqual(rejected.serverMessage, "服务端原文")
        XCTAssertEqual(ParticipationLoadIssue(APIError.httpStatus(503), detail: false).fallbackKey, "playerJourney.parity.list.unavailable")
        XCTAssertEqual(ParticipationLoadIssue(OfflineFailure(), detail: false).fallbackKey, "playerJourney.parity.network")
        let malformed = ParticipationLoadIssue(APIError.malformedResponse, detail: true)
        XCTAssertEqual(malformed.titleKey, "playerJourney.parity.detailFailed"); XCTAssertEqual(malformed.fallbackKey, "playerJourney.parity.detail.malformed")
        XCTAssertEqual(ParticipationLoadIssue(APIError.unauthorized, detail: true).kind, .signIn)
        XCTAssertEqual(ParticipationLoadIssue(APIError.notConfigured, detail: false).titleKey, "playerJourney.notConfigured")
    }

    func testModeKeyMatchesSourceModeText() throws {
        XCTAssertEqual(try record(paid).modeKey, "playerJourney.route")
        let free = paid.replacingOccurrences(of: #""name":"Synthetic route""#, with: #""name":"Synthetic route","productType":2"#)
        XCTAssertEqual(try record(free).modeKey, "playerJourney.freeExplore")
        XCTAssertEqual(try record(#"{"id":5,"ownerType":2,"cmsActivity":{"id":8}}"#).modeKey, "playerJourney.activity")
    }
}
