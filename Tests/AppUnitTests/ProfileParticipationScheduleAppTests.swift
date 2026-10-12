import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileParticipationScheduleAppTests: XCTestCase {
    private func detail(start:String="2026-10-13 09:00:00",end:String="2026-10-13 18:00:00") throws -> ParticipationDetail {
        let object:[String:Any]=["id":11,"ownerType":1,"ownerId":77,"registrationStatus":2,"paymentStatus":2,"cmsTopic":["id":77,"name":"Synthetic topic","startDate":start,"endDate":end],"cooperateDate":"Every afternoon","refundDeadlineDisplay":"Server refund policy"]
        return try JSONDecoder().decode(ParticipationDetail.self,from:JSONSerialization.data(withJSONObject:object))
    }
    func testDetailProjectionUsesOwnerScheduleNotReceptionOrRefundText() throws {let d=try detail();let p=ProfileParticipationSchedule(start:d.record.order.ownerStartDate,end:d.record.order.ownerEndDate).presentation(now:try XCTUnwrap(OrderLifecycleTime.date("2026-10-11 00:01:00")));XCTAssertEqual(p.reminderDays,2);XCTAssertEqual(p.range,"2026.10.13 - 2026.10.13")}
    func testPurePresentationCannotMutateParticipationDetail() throws {let d=try detail(),before=d;_ = ProfileParticipationSchedule(start:d.record.order.ownerStartDate,end:d.record.order.ownerEndDate).presentation();XCTAssertEqual(d,before)}
    func testMissingBackendDatesStayAbsent() throws {let d=try detail(start:"",end:"");XCTAssertNil(ProfileParticipationSchedule(start:d.record.order.ownerStartDate,end:d.record.order.ownerEndDate).presentation().range)}
    func testFixedFixtureContentBuildsWithoutReadersOrServices() {let host=UIHostingController(rootView:ProfileParticipationScheduleFixtureHost());host.loadViewIfNeeded();XCTAssertNotNil(host.view)}
    func testClockTransitionRecomputesWithoutReloadingSource() throws {let d=try detail(),s=ProfileParticipationSchedule(start:d.record.order.ownerStartDate,end:d.record.order.ownerEndDate);XCTAssertEqual(s.presentation(now:try XCTUnwrap(OrderLifecycleTime.date("2026-10-10"))).reminderDays,3);XCTAssertNil(s.presentation(now:try XCTUnwrap(OrderLifecycleTime.date("2026-10-13 09:00:00"))).reminderDays)}
    func testLocalViewCanRenderWithoutProductionApproval() {let host=UIHostingController(rootView:List{ProfileParticipationScheduleSection(start:"2026-10-13",end:"2026-10-14")});host.loadViewIfNeeded();XCTAssertNotNil(host.view)}
}
