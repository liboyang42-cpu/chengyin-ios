import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantPersonalIncomeHandoffTests:XCTestCase {
    private func setup()throws->(IncomeMerchantFake,MerchantPersonalIncomeSource){let r=try IncomeMerchantFake();return(r,try XCTUnwrap(MerchantPersonalIncomeSource(row:r.value.document.rows[0],reader:r,currentSnapshot:{r.value})))}
    private func wallet(account:Int=99,configured:Bool=true)throws->WalletCommerceReader {
        let scope=WalletCommerceScope(namespace:"synthetic",accountID:account,epoch:UUID())
        let service:WalletCommerceService?=configured ? try .init(configuration:.init(baseURL:URL(string:"https://example.com")!),transport:IncomeNoTransport()):nil
        return .init(service:service,session:{(scope,"synthetic-token")})
    }
    func testBindingCreatedBeforeFirstSelectionAdoptsAndDismissesIt() throws {
        var source: MerchantPersonalIncomeSource?
        let binding = merchantPersonalIncomePresentation(.init(get: { source }, set: { source = $0 }))
        XCTAssertNil(binding.wrappedValue)
        let (_, first) = try setup(); source = first
        XCTAssertTrue(binding.wrappedValue === first)
        binding.wrappedValue = nil
        XCTAssertNil(source)
    }
    func testOldBindingCannotAdoptOrDismissReopenedSource() throws {
        var source: MerchantPersonalIncomeSource?
        let old = merchantPersonalIncomePresentation(.init(get: { source }, set: { source = $0 }))
        let (_, first) = try setup(); source = first
        XCTAssertTrue(old.wrappedValue === first)
        old.wrappedValue = nil
        let (_, second) = try setup(); source = second
        XCTAssertNil(old.wrappedValue)
        old.wrappedValue = nil
        XCTAssertTrue(source === second)
        let fresh = merchantPersonalIncomePresentation(.init(get: { source }, set: { source = $0 }))
        XCTAssertTrue(fresh.wrappedValue === second)
        fresh.wrappedValue = nil
        XCTAssertNil(source)
    }
    func testUnobservedOldDismissalCannotClearFirstSelection() throws {
        var source: MerchantPersonalIncomeSource?
        let old = merchantPersonalIncomePresentation(.init(get: { source }, set: { source = $0 }))
        let (_, first) = try setup(); source = first
        old.wrappedValue = nil
        XCTAssertTrue(source === first)
    }
    func testFreshOwnedReadPrecedesHandoffWithoutWalletRequest()async throws{let(r,s)=try setup();let w=try wallet(),g=MerchantPersonalIncomeGate();await g.open(source:s,currentWallet:{w});XCTAssertEqual(r.reads,1);XCTAssertTrue(g.permits(source:s,wallet:w))}
    func testMissingWalletApprovalNeverProbesMerchant()async throws{let(r,s)=try setup();let w=try wallet(configured:false),g=MerchantPersonalIncomeGate();await g.open(source:s,currentWallet:{w});XCTAssertEqual(r.reads,0);XCTAssertFalse(g.approved)}
    func testDifferentWalletAccountRejected()async throws{let(r,s)=try setup();let w=try wallet(account:100),g=MerchantPersonalIncomeGate();await g.open(source:s,currentWallet:{w});XCTAssertEqual(r.reads,0);XCTAssertFalse(g.approved)}
    func testRevocationDuringFreshReadRejects()async throws{let(r,s)=try setup();let w=try wallet(),g=MerchantPersonalIncomeGate();r.afterRead={r.authorizationGeneration=UUID()};await g.open(source:s,currentWallet:{w});XCTAssertFalse(g.approved)}
    func testCancelDuringReadRejectsLateApproval()async throws{let(r,s)=try setup();let w=try wallet(),g=MerchantPersonalIncomeGate();r.afterRead={g.cancel()};await g.open(source:s,currentWallet:{w});XCTAssertFalse(g.approved)}
    func testWalletReplacementDuringReadRejects()async throws{let(r,s)=try setup();let old=try wallet(),new=try wallet(),g=MerchantPersonalIncomeGate();var current=old;r.afterRead={current=new};await g.open(source:s,currentWallet:{current});XCTAssertFalse(g.approved)}
}
private final class IncomeNoTransport:HTTPTransport {
    func send(_ request:URLRequest)async throws->(Data,Int){XCTFail("handoff must not issue a wallet transport request");throw APIError.invalidRequest}
}
@MainActor private final class IncomeMerchantFake:MerchantBusinessReading {
    var scope:MerchantBusinessScope? = .init(realm:"synthetic",accountID:99,epoch:1)
    var isConfigured=true,isOfflineExample=true,canExecuteSyntheticMutation=false
    var authorizationGeneration:UUID?=UUID()
    var value:MerchantBusinessSnapshot
    var reads=0
    var afterRead:(()->Void)?
    init()throws{let a=try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object);let q=MerchantBusinessQuery.redemption(recordID:"64001");value=try .init(access:.init(a),document:.init(query:q,payload:MerchantBusinessSyntheticFixtures.payload(q)))}
    func access()async throws->MerchantBusinessAccess{value.access}
    func snapshot(_ query:MerchantBusinessQuery)async throws->MerchantBusinessSnapshot{reads += 1;XCTAssertEqual(query,value.document.query);afterRead?();return value}
    func execute(_ mutation:MerchantBusinessMutation,requestID:String,scope:MerchantBusinessScope)async throws->MerchantBusinessReceipt{XCTFail("no writes");throw MerchantBusinessFailure.disabled}
}
