import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private final class ApplicationRequiredHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data,Int) {
        requests.append(request)
        return (Data(#"{"code":200,"data":{"state":"PENDING"}}"#.utf8),200)
    }
}
final class ClubApplicationRequiredMessageTests: XCTestCase {
    func testOnlyApprovalApplicationRequiresNonblankMessage() {
        for message in ["", " ", "\n\t "] {
            XCTAssertFalse(ClubApplicationMessage.isValid(message,for:.apply))
            XCTAssertTrue(ClubApplicationMessage.isMissingRequiredMessage(message))
        }
        for action in [ClubAction.join,.leave] {
            XCTAssertTrue(ClubApplicationMessage.isValid("",for:action))
            XCTAssertFalse(ClubApplicationMessage.isValid("message",for:action))
        }
    }
    func testExistingUTF16BoundIsUnchangedAndTextNotTruncated() {
        XCTAssertTrue(ClubApplicationMessage.isValid(String(repeating:"好",count:60),for:.apply))
        XCTAssertFalse(ClubApplicationMessage.isValid(String(repeating:"好",count:61),for:.apply))
        XCTAssertTrue(ClubApplicationMessage.isValid(String(repeating:"😀",count:30),for:.apply))
        XCTAssertFalse(ClubApplicationMessage.isValid(String(repeating:"😀",count:31),for:.apply))
        XCTAssertTrue(ClubApplicationMessage.isValid("  Reviewed words  ",for:.apply))
    }
    func testMissingApplicationStopsAtOriginalServiceBeforeHTTP() async throws {
        let t = ApplicationRequiredHTTP()
        let api = try ClubActionService(configuration:.init(baseURL:URL(string:"https://required.invalid")!),transport:t)
        for message in ["", " \n\t"] {
            do { _ = try await api.perform(.apply,clubID:10,token:"synthetic-token",joinMessage:message); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError,.notSent(.invalidRequest)) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testValidReviewedApplicationUsesUnchangedOriginalWriterBody() async throws {
        let t = ApplicationRequiredHTTP()
        let api = try ClubActionService(configuration:.init(baseURL:URL(string:"https://required.invalid")!),transport:t)
        let message = "  I would like to join  "
        let receipt = try await api.perform(.apply,clubID:10,token:"synthetic-token",joinMessage:message)
        XCTAssertEqual(receipt.state,"PENDING"); XCTAssertEqual(t.requests.count,1)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path,"/api/club/join")
        let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        XCTAssertEqual(body["joinMessage"] as? String,message)
    }
}
