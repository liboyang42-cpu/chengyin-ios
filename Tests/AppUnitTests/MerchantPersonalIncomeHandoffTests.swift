import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantPersonalIncomeHandoffTests:XCTestCase {
    private func setup()throws->(IncomeMerchantFake,MerchantPersonalIncomeSource){let r=try IncomeMerchantFake();return(r,try XCTUnwrap(MerchantPersonalIncomeSource(row:r.value.document.rows[0],reader:r,currentSnapshot:{r.value})))}
    private func wallet(account:Int=99,configured:Bool=true,onUnauthorized: @escaping (WalletCommerceScope) -> Void = { _ in })throws->WalletCommerceReader {
        let scope=WalletCommerceScope(namespace:"synthetic",accountID:account,epoch:UUID())
        let service:WalletCommerceService?=configured ? try .init(configuration:.init(baseURL:URL(string:"https://example.com")!),transport:IncomeNoTransport()):nil
        return .init(service:service,onUnauthorized:onUnauthorized,session:{(scope,"synthetic-token")})
    }
    private func ledger() throws -> (IncomeMerchantFake, MerchantLedgerAssetsSource) {
        let reader = try IncomeMerchantFake(ledger: true)
        return (reader, try XCTUnwrap(MerchantLedgerAssetsSource(reader: reader, currentSnapshot: { reader.value })))
    }
    func testSharedGateCannotReuseApprovalForAnotherOriginOnSameAccount() async throws {
        let (_, first) = try ledger(), (_, second) = try ledger(), original = try wallet(), gate = MerchantPersonalIncomeGate()
        await gate.open(source: first, currentWallet: { original })
        XCTAssertTrue(gate.permits(source: first, wallet: original)); XCTAssertFalse(gate.permits(source: second, wallet: original))
    }
    func testLedgerSourceRequiresOverviewAndRevalidatesBeforePersonalReads() async throws {
        let ordinary = try IncomeMerchantFake()
        XCTAssertNil(MerchantLedgerAssetsSource(reader: ordinary, currentSnapshot: { ordinary.value }))
        let (reader, source) = try ledger(), original = try wallet(), owner = MerchantLedgerAssetsReadOwner()
        await owner.open(source: source, currentWallet: { original }, isCurrent: { true })
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(owner.wallet?.scope?.accountID, 99)
        XCTAssertFalse(owner.wallet === original)
    }
    func testLedgerNeverAdoptsMerchantOwnerOrAnotherWalletPrincipal() async throws {
        let (reader, source) = try ledger(), other = try wallet(account: 100), owner = MerchantLedgerAssetsReadOwner()
        await owner.open(source: source, currentWallet: { other }, isCurrent: { true })
        XCTAssertNil(owner.wallet); XCTAssertEqual(reader.reads, 0); XCTAssertTrue(owner.failed)
        let absent = try wallet(configured: false)
        await owner.open(source: source, currentWallet: { absent }, isCurrent: { true })
        XCTAssertNil(owner.wallet); XCTAssertEqual(reader.reads, 0)
    }
    func testLedgerSourceAuthorityReplacementAndDismissalRetireReader() async throws {
        let (reader, source) = try ledger(), original = try wallet(), owner = MerchantLedgerAssetsReadOwner()
        await owner.open(source: source, currentWallet: { original }, isCurrent: { true })
        let old = try XCTUnwrap(owner.wallet)
        reader.authorizationGeneration = UUID(); XCTAssertNil(old.scope)
        let (_, replacement) = try ledger()
        await owner.open(source: replacement, currentWallet: { original }, isCurrent: { true })
        XCTAssertNil(old.scope); XCTAssertNotNil(owner.wallet?.scope)
        replacement.retire(); XCTAssertNil(owner.wallet?.scope)
    }
    func testLedgerDismissedBindingCannotRetireReopenedSource() throws {
        var selected: MerchantLedgerAssetsSource?
        let old = merchantLedgerAssetsPresentation(.init(get: { selected }, set: { selected = $0 }))
        let (_, first) = try ledger(); selected = first; XCTAssertTrue(old.wrappedValue === first)
        old.wrappedValue = nil; XCTAssertFalse(first.active); XCTAssertNil(selected)
        let (_, second) = try ledger(); selected = second
        old.wrappedValue = nil; XCTAssertTrue(second.active); XCTAssertTrue(selected === second)
    }
    func testRetiredLedgerWalletRejectsQueuedReadsAndSuppressesLate401() async throws {
        let (_, source) = try ledger(); var expired = 0
        let original = try wallet(onUnauthorized: { _ in expired += 1 }), owner = MerchantLedgerAssetsReadOwner()
        await owner.open(source: source, currentWallet: { original }, isCurrent: { true })
        let protected = try XCTUnwrap(owner.wallet), started = expectation(description: "wallet read pending")
        var completion: CheckedContinuation<Int, Error>?
        let task = Task { try await protected.read { _, _ in
            try await withCheckedThrowingContinuation { completion = $0; started.fulfill() }
        } }
        await fulfillment(of: [started], timeout: 2)
        source.retire(); completion?.resume(throwing: APIError.unauthorized)
        do { _ = try await task.value; XCTFail() } catch { }
        XCTAssertEqual(expired, 0)
        do { let _: Int = try await protected.read { _, _ in XCTFail("retired read dispatched"); return 0 }; XCTFail() } catch { }
    }
    func testCurrentLedgerWallet401StillReachesMatchingSessionHandler() async throws {
        let (_, source) = try ledger(); var expired = 0
        let original = try wallet(onUnauthorized: { _ in expired += 1 }), owner = MerchantLedgerAssetsReadOwner()
        await owner.open(source: source, currentWallet: { original }, isCurrent: { true })
        let protected = try XCTUnwrap(owner.wallet)
        do { let _: Int = try await protected.read { _, _ in throw APIError.unauthorized }; XCTFail() } catch { }
        XCTAssertEqual(expired, 1)
    }
    func testExternalOwnerInvalidationDuringSourceReadSuppressesLate401() async throws {
        let wire = LedgerReadWire(), configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://ledger.example")))
        let captured = try MerchantBusinessSession(accountID: 99, epoch: 1, token: "synthetic-token"); var expired = 0
        let reader = MerchantBusinessSessionReader(service: .init(configuration: configuration, readTransport: wire),
            currentSession: { captured }, onUnauthorized: { _ in expired += 1 })
        let baseline = try await reader.snapshot(.overview), source = try XCTUnwrap(MerchantLedgerAssetsSource(reader: reader, currentSnapshot: { baseline }))
        let original = try wallet(), owner = MerchantLedgerAssetsReadOwner(); var current = true
        let started = expectation(description: "owner source pending"); wire.hold = true; wire.onHeld = { started.fulfill() }
        let task = Task { await owner.open(source: source, currentWallet: { original }, isCurrent: { current }) }
        await fulfillment(of: [started], timeout: 2)
        current = false; wire.finish401(); await task.value
        XCTAssertTrue(source.current); XCTAssertEqual(expired, 0); XCTAssertNil(owner.wallet)
    }
    func testConcreteSourcePresentationFenceSuppressesAccess401AndSecondRead() async throws {
        let wire = LedgerReadWire(), configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://ledger.example")))
        let captured = try MerchantBusinessSession(accountID: 99, epoch: 1, token: "synthetic-token"); var expired = 0
        let reader = MerchantBusinessSessionReader(service: .init(configuration: configuration, readTransport: wire),
            currentSession: { captured }, onUnauthorized: { _ in expired += 1 })
        let baseline = try await reader.snapshot(.overview), source = try XCTUnwrap(MerchantLedgerAssetsSource(reader: reader, currentSnapshot: { baseline }))
        wire.requests = []; let started = expectation(description: "source access pending")
        wire.hold = true; wire.onHeld = { started.fulfill() }
        let task = Task { try await source.revalidate(isCurrent: { true }) }
        await fulfillment(of: [started], timeout: 2)
        source.retire(); wire.finish401()
        do { try await task.value; XCTFail() } catch { }
        XCTAssertEqual(expired, 0); XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["me"])
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
    init(ledger: Bool = false)throws{let a=try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object);let q: MerchantBusinessQuery = ledger ? .overview : .redemption(recordID:"64001");value=try .init(access:.init(a),document:.init(query:q,payload:MerchantBusinessSyntheticFixtures.payload(q)))}
    func access()async throws->MerchantBusinessAccess{value.access}
    func snapshot(_ query:MerchantBusinessQuery)async throws->MerchantBusinessSnapshot{reads += 1;XCTAssertEqual(query,value.document.query);afterRead?();return value}
    func execute(_ mutation:MerchantBusinessMutation,requestID:String,scope:MerchantBusinessScope)async throws->MerchantBusinessReceipt{XCTFail("no writes");throw MerchantBusinessFailure.disabled}
}

@MainActor private final class LedgerReadWire: HTTPTransport {
    var requests: [URLRequest] = []
    var hold = false
    var onHeld: (() -> Void)?
    var pending: CheckedContinuation<(Data, Int), Error>?
    func finish401() { let old = pending; pending = nil; old?.resume(returning: (Data(), 401)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if hold { hold = false; return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
        let payload: MerchantBusinessValue
        if request.url?.lastPathComponent == "me" { payload = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access) }
        else { payload = try MerchantBusinessSyntheticFixtures.payload(.overview) }
        return (try JSONEncoder().encode(MerchantBusinessValue.object(["code": .number(200), "data": payload])), 200)
    }
}
