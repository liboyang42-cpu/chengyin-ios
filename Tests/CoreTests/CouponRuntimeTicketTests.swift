import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class CouponRuntimeTicketTests: XCTestCase {
    final class Authority: CouponPublisherAuthorizing {
        func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission { .init(revision: "merchant-21-owner-permission", mayPublish: true, merchantID: 21) }
    }
    final class Boundary: CouponManagementConfirmedHTTPTransport {
        let configuration: APIConfiguration
        let credentials: CouponManagementReadCredentials
        var sent = 0, replayDenied = false
        var tamper = ""
        var held: CouponManagementDispatchAuthorization?
        init(configuration: APIConfiguration, credentials: CouponManagementReadCredentials) { self.configuration = configuration; self.credentials = credentials }
        func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(#"{"code":200,"data":[]}"#.utf8),200) }
        func sendConfirmed(_ request: URLRequest, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int) {
            held = authorization
            var candidate = request
            switch tamper {
            case "body": candidate.httpBody = Data("{}".utf8)
            case "method": candidate.httpMethod = "PUT"
            case "query": candidate.url = URL(string: request.url!.absoluteString + "?scope=CLUB")
            case "fragment": candidate.url = URL(string: request.url!.absoluteString + "#x")
            case "prefix": candidate.url = URL(string: "https://example.test/other/api/coupon/publish")
            case "encoded": candidate.url = URL(string: "https://example.test/native/api/coupon/%70ublish")
            case "contentType": candidate.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            case "stream": candidate.httpBodyStream = InputStream(data: request.httpBody!)
            default: break
            }
            try authorization.consume(candidate, configuration: configuration, credentials: credentials)
            sent += 1
            do { try authorization.consume(request, configuration: configuration, credentials: credentials) } catch { replayDenied = true }
            return (Data(#"{"code":200,"data":{"id":910}}"#.utf8),200)
        }
    }
    func testCoordinatorTicketIsOneUseAndRequiresMatchingDiskRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try CouponManagementSession(accountID: 7, namespace: "test", epoch: 1, authorizationRevision: "reviewed-lease")
        let credentials = try CouponManagementReadCredentials(session: session, token: "synthetic")
        let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test/native")))
        let boundary = Boundary(configuration: configuration, credentials: credentials)
        let runtime = CouponManagementRuntimeTransport(configuration: configuration, http: boundary, actions: [.publish, .stop], credentials: { credentials })
        let locks = try CouponManagementFileLocks(directory: directory)
        let core = CouponManagementCoordinator(adapter: .init(transport: runtime, dormantWritesEnabled: true), authorizer: Authority(), locks: locks, currentSession: { session })
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(boundary.sent, 1); XCTAssertTrue(boundary.replayDenied); XCTAssertTrue(core.acknowledged)
        XCTAssertNil(core.verifiedRecord)
        XCTAssertThrowsError(try XCTUnwrap(boundary.held).validate()) // acknowledged lock was released
    }
    func testChangedFrozenBytesNeverDispatchAndUnknownRecordSurvivesReopen() async throws {
        for tamper in ["body", "method", "query", "fragment", "prefix", "encoded", "contentType", "stream"] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try CouponManagementSession(accountID: 7, namespace: "test", epoch: 1, authorizationRevision: "reviewed-lease")
        let credentials = try CouponManagementReadCredentials(session: session, token: "synthetic")
        let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test/native")))
        let boundary = Boundary(configuration: configuration, credentials: credentials); boundary.tamper = tamper
        let runtime = CouponManagementRuntimeTransport(configuration: configuration, http: boundary, actions: [.publish, .stop], credentials: { credentials })
        let core = CouponManagementCoordinator(adapter: .init(transport: runtime, dormantWritesEnabled: true), authorizer: Authority(), locks: try CouponManagementFileLocks(directory: directory), currentSession: { session })
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(boundary.sent, 0); XCTAssertEqual(core.issue, .locked)
        XCTAssertNotNil(try CouponManagementFileLocks(directory: directory).pending(ownerKey: session.ownerKey, resource: "publish"))
        }
    }
    func testRuntimeOrdinaryDescriptorCannotMintAuthorization() async throws {
        let session = try CouponManagementSession(accountID: 7, namespace: "test", epoch: 1, authorizationRevision: "reviewed-lease")
        let credentials = try CouponManagementReadCredentials(session: session, token: "synthetic")
        let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test/native")))
        let boundary = Boundary(configuration: configuration, credentials: credentials)
        let runtime = CouponManagementRuntimeTransport(configuration: configuration, http: boundary, actions: [.publish, .stop], credentials: { credentials })
        let request = try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft())
        do { _ = try await runtime.send(request, session: session); XCTFail() } catch {}
        let result = await CouponManagementAdapter(transport: runtime, dormantWritesEnabled: true).submit(request, session: session)
        XCTAssertEqual(result, .notSent); XCTAssertEqual(boundary.sent, 0)
    }
    func testOldPendingRecordDecodesWithoutWireAndRemainsLocked() throws {
        let request = try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft())
        let original = CouponManagementPending(operationID: UUID(), ownerKey: "owner", resource: "publish", request: request, createdAt: Date())
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]); value.removeValue(forKey: "wire")
        let decoded = try JSONDecoder().decode(CouponManagementPending.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertEqual(decoded, original); XCTAssertNil(decoded.wire)
    }
}
