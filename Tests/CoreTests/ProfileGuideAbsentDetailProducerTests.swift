import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProfileGuideAbsentDetailProducerTests: XCTestCase {
    func testOriginalSuccessWithoutDataProjectsRemovedOnlyForDetail() async throws {
        let wire = AbsentGuideWire(body: #"{"code":200,"msg":"操作成功"}"#)
        let service = SocialAccountService(configuration: try APIConfiguration(baseURL: URL(string: "https://guide.example/native")!), transport: wire)
        try ProfileGuideReadRoute.detail(21).validateResponse((Data(wire.body.utf8), 200))
        let detail = try await service.information(id: 21, token: "synthetic-guide")
        XCTAssertTrue(detail.isRemoved)
        XCTAssertEqual(detail.id, 0)
        XCTAssertNil(detail.contents)
        XCTAssertThrowsError(try ProfileGuideReadRoute.list.validateResponse((Data(wire.body.utf8), 200)))
        do { _ = try await service.informationList(token: "synthetic-guide"); XCTFail("Absent list is not an empty list") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        do { _ = try await service.profile(memberID: 21, token: "synthetic-guide"); XCTFail("Absent profile remains invalid") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testPresentMalformedOrWrongIdentityDetailStillFails() async throws {
        let wire = AbsentGuideWire(body: "")
        let service = SocialAccountService(configuration: try APIConfiguration(baseURL: URL(string: "https://guide.example/native")!), transport: wire)
        for body in [#"{"code":200,"data":[]}"#, #"{"code":200,"data":{"id":22}}"#,
                     #"{"code":200,"data":{"id":"21"}}"#, #"{"code":200,"data":{"id":true}}"#,
                     #"{"code":200,"data":{"title":"No ID"}}"#] {
            wire.body = body
            XCTAssertThrowsError(try ProfileGuideReadRoute.detail(21).validateResponse((Data(body.utf8), 200)))
            // Original service accepts numeric strings; the scoped route remains stricter.
            if body.contains("\"id\":\"21\"") { continue }
            do { _ = try await service.information(id: 21, token: "synthetic-guide"); XCTFail("Malformed present data cannot mean removed") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testErrorsNeverBecomeRemovedAndFreshDetailRemainsReadable() async throws {
        let wire = AbsentGuideWire(body: #"{"code":401}"#)
        let service = SocialAccountService(configuration: try APIConfiguration(baseURL: URL(string: "https://guide.example/native")!), transport: wire)
        do { _ = try await service.information(id: 21, token: "synthetic-guide"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        wire.status = 503; wire.body = #"{"code":200}"#
        do { _ = try await service.information(id: 21, token: "synthetic-guide"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
        wire.status = 200; wire.body = #"{"code":200,"data":{"id":21,"title":"Guide","contents":"Source text"}}"#
        let detail = try await service.information(id: 21, token: "synthetic-guide")
        XCTAssertFalse(detail.isRemoved); XCTAssertEqual(detail.id, 21)
    }
}

@MainActor private final class AbsentGuideWire: HTTPTransport {
    var body: String
    var status = 200
    init(body: String) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(body.utf8), status) }
}
