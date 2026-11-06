import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Contract rejection through the existing service, with synthetic replies only.
/// No fixture grants a real route or substitutes for a backend receipt producer.
final class NativeChannelTypedReadReceiptContractTests: XCTestCase {
    func testLegacyVoidSuccessAndUnstructuredDataCannotBecomeAnAcknowledgement() async throws {
        for raw in [#"{"code":200}"#, #"{"code":200,"msg":"success"}"#,
                    #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#,
                    #"{"code":200,"data":[]}"#, #"{"code":200,"data":true}"#] {
            await rejectsMalformed(Data(raw.utf8), label: raw)
        }
    }

    func testEveryTypedReceiptFieldIsRequiredAndCannotBeNull() async throws {
        for key in ["conversationId", "readTo", "lastReadMessageId", "unread"] {
            var absent = valid
            absent.removeValue(forKey: key)
            await rejectsMalformed(try envelope(absent), label: "missing \(key)")
            var null = valid
            null[key] = NSNull()
            await rejectsMalformed(try envelope(null), label: "null \(key)")
        }
    }

    func testStringsBooleansAndFractionalValuesDoNotSupplyIntegerReceiptFields() async throws {
        for key in ["conversationId", "readTo", "lastReadMessageId", "unread"] {
            for wrong in ["40", true, 1.5] as [Any] {
                var value = valid
                value[key] = wrong
                await rejectsMalformed(try envelope(value), label: "wrong type \(key): \(wrong)")
            }
        }
    }

    func testAnotherConversationOrCutoffCannotConfirmThisReadIntent() async throws {
        for (key, wrong) in [("conversationId", 10), ("readTo", 41)] {
            var value = valid
            value[key] = wrong
            await rejectsMalformed(try envelope(value), label: "mismatched \(key)")
        }
    }

    func testInvalidWatermarkOrUnreadCannotBecomeAReceipt() async throws {
        for (key, wrong) in [("lastReadMessageId", 0), ("lastReadMessageId", -1), ("unread", -1)] {
            var value = valid
            value[key] = wrong
            await rejectsMalformed(try envelope(value), label: "invalid \(key): \(wrong)")
        }
    }

    func testValidReceiptPreservesServerWatermarkAndUnreadWithoutNumericIDAssumptions() async throws {
        // A smaller numeric ID can be later in server visibility order. The client
        // cannot replace that committed watermark with readTo or invent unread=0.
        let wire = Wire(try envelope(valid))
        let receipt = try await service(wire).readThrough(conversationID: 9, readTo: 40, token: "synthetic-receipt-token")
        XCTAssertEqual(receipt.conversationId, 9)
        XCTAssertEqual(receipt.readTo, 40)
        XCTAssertEqual(receipt.lastReadMessageId, 3)
        XCTAssertEqual(receipt.unread, 5)
        XCTAssertEqual(wire.requests.count, 1)
    }

    private var valid: [String: Any] {
        ["conversationId": 9, "readTo": 40, "lastReadMessageId": 3, "unread": 5]
    }
    private func envelope(_ data: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": data])
    }
    private func service(_ wire: Wire) throws -> NativeChannelService {
        NativeChannelService(configuration: try .init(baseURL: URL(string: "https://example.test/native")!),
                             transport: wire, allowsReadReceipt: true)
    }
    private func rejectsMalformed(_ response: Data, label: String, file: StaticString = #filePath, line: UInt = #line) async {
        let wire = Wire(response)
        do {
            _ = try await service(wire).readThrough(conversationID: 9, readTo: 40, token: "synthetic-receipt-token")
            XCTFail("Accepted invalid typed receipt: \(label)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? APIError, .malformedResponse, label, file: file, line: line)
        }
        XCTAssertEqual(wire.requests.count, 1, label, file: file, line: line)
    }
    private final class Wire: HTTPTransport {
        let response: Data
        var requests: [URLRequest] = []
        init(_ response: Data) { self.response = response }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/native/api/native/channels/read-through")
            XCTAssertEqual(request.httpMethod, "POST")
            return (response, 200)
        }
    }
}
