import XCTest
@testable import QuestifyCore

final class MerchantPerkValidityDraftTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-12T15:59:00Z")!
    private func date(_ value:String) -> Date { MerchantPerkValidityDraft.parse(value)! }
    func testChinaTomorrowDoesNotUseDeviceCalendar() { XCTAssertEqual(MerchantPerkValidityDraft.wire(MerchantPerkValidityDraft.minimum(now:now)),"2026-10-13") }
    func testMidnightAdvancesMinimum() {
        let after=ISO8601DateFormatter().date(from:"2026-10-12T16:00:00Z")!
        XCTAssertEqual(MerchantPerkValidityDraft.wire(MerchantPerkValidityDraft.minimum(now:after)),"2026-10-14")
    }
    func testStrictSourceDateParsing() {
        for s in ["2026-02-30","2026-1-1"," 2026-10-13","2026-10-13T00:00:00","2026-10-13\n"] { XCTAssertNil(MerchantPerkValidityDraft.parse(s)) }
        XCTAssertNotNil(MerchantPerkValidityDraft.parse("2028-02-29"))
    }
    func testEmptyNoExpiryStaysExactWithoutEditing() throws { let d=MerchantPerkValidityDraft(value:"",now:now);XCTAssertFalse(d.enabled);XCTAssertEqual(try d.value(now:now),"") }
    func testChooseTomorrowProducesSourceWire() throws { var d=MerchantPerkValidityDraft(value:"",now:now);d.choose(date("2026-10-13"));XCTAssertEqual(try d.value(now:now),"2026-10-13") }
    func testChoosingTodayOrPastFailsApply() { for day in ["2026-10-11","2026-10-12"] { var d=MerchantPerkValidityDraft(value:"",now:now);d.choose(date(day));XCTAssertThrowsError(try d.value(now:now)) } }
    func testExplicitClearProducesEmptyWithoutChangingOriginal() throws { var d=MerchantPerkValidityDraft(value:"2026-10-15",now:now);d.setEnabled(false,now:now);XCTAssertEqual(try d.value(now:now),"");XCTAssertEqual(d.original,"2026-10-15") }
    func testUntouchedHistoricalTextIsNotRepaired() throws { for raw in ["历史格式","2020-01-01"] { let d=MerchantPerkValidityDraft(value:raw,now:now);XCTAssertEqual(try d.value(now:now),raw);XCTAssertTrue(d.preservesExistingValue(now:now)) } }
    func testMidnightRolloverRecheckedAtApply() {
        var d=MerchantPerkValidityDraft(value:"",now:now);d.choose(date("2026-10-13"))
        XCTAssertThrowsError(try d.value(now:ISO8601DateFormatter().date(from:"2026-10-12T16:00:00Z")!))
    }
    func testEnablingUsesTomorrowNotToday() throws { var d=MerchantPerkValidityDraft(value:"",now:now);d.setEnabled(true,now:now);XCTAssertEqual(try d.value(now:now),"2026-10-13") }
    func testRevertingToOriginalIsNotDirty() { var d=MerchantPerkValidityDraft(value:"2026-10-15",now:now);d.choose(date("2026-10-16"));XCTAssertTrue(d.isDirty);d.choose(date("2026-10-15"));XCTAssertFalse(d.isDirty) }
    func testExistingTemplateRequestReceivesUnchangedWireContract() throws {
        var d=MerchantPerkValidityDraft(value:"",now:now);d.choose(date("2026-10-13"))
        let template=try CoopFlowPerkTemplate(name:"Synthetic perk",type:0,retailValue:10,unitCost:nil,quota:3,validEnd:d.value(now:now))
        XCTAssertEqual(template.validEnd,"2026-10-13")
        d.setEnabled(false,now:now);let cleared=try d.value(now:now)
        let noDate=try CoopFlowPerkTemplate(name:"Synthetic perk",type:0,retailValue:10,unitCost:nil,quota:3,validEnd:cleared.isEmpty ? nil : cleared)
        XCTAssertNil(noDate.validEnd)
    }
}
