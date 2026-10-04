import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ClubActionServiceTests: XCTestCase {
    private func service(_ transport: ClubActionTestTransport) throws -> ClubActionService {
        ClubActionService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testJoinAndApplyUseCurrentJSONWhileLeaveKeepsItsContract() async throws {
        for action in [ClubAction.join, .apply, .leave] {
            let t = ClubActionTestTransport()
            t.json = #"{"code":200,"data":{"state":"pending"},"msg":"  Source receipt  "}"#
            let receipt = try await service(t).perform(action, clubID: 7, token: "fixture-token")
            XCTAssertEqual(receipt, ClubActionReceipt(state: "pending", message: "  Source receipt  "))
            let request = try XCTUnwrap(t.requests.first)
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/fixture/api/club/" + (action == .leave ? "quit" : "join"))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            if action == .leave {
                XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            } else { XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json") }
            let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
            if action == .leave {
                XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n7\r\n"))
            } else {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                XCTAssertEqual(json["id"] as? Int, 7)
                XCTAssertEqual(Set(json.keys), action == .apply ? Set(["id", "joinMessage"]) : Set(["id"]))
            }
            XCTAssertFalse(body.contains("clubId")); XCTAssertFalse(body.contains("approved")); XCTAssertFalse(body.contains("payment"))
            if action == .leave { XCTAssertEqual(body.components(separatedBy: "name=\"").count, 2) }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testJoinedPendingMissingAndUnknownReceiptStatesAreNotConflated() async throws {
        let values: [(String, String?)] = [
            (#"{"code":200,"data":{"state":"joined"}}"#, "joined"),
            (#"{"code":200,"data":{"state":"pending"}}"#, "pending"),
            (#"{"code":200,"data":{"state":"future-state"}}"#, "future-state"),
            (#"{"code":200}"#, nil), (#"{"code":200,"data":null}"#, nil),
            (#"{"code":200,"data":{"state":42}}"#, nil)
        ]
        for (json, expected) in values {
            let t = ClubActionTestTransport(); t.json = json
            let receipt = try await service(t).perform(.join, clubID: 7, token: "fixture-token")
            XCTAssertEqual(receipt.state, expected)
        }
    }
    func testApplicationMessagePreservesReviewedUnicodeAndJSONEscaping() async throws {
        for message in ["", "   ", "  朋友推荐 👋\nA&B + \"quote\"  ", String(repeating: "😀", count: 30), String(repeating: "e\u{301}", count: 30)] {
            let t = ClubActionTestTransport()
            _ = try await service(t).perform(.apply, clubID: 7, token: "fixture-token", joinMessage: message)
            let data = try XCTUnwrap(t.requests.first?.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["joinMessage"] as? String, message)
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testOverlongAndNonApplicationMessagesNeverDispatch() async throws {
        for (action, message) in [(ClubAction.apply, String(repeating: "a", count: 61)), (.apply, String(repeating: "😀", count: 31)), (.join, "hello"), (.leave, "hello")] {
            let t = ClubActionTestTransport()
            do { _ = try await service(t).perform(action, clubID: 7, token: "fixture-token", joinMessage: message); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.invalidRequest)) }
            XCTAssertTrue(t.requests.isEmpty)
        }
    }
    func testReceivedApplicationMessageIsOptionalAndTyped() throws {
        for suffix in ["", ",\"joinMessage\":null", ",\"joinMessage\":\"\"", ",\"joinMessage\":\"你好 👋\""] {
            let data = Data(("{\"memberId\":7" + suffix + "}").utf8)
            let value = try JSONDecoder().decode(ClubManagementRequest.self, from: data)
            XCTAssertEqual(value.joinMessage, suffix.contains("你好") ? "你好 👋" : suffix.hasSuffix("\"\"") ? "" : nil)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ClubManagementRequest.self, from: Data(#"{"memberId":7,"joinMessage":42}"#.utf8)))
    }
    func testInvalidInputSendsNothing() async throws {
        let t = ClubActionTestTransport(), s = try service(t)
        for id in [0, -1] {
            do { _ = try await s.perform(.join, clubID: id, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.invalidRequest)) }
        }
        for token in ["", " ", "bad\r\nheader", "bad\tvalue"] {
            do { _ = try await s.perform(.leave, clubID: 7, token: token); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.invalidRequest)) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testAuthenticationAndForbiddenAreExplicitRejections() async throws {
        for code in [401, 403] {
            for status in [200, code] {
                let t = ClubActionTestTransport(); t.status = status; t.json = "{\"code\":\(code),\"msg\":\"Server decision\"}"
                do { _ = try await service(t).perform(.join, clubID: 7, token: "fixture-token"); XCTFail() }
                catch { XCTAssertEqual(error as? ClubActionWriteError, .rejected(.init(httpStatus: status == 200 ? nil : status, code: code, message: "Server decision"))) }
                XCTAssertEqual(t.requests.count, 1)
            }
        }
    }
    func testHTTPAuthDecisionSurvivesMalformedEnvelope() async throws {
        for status in [401, 403] {
            let t = ClubActionTestTransport(); t.status = status; t.json = "malformed"
            do { _ = try await service(t).perform(.leave, clubID: 7, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .rejected(.init(httpStatus: status))) }
        }
    }
    func testBusinessRejectionRetainsServerMessageAndNeverRetries() async throws {
        let t = ClubActionTestTransport(); t.json = #"{"code":409,"msg":"  Approval is required  "}"#
        do { _ = try await service(t).perform(.join, clubID: 7, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .rejected(.init(code: 409, message: "  Approval is required  "))) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testHTTP500RedirectAndTimeoutAreUnknownWithoutRetry() async throws {
        for status in [301, 429, 500] {
            let t = ClubActionTestTransport(); t.status = status; t.json = #"{"code":500,"msg":"Unknown"}"#
            do { _ = try await service(t).perform(.leave, clubID: 7, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .outcomeUnknown(.response(.init(httpStatus: status, code: 500, message: "Unknown")))) }
            XCTAssertEqual(t.requests.count, 1)
        }
        let t = ClubActionTestTransport(); t.error = URLError(.timedOut)
        do { _ = try await service(t).perform(.leave, clubID: 7, token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .outcomeUnknown(.transport)) }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testMalformedAcknowledgementIsUnknown() async throws {
        for json in ["not json", "{}", #"{"code":"200"}"#, #"{"data":{"state":"joined"}}"#] {
            let t = ClubActionTestTransport(); t.json = json
            do { _ = try await service(t).perform(.join, clubID: 7, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .outcomeUnknown(.malformedResponse)) }
        }
    }
    func testCancellationAfterDispatchIsUnknown() async throws {
        let failures: [Error] = [CancellationError(), URLError(.cancelled)]
        for failure in failures {
            let t = ClubActionTestTransport(); t.error = failure
            do { _ = try await service(t).perform(.join, clubID: 7, token: "fixture-token"); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .outcomeUnknown(.cancelled)) }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
}

private final class ClubActionTestTransport: HTTPTransport {
    var json = #"{"code":200}"#
    var status = 200
    var error: Error?
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let error { throw error }
        return (Data(json.utf8), status)
    }
}
