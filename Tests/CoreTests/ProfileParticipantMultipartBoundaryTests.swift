import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ProfileParticipantMultipartBoundaryTests: XCTestCase {
    private let base = URL(string: "https://participant.example.test/native/")!
    private let boundary = "participant-crlf-regression"

    private func request(_ leaf: String, fields: [String: String]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(
            url: base.appendingPathComponent("api/user/address/" + leaf), fields: fields,
            token: "synthetic-participant-boundary", boundary: boundary)
    }

    func testSingleCharacterIDIsNotRemovedWithCRLFTerminator() throws {
        // Executable Swift characterization of the original bug: byte count
        // must not be used as String.Character count when trimming a delimiter.
        XCTAssertEqual("\r\n".utf8.count, 2)
        XCTAssertEqual("\r\n".count, 1)
        XCTAssertEqual(String("9\r\n".dropLast(2)), "")
        XCTAssertEqual(String("9\r\n".dropLast("\r\n".count)), "9")
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("info", fields: ["id": "9"]), baseURL: base)?.operation, .info(9))
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("delete", fields: ["id": "9"]), baseURL: base)?.operation, .delete(9))
    }

    func testMultibyteAndCombiningFieldValuesKeepExactCanonicalBytes() throws {
        let fields = ["id": "9", "fullName": "林 e\u{301} 👩🏽‍💻", "mobilePhone": "13900000000",
                      "isDefault": "1", "province": "江苏", "detailAddress": "一号楼🧭"]
        let built = try request("action", fields: fields)
        XCTAssertEqual(ProfileParticipantRoute.parse(built, baseURL: base)?.operation, .edit(9))
        let id = UUID()
        let create = ["fullName": "林 e\u{301} 👩🏽‍💻", "mobilePhone": "13900000000",
                      "isDefault": "0", "requestId": id.uuidString.lowercased()]
        XCTAssertEqual(ProfileParticipantRoute.parse(try request("action", fields: create), baseURL: base)?.operation, .create(id))
    }

    func testMissingLoneOrExtraTerminatorBytesRemainRejected() throws {
        let built = try request("delete", fields: ["id": "9"])
        let data = try XCTUnwrap(built.httpBody)
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        let suffix = "\r\n--\(boundary)--\r\n"
        XCTAssertTrue(body.hasSuffix(suffix))
        let malformed = [
            body.replacingOccurrences(of: suffix, with: "\n--\(boundary)--\r\n"),
            body.replacingOccurrences(of: suffix, with: "--\(boundary)--\r\n"),
            body.replacingOccurrences(of: suffix, with: "\r\r\n--\(boundary)--\r\n"),
            body.replacingOccurrences(of: suffix, with: "\r\n--\(boundary)--\n"),
            body + "\r\n"
        ]
        for bytes in malformed {
            var altered = built
            altered.httpBody = Data(bytes.utf8)
            XCTAssertNil(ProfileParticipantRoute.parse(altered, baseURL: base))
        }
    }
}
