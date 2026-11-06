import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileParticipantAccessTests: XCTestCase {
    let base = URL(string: "https://example.com/native/")!
    func context(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-7") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: token))
    }
    func request(_ path: String, _ fields: [String: String]? = nil) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/user/address/" + path),
            fields: fields ?? [:], token: "synthetic-7", includesBody: fields != nil, boundary: "participant-test-boundary")
    }
    func testOriginalFourRoutesAndCanonicalCreateUUID() throws {
        let id = UUID()
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("list"), baseURL: base)?.operation, .list)
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("info", ["id":"9"]), baseURL: base)?.operation, .info(9))
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("delete", ["id":"9"]), baseURL: base)?.operation, .delete(9))
        let create = ["fullName":"林 Test", "mobilePhone":"13900000000", "isDefault":"0", "requestId":id.uuidString.lowercased()]
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("action", create), baseURL: base)?.operation, .create(id))
        let edit = ["id":"9", "fullName":"林 Test", "mobilePhone":"13900000000", "isDefault":"1", "province":"P", "detailAddress":"A"]
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("action", edit), baseURL: base)?.operation, .edit(9))
    }
    func testRejectsAliasesExtraFieldsMissingIDAndNoncanonicalMultipart() throws {
        var bad: [URLRequest] = [try request("setDefault", ["id":"9", "isDefault":"1"]),
            try request("list", [:]), try request("info", ["id":"09"]), try request("delete", ["id":"-1"]),
            try request("info", ["id":"9", "scope":"MY"]),
            try request("action", ["fullName":"Name","mobilePhone":"13900000000","isDefault":"0"]),
            try request("action", ["id":"9","fullName":"Name","mobilePhone":"13900000000","isDefault":"0","requestId":UUID().uuidString.lowercased()])]
        let original = try request("info", ["id":"9"])
        var method = original; method.httpMethod = "GET"; bad.append(method)
        var query = original; query.url = URL(string: original.url!.absoluteString + "?id=9"); bad.append(query)
        var origin = original; origin.url = URL(string: "https://other.example.com/native/api/user/address/info"); bad.append(origin)
        var fragment = original; fragment.url = URL(string: original.url!.absoluteString + "#x"); bad.append(fragment)
        var malformed = original; malformed.httpBody = Data(String(decoding: original.httpBody!, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").utf8); bad.append(malformed)
        var duplicate = original
        let part = "--participant-test-boundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n9\r\n"
        duplicate.httpBody = Data((part + part + "--participant-test-boundary--\r\n").utf8); bad.append(duplicate)
        var cookie = original; cookie.setValue("not-source", forHTTPHeaderField: "Cookie"); bad.append(cookie)
        var stream = original; stream.httpBodyStream = InputStream(data: Data()); bad.append(stream)
        for value in bad { XCTAssertNil(ProfileParticipantRoute.parse(value, baseURL: base)) }
    }
    func testReadOnlyAndRevokedGrantDispatchNothingForMutations() async throws {
        let owner = try context(), spy = ParticipantAccessWire()
        let access = try ProfileParticipantAccess(context: owner, permitsWrites: false, expiresAt: Date().addingTimeInterval(60))
        let read = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { owner }, stillCurrent: { true })
        _ = try await read.send(request("list")); XCTAssertEqual(spy.calls, 1)
        let write = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { owner }, stillCurrent: { true })
        do { _ = try await write.send(request("delete", ["id":"9"])); XCTFail() } catch {}
        XCTAssertFalse(write.hasForwardedRequest); XCTAssertEqual(spy.calls, 1)
        access.revoke()
        let revoked = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { owner }, stillCurrent: { true })
        do { _ = try await revoked.send(request("list")); XCTFail() } catch {}
        XCTAssertFalse(revoked.hasForwardedRequest); XCTAssertEqual(spy.calls, 1)
    }
    func testWrongCredentialAndScopeNeverDispatchAndLateRevocationDiscardsResult() async throws {
        let owner = try context(), spy = ParticipantAccessWire()
        let access = try ProfileParticipantAccess(context: owner, permitsWrites: true, expiresAt: Date().addingTimeInterval(60))
        var now: RuntimeDependencyContext? = owner
        let wrong = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { now }, stillCurrent: { true })
        var req = try request("list"); req.setValue("replacement", forHTTPHeaderField: "Authorization")
        do { _ = try await wrong.send(req); XCTFail() } catch {}
        XCTAssertEqual(spy.calls, 0)
        now = try context(account: 8)
        let changed = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { now }, stillCurrent: { true })
        do { _ = try await changed.send(request("list")); XCTFail() } catch {}
        XCTAssertEqual(spy.calls, 0)
        now = owner; spy.onSend = { access.revoke() }
        let late = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { now }, stillCurrent: { true })
        do { _ = try await late.send(request("delete", ["id":"9"])); XCTFail() } catch {}
        XCTAssertTrue(late.hasForwardedRequest); XCTAssertEqual(spy.calls, 1)
    }
    func testLeaseRejectsBadExpiryAndDoesNotAcceptChangedEpochRoleOrToken() throws {
        let owner = try context()
        XCTAssertThrowsError(try ProfileParticipantAccess(context: owner, permitsWrites: true, expiresAt: Date().addingTimeInterval(-1)))
        let access = try ProfileParticipantAccess(context: owner, permitsWrites: true, expiresAt: Date().addingTimeInterval(60))
        XCTAssertFalse(access.matches(try context(epoch: 2)))
        XCTAssertFalse(access.matches(try context(token: "replacement")))
        XCTAssertFalse(access.matches(.init(market: .china, baseURL: base, role: "merchant", session: owner.session)))
        XCTAssertFalse(access.matches(owner, now: Date().addingTimeInterval(120)))
    }
    func testOriginalServicesReachOnlyCanonicalSingleAttempts() async throws {
        let owner = try context(), access = try ProfileParticipantAccess(context: owner, permitsWrites: true, expiresAt: Date().addingTimeInterval(60))
        let spy = ParticipantAccessWire(); spy.response = (Data(#"{"code":200,"data":{"rows":[]}}"#.utf8),200)
        let wire = ProfileParticipantTransport(context: owner, access: access, underlying: spy, current: { owner }, stillCurrent: { true })
        let service = ProfileService(configuration: try .init(baseURL: base), transport: wire)
        let rows = try await service.participants(token: "synthetic-7"); XCTAssertTrue(rows.isEmpty)
        do { _ = try await service.participants(token: "synthetic-7"); XCTFail() } catch {}
        XCTAssertEqual(spy.calls, 1)
    }
}
private final class ParticipantAccessWire: HTTPTransport {
    var calls = 0
    var response = (Data(#"{"code":200}"#.utf8), 200)
    var onSend: (@MainActor () -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; await onSend?(); return response
    }
}
