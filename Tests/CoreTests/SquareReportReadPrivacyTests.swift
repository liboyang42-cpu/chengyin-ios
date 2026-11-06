import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ReportPrivacyAccess: SquareReportAccess {
    var identity: SquareGovernanceIdentity? = .init(accountID:81,epoch:1,namespace:"report-privacy-tests")
    var token: String? = "synthetic-report-token"
    func freshSubject(_ target: SocialActionTarget) async throws -> SocialActionSnapshot {
        try .init(target:target,post:SquareReportFixtures.post(),comment:nil)
    }
}
@MainActor private final class ReportPrivacyTransport: SquareReportOfflineTransport {
    let original = SquareReportFixtureTransport()
    var denial: (Data,Int)?
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data,Int) {
        requests.append(request)
        if request.url?.path.contains("community-trust/reports") == true, let denial { return denial }
        return try await original.send(request)
    }
}
@MainActor final class SquareReportReadPrivacyTests: XCTestCase {
    private func configured(_ transport: ReportPrivacyTransport) throws -> SquareReportService {
        .init(offlineConfiguration:try .init(baseURL:URL(string:"https://example.com")!),transport:transport)
    }
    private func acknowledged(_ model:SquareReportCoordinator,access:ReportPrivacyAccess) async throws -> (SquareReportReview,SquareReportReceipt) {
        let target=try SquareReportTarget(post:SquareReportFixtures.post())
        let snapshot=try await model.load(target:target,access:access)
        let review=try model.prepare(snapshot:snapshot,reasonCode:"SPAM",description:"Synthetic private report",access:access)
        return (review,try await model.confirm(review,access:access))
    }
    func testHTTPRead403IsRecognizedWithoutJSONButMutationStaysUnknown() {
        for body in [Data(),Data("<html>Forbidden</html>".utf8),Data("{\"code\":403}".utf8)] {
            XCTAssertThrowsError(try SquareReportService.decode(body,status:403,mutation:false)) {
                XCTAssertEqual($0 as? SquareReportFailure,.rejected(403))
            }
            XCTAssertThrowsError(try SquareReportService.decode(body,status:403,mutation:true)) {
                XCTAssertEqual($0 as? SquareReportFailure,.unknown)
            }
        }
    }
    func testExisting401PrecedenceAndOrdinaryErrorsRemainUnchanged() {
        XCTAssertThrowsError(try SquareReportService.decode(Data("{\"code\":401}".utf8),status:403,mutation:false)) {
            XCTAssertEqual($0 as? SquareReportFailure,.signedOut)
        }
        XCTAssertThrowsError(try SquareReportService.decode(Data(),status:401,mutation:true)) {
            XCTAssertEqual($0 as? SquareReportFailure,.signedOut)
        }
        XCTAssertThrowsError(try SquareReportService.decode(Data(),status:500,mutation:false)) {
            XCTAssertEqual($0 as? SquareReportFailure,.malformed)
        }
    }
    func testPresentationPolicyOnlyDropsPrivateServerStateOnAuthenticationOrDenial() {
        for error in [SquareReportFailure.signedOut,.rejected(401),.rejected(403)] {
            XCTAssertTrue(SquareReportReadPrivacy.hidesPrivateState(after:error))
        }
        for error in [SquareReportFailure.unknown,.locked,.malformed,.disabled,.rejected(409),.stale] {
            XCTAssertFalse(SquareReportReadPrivacy.hidesPrivateState(after:error))
        }
        XCTAssertFalse(SquareReportReadPrivacy.hidesPrivateState(after:URLError(.notConnectedToInternet)))
    }
    func testRefresh403EvictsDisplayOnlyAndKeepsCaseOriginalAndLock() async throws {
        let transport=ReportPrivacyTransport(),access=ReportPrivacyAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try configured(transport),journal:.ephemeral(),caseStore:cases)
        let (review,receipt)=try await acknowledged(model,access:access)
        transport.denial=(Data(),403)
        do {_ = try await model.refresh(receipt,target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.rejected(403))}
        XCTAssertNil(model.receipt(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertEqual(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity),receipt.id)
        XCTAssertEqual(try cases.original(target:review.snapshot.target,identity:review.snapshot.identity)?.requestID,review.requestID)
        XCTAssertTrue(model.isLocked(target:review.snapshot.target,identity:review.snapshot.identity))
        let before=transport.requests.count
        do {_ = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.rejected(403))}
        XCTAssertEqual(transport.requests.count,before+1)
        XCTAssertEqual(transport.requests.filter{$0.httpMethod == "POST"}.count,1)
    }
    func testBusiness403OnOriginalRecoveryAlsoEvictsExistingDisplay() async throws {
        let transport=ReportPrivacyTransport(),access=ReportPrivacyAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try configured(transport),journal:.ephemeral(),caseStore:cases)
        let (review,receipt)=try await acknowledged(model,access:access)
        transport.denial=(Data("{\"code\":403}".utf8),200)
        do {_ = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.rejected(403))}
        XCTAssertNil(model.receipt(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertEqual(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity),receipt.id)
        XCTAssertTrue(model.isLocked(target:review.snapshot.target,identity:review.snapshot.identity))
    }
    func testOrdinaryReadFailureDoesNotInventRevocationOrClearOriginal() async throws {
        let transport=ReportPrivacyTransport(),access=ReportPrivacyAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try configured(transport),journal:.ephemeral(),caseStore:cases)
        let (review,receipt)=try await acknowledged(model,access:access)
        transport.denial=(Data(),500)
        do {_ = try await model.refresh(receipt,target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.malformed)}
        XCTAssertEqual(model.receipt(target:review.snapshot.target,identity:review.snapshot.identity),receipt)
        XCTAssertTrue(model.isLocked(target:review.snapshot.target,identity:review.snapshot.identity))
    }
    func testSignedOutReadHidesCacheWithoutDeletingDurableIntent() async throws {
        let transport=ReportPrivacyTransport(),access=ReportPrivacyAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try configured(transport),journal:.ephemeral(),caseStore:cases)
        let (review,receipt)=try await acknowledged(model,access:access)
        transport.denial=(Data(),401)
        do {_ = try await model.refresh(receipt,target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.signedOut)}
        XCTAssertNil(model.receipt(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertNotNil(try cases.original(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertEqual(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity),receipt.id)
    }
}
