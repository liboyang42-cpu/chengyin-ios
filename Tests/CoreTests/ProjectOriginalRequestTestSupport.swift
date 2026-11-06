import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fixture-only paired server around the existing original-result cases. Nothing is sent.
func projectOriginalTestReceipt(_ request: URLRequest, legacy: Data) throws -> Data {
    guard request.url?.path.hasSuffix("/api/topic/edit-requests/submit") == true else { return legacy }
    let sent = try JSONDecoder().decode(ProjectEditRequestContract.Submit.self, from: XCTUnwrap(request.httpBody))
    let original = try JSONDecoder().decode([String: ProjectEditJSON].self, from: legacy)
    return try projectOriginalTestReceipt(sent, state: original["code"] == .number(200) ? "COMMITTED" : "REJECTED", original: original["data"] ?? .null)
}
func projectOriginalTestReceipt(_ sent: ProjectEditRequestContract.Submit, state: String = "COMMITTED", original: ProjectEditJSON = .number(71)) throws -> Data {
    let body: [String: ProjectEditJSON] = ["protocolVersion": .string(sent.protocolVersion), "requestId": .string(sent.requestId), "originalPath": .string(sent.originalPath), "payloadSHA256": .string(sent.payloadSHA256), "state": .string(state), "postProcessing": .string("NOT_RECONCILED"), "originalResult": original]
    return try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(body)])
}
func projectOriginalTestPayload(_ request: URLRequest) throws -> [String: ProjectEditJSON] {
    let sent = try JSONDecoder().decode(ProjectEditRequestContract.Submit.self, from: XCTUnwrap(request.httpBody))
    return try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(Data(base64Encoded: sent.payloadBase64Chunks.joined())))
}
