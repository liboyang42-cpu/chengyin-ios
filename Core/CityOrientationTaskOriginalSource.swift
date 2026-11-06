import Foundation
import CryptoKit
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original cms_topic_node identity within the existing personal topic_route_session.
/// No new task, run, score or reward is created by this adapter.
public struct CityOrientationTaskCommand: Codable, Equatable {
    public let sessionId: Int
    public let nodeId: Int
    public let requestId: String
    public let expectedVersion: Int
    public let answer: String
    public init(sessionID: Int, nodeID: Int, requestID: UUID = UUID(), expectedVersion: Int, answer: String) throws {
        sessionId = sessionID; nodeId = nodeID; requestId = requestID.uuidString
        self.expectedVersion = expectedVersion; self.answer = answer
        try validate()
    }
    func validate() throws {
        guard sessionId > 0, nodeId > 0, UUID(uuidString: requestId) != nil, expectedVersion >= 0,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.utf16.count <= 300 else { throw PlayExperienceError.invalidAction }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionId == rhs.sessionId && lhs.nodeId == rhs.nodeId && lhs.expectedVersion == rhs.expectedVersion &&
        lhs.requestId.utf8.elementsEqual(rhs.requestId.utf8) && lhs.answer.utf8.elementsEqual(rhs.answer.utf8)
    }
    var payloadHash: String {
        let raw = "\(sessionId):\(nodeId):\(expectedVersion):\(answer.utf8.count):\(answer)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CityOrientationTaskReceipt: Codable, Equatable {
    public let contract: String
    public let sessionId: Int
    public let nodeId: Int
    public let requestId: String
    public let payloadHash: String
    public let configVersion: Int?
    public let revision: Int
    public let outcome: String
    public let response: PlayWireValue
    public var succeeded: Bool { outcome == "APPLIED" }
    public var message: String? { response["msg"].text }
    public var score: Int? { response["data"]["puzzleScore"].tolerantInteger }
    public var xp: Int? { response["data"]["xp"].tolerantInteger }
    public var answerWrong: Bool { response["data"]["answerWrong"].bool == true }
    func validate(_ command: CityOrientationTaskCommand) throws {
        guard contract == "CITY_ORIENTATION_ANSWER_V1", sessionId == command.sessionId, nodeId == command.nodeId,
              requestId == command.requestId, payloadHash == command.payloadHash, revision >= 0,
              !succeeded || revision >= command.expectedVersion, !succeeded || (configVersion ?? -1) >= 0,
              ["APPLIED", "FAILED"].contains(outcome), let code = response["code"].tolerantInteger,
              (code == 200) == succeeded,
              !succeeded || response["data"]["nodeId"].tolerantInteger == nodeId else { throw PlayExperienceError.malformed }
    }
}

/// Secure-store payload only. Credentials are never serialized; the answer is retained only
/// to permit an explicit identical retry, not to create a new intent after a lost response.
public struct CityOrientationTaskPending: Codable, Equatable {
    let owner: PlayRecoveryOwner
    let command: CityOrientationTaskCommand
    var receipt: CityOrientationTaskReceipt?
    var settled: Bool
}

@MainActor public final class CityOrientationTaskJournal {
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data?, write: @escaping (Data, String) throws -> Void) {
        self.read = read; self.write = write
    }
    private func key(_ binding: String) -> String {
        "city-orientation-answer-v1:" + SHA256.hash(data: Data(binding.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func load(_ binding: String, owner: PlayRecoveryOwner) throws -> CityOrientationTaskPending? {
        guard let data = try read(key(binding)) else { return nil }
        guard data.count <= 262_144, let value = try? JSONDecoder().decode(CityOrientationTaskPending.self, from: data),
              value.owner == owner, !value.settled || value.receipt != nil else { throw PlayExperienceError.persistenceUnavailable }
        try value.command.validate(); try value.receipt?.validate(value.command)
        return value
    }
    public func pendingSessionID(realm: URL, scope: PlaySessionScope, session: PlayExperienceSession) throws -> Int? {
        let binding = realm.absoluteString + ":" + PlayRunStorageKey.make(session: session, scope: scope)
        guard let value = try load(binding, owner: .init(session: session)), !value.settled else { return nil }
        return value.command.sessionId
    }
    func replace(_ value: CityOrientationTaskPending, expected: CityOrientationTaskPending?, binding: String) throws {
        guard try load(binding, owner: value.owner) == expected else { throw PlayExperienceError.persistenceUnavailable }
        // Validate before writing: a failed replacement must not destroy the recoverable original.
        try value.command.validate()
        try value.receipt?.validate(value.command)
        guard !value.settled || value.receipt != nil else { throw PlayExperienceError.persistenceUnavailable }
        if let expected {
            // UNKNOWN and unacknowledged terminals retain their exact original command bytes.
            guard expected.settled || value.command == expected.command else { throw PlayExperienceError.persistenceUnavailable }
            if value.command == expected.command {
                // Original receipt evidence and settlement cannot be erased or rewritten.
                guard expected.receipt == nil || value.receipt == expected.receipt,
                      !expected.settled || value.settled else { throw PlayExperienceError.persistenceUnavailable }
            } else {
                // A new command starts pending, never with a fabricated known outcome.
                guard UUID(uuidString: value.command.requestId) != UUID(uuidString: expected.command.requestId),
                      value.receipt == nil, !value.settled else { throw PlayExperienceError.persistenceUnavailable }
            }
        } else {
            guard value.receipt == nil, !value.settled else { throw PlayExperienceError.persistenceUnavailable }
        }
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= 262_144 else { throw PlayExperienceError.persistenceUnavailable }
        try write(bytes, key(binding))
        guard try load(binding, owner: value.owner) == value else { throw PlayExperienceError.persistenceUnavailable }
    }
}

/// The existing play reader remains the task/progress truth. Writes require a separate,
/// default-off integration grant; reads, login and opening a task never grant submissions.
public struct CityOrientationTaskService {
    private let play: PlayService
    private let configuration: APIConfiguration
    private let receiptTransport: (any HTTPTransport)?
    private let answerTransport: (any HTTPTransport)?
    public let receiptSessionID: Int?
    public let answerSessionID: Int?
    public var receiptReadsEnabled: Bool { receiptTransport != nil && (receiptSessionID ?? 0) > 0 }
    public var writesEnabled: Bool { receiptTransport != nil && answerTransport != nil && (answerSessionID ?? 0) > 0 && receiptSessionID == answerSessionID }
    /// The existing play transport reads only nodes/route-state. New endpoints each require
    /// their own approved transport; nil is closed and a read never implies an answer grant.
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                receiptTransport: (any HTTPTransport)? = nil, answerTransport: (any HTTPTransport)? = nil,
                receiptSessionID: Int? = nil, answerSessionID: Int? = nil) {
        self.configuration = configuration; self.receiptTransport = receiptTransport; self.answerTransport = answerTransport
        self.receiptSessionID = receiptSessionID; self.answerSessionID = answerSessionID
        play = .init(configuration: configuration, transport: transport)
    }
    var realm: String { configuration.baseURL.absoluteString }
    func tasks(scope: PlaySessionScope, token: String) async throws -> PlaySnapshot {
        let nodes = try await play.nodes(scope: scope, token: token)
        guard nodes.mode == 1 else { throw PlayExperienceError.unsupported }
        let route = nodes.routeState?.isBranch == true ? try await play.routeState(scope: scope, token: token) : nil
        return try PlaySnapshot(scope: scope, result: nodes, authority: route)
    }
    func submit(_ command: CityOrientationTaskCommand, token: String) async throws -> CityOrientationTaskReceipt {
        guard writesEnabled, let answerTransport, command.sessionId == answerSessionID else { throw PlayExperienceError.disabled }
        try command.validate()
        var request = try request(path: "answer", token: token)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(command)
        let raw = try await execute(request, using: answerTransport)
        let receipt: CityOrientationTaskReceipt = try raw.decoded(); try receipt.validate(command); return receipt
    }
    func original(_ command: CityOrientationTaskCommand, token: String) async throws -> CityOrientationTaskReceipt? {
        guard let receiptTransport, command.sessionId == receiptSessionID else { throw PlayExperienceError.disabled }
        var request = try request(path: "receipt", token: token)
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "sessionId", value: String(command.sessionId)),
                         URLQueryItem(name: "nodeId", value: String(command.nodeId)), URLQueryItem(name: "requestId", value: command.requestId)]
        request.url = url.url
        let raw = try await execute(request, using: receiptTransport)
        if raw["outcome"].text == "PENDING", raw["sessionId"].tolerantInteger == command.sessionId,
           raw["nodeId"].tolerantInteger == command.nodeId, raw["requestId"].text == command.requestId { return nil }
        let receipt: CityOrientationTaskReceipt = try raw.decoded(); try receipt.validate(command); return receipt
    }
    private func request(path: String, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw PlayExperienceError.unauthorized }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/play/city-orientation/" + path))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    /// Only an actual HTTP 401 or the original bounded 2xx/code-401 envelope is auth evidence.
    /// Cancellation, transport errors, malformed bodies and other status codes are not.
    public static func isAuthenticationFailure(_ result: (Data, Int)) -> Bool {
        if result.1 == 401 { return true }
        guard (200..<300).contains(result.1), result.0.count <= 262_144,
              let raw = try? JSONDecoder().decode(PlayWireValue.self, from: result.0) else { return false }
        return raw["code"].tolerantInteger == 401
    }
    private func execute(_ request: URLRequest, using transport: any HTTPTransport) async throws -> PlayWireValue {
        try Task.checkCancellation()
        let (bytes, status) = try await transport.send(request)
        if Self.isAuthenticationFailure((bytes, status)) { throw PlayExperienceError.unauthorized }
        try Task.checkCancellation()
        guard bytes.count <= 262_144 else { throw PlayExperienceError.malformed }
        if status == 401 { throw PlayExperienceError.unauthorized }
        if status == 403 { throw PlayExperienceError.rejected(403, nil) }
        guard (200..<300).contains(status) else { throw PlayExperienceError.unknownResult }
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: bytes)
        if raw["code"].tolerantInteger == 401 { throw PlayExperienceError.unauthorized }
        guard raw["code"].tolerantInteger == 200 else { throw PlayExperienceError.rejected(raw["code"].tolerantInteger ?? 500, raw["msg"].text) }
        return raw["data"]
    }
}
