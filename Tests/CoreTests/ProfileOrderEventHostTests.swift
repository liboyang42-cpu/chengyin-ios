import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Authored for XCTest. Linux execution of this file is NOT_RUN unless compiled.
final class ProfileOrderEventHostTests: XCTestCase {
    private static let token = "fixture-token"
    private struct PostFailed: Error {}

    func testFirstJourneyOwnedOrderReadsInfoThenOriginalEventAndRecoverOriginal() async throws {
        let transport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":501,"title":"周末沙发","payableAmount":200.00,"memberId":7}"#)),
            .json(Self.envelope(#"{"requestId":"c11-owned-order","targetType":"ORDER","targetId":501,"action":"CREATE","afterJson":"UNKNOWN","title":"周末沙发","payableAmount":200.00}"#)),
        ])
        var host = ProfileOrderEventHost()
        let opened = await host.open(501, service: try Self.service(transport), token: Self.token)

        XCTAssertEqual(opened, 501)
        XCTAssertEqual(host.calls, [
            .init(path: "api/registration/info", id: "501"),
            .init(path: "api/registration/original-event", id: "501"),
        ])
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/fixture/api/registration/info",
            "/fixture/api/registration/original-event",
        ])
        for request in transport.requests {
            let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!
            XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n501\r\n"))
            XCTAssertFalse(body.contains("title"))
            XCTAssertFalse(body.contains("payableAmount"))
            XCTAssertFalse(body.contains("audit-log"))
            XCTAssertFalse(body.contains("business/audit"))
        }
        XCTAssertFalse(host.calls.contains { $0.path.contains("audit-log") || $0.path.contains("business/audit") })
        let events = try XCTUnwrap(host.injection.events)
        XCTAssertEqual(events, [
            OriginalAuditEvent(
                requestId: "c11-owned-order", targetType: "ORDER", targetId: 501,
                action: "CREATE", afterJson: "UNKNOWN"),
        ])
        XCTAssertEqual(host.injection.lookups, 1)
        XCTAssertEqual(host.injection.sends, 0)
        let projection = SupportCurrentProjection(
            requestId: "c11-owned-order",
            appliedState: SupportEventLocator.projectionAppliedSuccess)
        let recovered = try XCTUnwrap(host.injection.recoverOriginal(
            requestID: "c11-owned-order", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(recovered.orderId, 501)
        XCTAssertNotEqual(recovered.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(host.injection.sends, 0)
    }

    func testPostOwnedOrderFormReturnsTheRawBodyAndDoesNotDecodeIt() async throws {
        let raw = #"{"code":200,"data":{"id":501,"title":"周末沙发","payableAmount":200.00,"memberId":7}}"#
        let transport = ProfileTestTransport([.json(raw)])
        let body = try await Self.service(transport).postOwnedOrderForm(
            path: "api/registration/info", id: "501", token: Self.token)
        XCTAssertEqual(body, Data(raw.utf8))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fixture/api/registration/info")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), Self.token)
        let encoded = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)!
        XCTAssertTrue(encoded.contains("name=\"id\"\r\n\r\n501\r\n"))
        XCTAssertFalse(encoded.contains("title"))

        let blocked = ProfileTestTransport([])
        do {
            _ = try await Self.service(blocked).postOwnedOrderForm(
                path: "business/audit-log/list", id: "501", token: Self.token)
            XCTFail("audit log is not an owned order form")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidRequest)
        }
        XCTAssertTrue(blocked.requests.isEmpty)

        let empty = ProfileTestTransport([.json("")])
        let missing = try await Self.service(empty).postOwnedOrderForm(
            path: "api/registration/original-event", id: "501", token: Self.token)
        XCTAssertNil(missing)
        XCTAssertEqual(empty.requests.count, 1)
    }

    func testMismatchTransportFailureAndAbsentBodyDoNotInventEvents() async throws {
        let mismatchTransport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":99,"title":"别的订单","payableAmount":1}"#)),
        ])
        var mismatch = ProfileOrderEventHost()
        let mismatched = await mismatch.open(501, service: try Self.service(mismatchTransport), token: Self.token)
        XCTAssertNil(mismatched)
        XCTAssertEqual(mismatch.calls.map(\.path), ["api/registration/info"])
        XCTAssertEqual(mismatchTransport.requests.map { $0.url?.lastPathComponent }, ["info"])
        XCTAssertNil(mismatch.injection.events)
        XCTAssertEqual(mismatch.injection.lookups, 0)

        let infoTransport = ProfileTestTransport([.failure(PostFailed())])
        var infoFailed = ProfileOrderEventHost()
        let infoFailure = await infoFailed.open(501, service: try Self.service(infoTransport), token: Self.token)
        XCTAssertNil(infoFailure)
        XCTAssertEqual(infoFailed.calls.map(\.path), ["api/registration/info"])
        XCTAssertNil(infoFailed.injection.events)

        let eventTransport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":"501"}"#)),
            .failure(PostFailed()),
        ])
        var eventFailed = ProfileOrderEventHost()
        let eventFailure = await eventFailed.open(501, service: try Self.service(eventTransport), token: Self.token)
        XCTAssertNil(eventFailure)
        XCTAssertEqual(eventFailed.calls.map(\.path), ["api/registration/info", "api/registration/original-event"])
        XCTAssertNil(eventFailed.injection.events)

        let absentTransport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":501}"#)),
            .json(""),
        ])
        var absent = ProfileOrderEventHost()
        let absentBody = await absent.open(501, service: try Self.service(absentTransport), token: Self.token)
        XCTAssertNil(absentBody)
        XCTAssertEqual(absent.calls.count, 2)
        XCTAssertEqual(absentTransport.requests.count, 2)
        XCTAssertNil(absent.injection.events)

        let blankTransport = ProfileTestTransport([.json("{}")])
        var blank = ProfileOrderEventHost()
        let blankID = await blank.open(0, service: try Self.service(blankTransport), token: Self.token)
        XCTAssertNil(blankID)
        XCTAssertEqual(blank.calls, [])
        XCTAssertTrue(blankTransport.requests.isEmpty)
        XCTAssertNil(blank.injection.events)
    }

    func testProfileOrderFieldsAndADifferentFirstOrderDoNotBecomeThisOrder() async throws {
        let profileTransport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":501,"title":"周末沙发","payableAmount":200,"memberId":7,"registrationNo":"NO501"}"#)),
            .json(Self.envelope(#"{"id":501,"title":"周末沙发","payableAmount":200,"memberId":7}"#)),
        ])
        var profile = ProfileOrderEventHost()
        let invented = await profile.open(501, service: try Self.service(profileTransport), token: Self.token)
        XCTAssertNil(invented)
        XCTAssertEqual(profile.calls.map(\.path), ["api/registration/info", "api/registration/original-event"])
        XCTAssertNil(profile.injection.events)
        XCTAssertEqual(profile.injection.sends, 0)

        let differentTransport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":501}"#)),
            .json(Self.envelope(#"[{"requestId":"c11-other","targetType":"ORDER","targetId":9,"action":"CREATE","afterJson":"PENDING"},{"requestId":"c11-owned-order","targetType":"ORDER","targetId":501,"action":"CREATE","afterJson":"UNKNOWN"}]"#)),
        ])
        var different = ProfileOrderEventHost()
        let otherFirst = await different.open(501, service: try Self.service(differentTransport), token: Self.token)
        XCTAssertNil(otherFirst)
        XCTAssertNil(different.injection.events)

        let runTransport = ProfileTestTransport([
            .json(Self.envelope(#"{"id":501}"#)),
            .json(Self.envelope(#"{"requestId":"c11-run","targetType":"RUN","targetId":77,"action":"START","afterJson":"UNKNOWN"}"#)),
        ])
        var runOnly = ProfileOrderEventHost()
        let runRow = await runOnly.open(501, service: try Self.service(runTransport), token: Self.token)
        XCTAssertNil(runRow)
        XCTAssertEqual(runOnly.calls.map(\.path), ["api/registration/info", "api/registration/original-event"])
        XCTAssertNil(runOnly.injection.events)

        let refusedTransport = ProfileTestTransport([
            .json(#"{"code":500,"msg":"无权查看该报名信息","data":{"id":501}}"#),
        ])
        var refused = ProfileOrderEventHost()
        let denied = await refused.open(501, service: try Self.service(refusedTransport), token: Self.token)
        XCTAssertNil(denied)
        XCTAssertEqual(refused.calls.map(\.path), ["api/registration/info"])
        XCTAssertNil(refused.injection.events)
    }

    private static func service(_ transport: ProfileTestTransport) throws -> ProfileService {
        ProfileService(
            configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!),
            transport: transport)
    }

    private static func envelope(_ data: String, code: Int = 200) -> String {
        "{\"code\":\(code),\"data\":\(data)}"
    }
}
