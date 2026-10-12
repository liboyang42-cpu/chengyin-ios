import XCTest
@testable import Questify

@MainActor final class MerchantPerkValidityCalendarTests:XCTestCase {
    private let now=ISO8601DateFormatter().date(from:"2026-10-12T15:59:00Z")!
    private func date(_ s:String)->Date{MerchantPerkValidityDraft.parse(s)!}
    private func context(_ value:String="",account:Int=41,epoch:UInt64=1,sibling:String="original")throws->MerchantPerkValidityContext {
        .init(session:try .init(accountID:account,epoch:epoch,token:"synthetic-token"),value:value,siblingFields:[sibling,"0","10","","3"])
    }
    func testMissingSessionCannotOpen(){XCTAssertNil(MerchantPerkValiditySession(current:{nil},now:now))}
    func testOpenReadsOriginalWithoutApply()throws{let c=try context("2026-10-15");let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));XCTAssertEqual(s.draft.original,c.value);XCTAssertFalse(s.draft.isDirty)}
    func testConfirmProducesOnlySelectedValueOnce()throws{
        let c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.choose(date("2026-10-15"));XCTAssertEqual(s.apply(now:now),"2026-10-15");XCTAssertNil(s.apply(now:now))
    }
    func testDirtyCancelRequiresChoice()throws{
        let c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.choose(date("2026-10-15"));XCTAssertFalse(s.requestClose());XCTAssertTrue(s.asksDiscard);XCTAssertNil(s.apply(now:now))
    }
    func testKeepEditingPreservesBufferedDate()throws{
        let c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.choose(date("2026-10-15"));_ = s.requestClose();s.keepEditing();XCTAssertEqual(s.apply(now:now),"2026-10-15")
    }
    func testDiscardRetiresWithoutChangingOriginal()throws{
        let c=try context("2026-10-14");let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.choose(date("2026-10-15"));s.cancel();XCTAssertNil(s.apply(now:now));XCTAssertEqual(c.value,"2026-10-14")
    }
    func testCleanCloseNeedsNoDiscardDialog()throws{let c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));XCTAssertTrue(s.requestClose());XCTAssertFalse(s.asksDiscard)}
    func testAccountChangeBlocksOldApply()throws{
        var c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.choose(date("2026-10-15"));c=try context(account:42);XCTAssertNil(s.apply(now:now))
    }
    func testEpochChangeBlocksOldApply()throws{
        var c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));c=try context(epoch:2);XCTAssertNil(s.apply(now:now))
    }
    func testSiblingEditBlocksOldApply()throws{
        var c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));c=try context(sibling:"changed");XCTAssertNil(s.apply(now:now))
    }
    func testReplacedDateBlocksOldApply()throws{
        var c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));c=try context("2026-10-19");XCTAssertNil(s.apply(now:now))
    }
    func testLogoutBlocksOldApply()throws{
        var c:MerchantPerkValidityContext?=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));c=nil;XCTAssertNil(s.apply(now:now))
    }
    func testDateInvalidatedByMidnightRemainsEditable()throws{
        let c=try context();let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.choose(date("2026-10-13"))
        let after=ISO8601DateFormatter().date(from:"2026-10-12T16:00:00Z")!;XCTAssertNil(s.apply(now:after));XCTAssertTrue(s.invalid);s.choose(date("2026-10-14"));XCTAssertEqual(s.apply(now:after),"2026-10-14")
    }
    func testClearReturnsEmptyAndPreservesSiblings()throws{
        let c=try context("2026-10-15");let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now));s.setEnabled(false,now:now);XCTAssertEqual(s.apply(now:now),"");XCTAssertEqual(c.siblingFields,["original","0","10","","3"])
    }
    func testCanonicallyEqualButDifferentRawSiblingBytesRejectOldApply()throws{
        var c=try context(sibling:"é");let s=try XCTUnwrap(MerchantPerkValiditySession(current:{c},now:now))
        c=try context(sibling:"e\u{301}");XCTAssertNil(s.apply(now:now))
    }

}
