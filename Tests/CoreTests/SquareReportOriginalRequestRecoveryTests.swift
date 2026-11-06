import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class OriginalReportAccess: SquareReportAccess {
    var identity: SquareGovernanceIdentity? = .init(accountID: 81, epoch: 1, namespace: "original-report-tests")
    var token: String? = "synthetic-report-token"
    func freshSubject(_ target: SocialActionTarget) async throws -> SocialActionSnapshot {
        try .init(target: target, post: SquareReportFixtures.post(), comment: nil)
    }
}
@MainActor private final class OriginalReportTransport: SquareReportOfflineTransport {
    let original = SquareReportFixtureTransport()
    var requests: [URLRequest] = []
    var lostPost = true
    var originalRows: [SquareGovernanceJSON] = []
    var onOriginalRead: (() -> Void)?
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path.hasSuffix("/reports/mine") == true {
            onOriginalRead?()
            if status == 401 { return (Data(),401) }
            return (try JSONEncoder().encode(SquareGovernanceJSON.object([
                "code": .integer(200),"data": .array(originalRows)])),status)
        }
        let response = try await original.send(request)
        if request.httpMethod == "POST" {
            let envelope = try JSONDecoder().decode(SquareGovernanceJSON.self, from: response.0)
            originalRows = [envelope["data"]]
            if lostPost { throw URLError(.timedOut) }
        }
        return response
    }
}
@MainActor final class SquareReportOriginalRequestRecoveryTests: XCTestCase {
    private func service(_ transport: OriginalReportTransport) throws -> SquareReportService {
        .init(offlineConfiguration: try .init(baseURL: URL(string: "https://example.com/base")!), transport: transport)
    }
    private func prepared(_ model: SquareReportCoordinator, access: OriginalReportAccess) async throws -> SquareReportReview {
        let target = try SquareReportTarget(post: SquareReportFixtures.post())
        let snapshot = try await model.load(target: target, access: access)
        return try model.prepare(snapshot: snapshot, reasonCode: "SPAM", description: "Private synthetic facts", access: access)
    }
    private func lose(_ model: SquareReportCoordinator, review: SquareReportReview, access: OriginalReportAccess) async {
        do { _ = try await model.confirm(review, access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure,.unknown) }
    }
    func testLostPostReopensFromPersistedExactRequestWithoutSecondPost() async throws {
        let suite = "original-report-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let transport = OriginalReportTransport(), access = OriginalReportAccess()
        let model = SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:.init(defaults:defaults))
        let review = try await prepared(model,access:access)
        await lose(model,review:review,access:access)
        // New storage/coordinator and new login epoch, same authenticated account/deployment.
        access.identity = .init(accountID:81,epoch:2,namespace:"original-report-tests")
        let identity = try XCTUnwrap(access.identity)
        let cases = SquareReportCaseStore(defaults:defaults)
        let reopened = SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
        XCTAssertTrue(reopened.isLocked(target:review.snapshot.target,identity:identity))
        let result = try await reopened.recover(target:review.snapshot.target,expectedIdentity:identity,access:access)
        XCTAssertEqual(result?.id,9901)
        XCTAssertEqual(try cases.reference(target:review.snapshot.target,identity:identity),9901)
        let get = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(get.httpMethod,"GET")
        XCTAssertEqual(get.url?.path,"/base/api/community-trust/reports/mine")
        XCTAssertEqual(URLComponents(url:try XCTUnwrap(get.url),resolvingAgainstBaseURL:false)?.queryItems,
                       [URLQueryItem(name:"requestId",value:review.requestID)])
        XCTAssertEqual(transport.requests.filter{$0.httpMethod == "POST"}.count,1)
        XCTAssertTrue(reopened.isLocked(target:review.snapshot.target,identity:identity))
        for value in defaults.dictionaryRepresentation().values {
            if let data = value as? Data { XCTAssertFalse(String(decoding:data,as:UTF8.self).contains(review.description)) }
        }
    }
    func testEmptyOriginalReadDoesNotReleaseLockOrCreateNewRequest() async throws {
        let transport = OriginalReportTransport(), access = OriginalReportAccess(), cases = SquareReportCaseStore.ephemeral()
        let model = SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
        let review = try await prepared(model,access:access);await lose(model,review:review,access:access)
        transport.originalRows=[]
        let result = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access)
        XCTAssertNil(result);XCTAssertTrue(model.isLocked(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertNil(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertEqual(transport.requests.filter{$0.httpMethod == "POST"}.count,1)
    }
    func testMismatchedTextDuplicateRowsMissingVersionAndAttachmentsStayUnknown() async throws {
        for field in ["description","reasonCode","policyVersion","targetId","evidenceAssetIds","version","duplicates"] {
            let transport=OriginalReportTransport(),access=OriginalReportAccess(),cases=SquareReportCaseStore.ephemeral()
            let model=SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
            let review=try await prepared(model,access:access);await lose(model,review:review,access:access)
            guard case .object(var row)=try XCTUnwrap(transport.originalRows.first) else { return XCTFail() }
            switch field {
            case "targetId":row[field] = .integer(999)
            case "evidenceAssetIds":row[field] = .array([.integer(1)])
            case "version":row.removeValue(forKey:field)
            case "duplicates":break
            default:row[field] = .string("different")
            }
            transport.originalRows = field == "duplicates" ? [.object(row),.object(row)] : [.object(row)]
            do {_ = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail(field)}
            catch {XCTAssertEqual(error as? SquareReportFailure,.unknown,field)}
            XCTAssertNil(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity))
            XCTAssertTrue(model.isLocked(target:review.snapshot.target,identity:review.snapshot.identity))
        }
    }
    func testLegacyUnknownLockNeverInventsOriginalIDOrRequests() async throws {
        let transport=OriginalReportTransport(),access=OriginalReportAccess(),journal=SquareGovernanceJournal.ephemeral()
        let target=try SquareReportTarget(post:SquareReportFixtures.post()),identity=try XCTUnwrap(access.identity)
        XCTAssertTrue(journal.claim(target.lockKey,identity:identity))
        let model=SquareReportCoordinator(service:try service(transport),journal:journal,caseStore:.ephemeral())
        let result=try await model.recover(target:target,expectedIdentity:identity,access:access)
        XCTAssertNil(result);XCTAssertTrue(model.isLocked(target:target,identity:identity));XCTAssertTrue(transport.requests.isEmpty)
    }
    func testAccountChangeDuringOriginalReadCannotPublishOrSaveForeignResult() async throws {
        let transport=OriginalReportTransport(),access=OriginalReportAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
        let review=try await prepared(model,access:access);await lose(model,review:review,access:access)
        transport.onOriginalRead={access.identity = .init(accountID:82,epoch:2,namespace:"original-report-tests")}
        do {_ = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.signedOut)}
        XCTAssertNil(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertNil(model.receipt(target:review.snapshot.target,identity:review.snapshot.identity))
    }
    func test401PreservesOriginalIntentForLaterSameAccountRead() async throws {
        let transport=OriginalReportTransport(),access=OriginalReportAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
        let review=try await prepared(model,access:access);await lose(model,review:review,access:access)
        transport.status=401
        do {_ = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.signedOut)}
        XCTAssertEqual(try cases.original(target:review.snapshot.target,identity:review.snapshot.identity)?.requestID,review.requestID)
        transport.status=200
        let recovered=try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access)
        XCTAssertEqual(recovered?.id,9901);XCTAssertEqual(transport.requests.filter{$0.httpMethod == "POST"}.count,1)
    }
    func testKnownCaseIdentityMismatchCannotReplaceAcknowledgment() async throws {
        let transport=OriginalReportTransport(),access=OriginalReportAccess(),cases=SquareReportCaseStore.ephemeral()
        let model=SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
        let review=try await prepared(model,access:access);await lose(model,review:review,access:access)
        cases.record(9902,target:review.snapshot.target,identity:review.snapshot.identity)
        do {_ = try await model.recover(target:review.snapshot.target,expectedIdentity:review.snapshot.identity,access:access);XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.unknown)}
        XCTAssertEqual(try cases.reference(target:review.snapshot.target,identity:review.snapshot.identity),9902)
    }
    func testOriginalReadStillRequiresExistingReadEnablement() async throws {
        let transport=OriginalReportTransport(),access=OriginalReportAccess()
        let model=SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:.ephemeral())
        let review=try await prepared(model,access:access),intent=try SquareReportOriginalIntent(review)
        let disabled=SquareReportService(configuration:try .init(baseURL:URL(string:"https://example.com")!),transport:transport)
        let before=transport.requests.count
        do {_ = try await disabled.original(intent,token:"synthetic-report-token",check:{});XCTFail()}
        catch {XCTAssertEqual(error as? SquareReportFailure,.disabled)}
        XCTAssertEqual(transport.requests.count,before)
    }
    func testCorruptOriginalCannotReopenDispatchAndReserveCannotReplaceIt() async throws {
        let suite="corrupt-report-"+UUID().uuidString
        let isolated=try XCTUnwrap(UserDefaults(suiteName:suite));defer{isolated.removePersistentDomain(forName:suite)}
        let cases=SquareReportCaseStore(defaults:isolated),transport=OriginalReportTransport(),access=OriginalReportAccess()
        let model=SquareReportCoordinator(service:try service(transport),journal:.ephemeral(),caseStore:cases)
        let review=try await prepared(model,access:access);try cases.reserveOriginal(review)
        let key=try XCTUnwrap(isolated.dictionaryRepresentation().keys.first{$0.hasSuffix(".original-v1")})
        isolated.set(Data("invalid".utf8),forKey:key)
        XCTAssertTrue(model.isLocked(target:review.snapshot.target,identity:review.snapshot.identity))
        XCTAssertThrowsError(try cases.reserveOriginal(review))
        do {_ = try await model.confirm(review,access:access);XCTFail()}
        catch{XCTAssertEqual(error as? SquareReportFailure,.locked)}
        XCTAssertTrue(transport.requests.allSatisfy{$0.httpMethod == "GET"})
    }
}
