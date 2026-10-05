import Foundation

public struct JourneyAskReceipt: Equatable {
    public let nodeID: Int
    public let questionID: String
    public let question: String
    public let answer: String
    public let stateVersion: Int
    init(_ raw: PlayWireValue, nodeID: Int, questionID: String) throws {
        guard raw["nodeId"].integer == nodeID, raw["questionId"].text == questionID,
              let question = raw["q"].text, let answer = raw["a"].text,
              let version = raw["stateVersion"].integer, version >= 0 else { throw PlayExperienceError.malformed }
        self.nodeID = nodeID; self.questionID = questionID; self.question = question; self.answer = answer; stateVersion = version
    }
}
/// Uses the same protected runtime transport. Endpoint approval and action approval
/// are independent; neither reads nor writes can be enabled by a server response.
public struct JourneyNarrativeService {
    private let api: PlayExperienceService
    public var realm: String { api.configuration.baseURL.absoluteString }
    public let readsEnabled: Bool
    public let asksEnabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, readsEnabled: Bool = false, asksEnabled: Bool = false) {
        api = .init(configuration: configuration, transport: transport, enabled: [.reads, .journeyAsks])
        self.readsEnabled = readsEnabled; self.asksEnabled = asksEnabled
    }
    public func read(_ query: JourneyNarrativeQuery, scope: JourneyNarrativeScope, token: String) async throws -> JourneyNarrativeDocument {
        guard readsEnabled else { throw PlayExperienceError.disabled }
        return try JourneyNarrativeDocument(await api.request(query.path, query: query.fields(scope), capability: .reads, token: token), query: query)
    }
    func ask(scope: JourneyNarrativeScope, nodeID: Int, questionID: String, token: String) async throws -> JourneyAskReceipt {
        guard asksEnabled else { throw PlayExperienceError.disabled }
        guard nodeID > 0, JourneyQuestion.validID(questionID) else { throw APIError.invalidRequest }
        var fields = scope.json; fields["nodeId"] = .int(nodeID); fields["questionId"] = .string(questionID)
        return try JourneyAskReceipt(await api.request("api/play/journey/ask", json: fields, capability: .journeyAsks, token: token), nodeID: nodeID, questionID: questionID)
    }
}

/// Write-ahead reservations contain only owner/run/node/question identifiers.
/// Unknown outcomes require server readback; a relaunch never automatically retries.
@MainActor public protocol JourneyNarrativeJournal: AnyObject {
    var isDurable: Bool { get }
    func pending(owner: PlayExperienceSession, scope: JourneyNarrativeScope, realm: String, runID: Int, nodeID: Int) throws -> Set<String>
    func save(_ ids: Set<String>, owner: PlayExperienceSession, scope: JourneyNarrativeScope, realm: String, runID: Int, nodeID: Int) throws
}
@MainActor public final class JourneyStoredNarrativeJournal: JourneyNarrativeJournal {
    public let isDurable = true
    private let read: (String) throws -> Data?
    private let write: (Data, String) throws -> Void
    public init(read: @escaping (String) throws -> Data?, write: @escaping (Data, String) throws -> Void) { self.read = read; self.write = write }
    private func key(_ owner: PlayExperienceSession, _ scope: JourneyNarrativeScope, _ realm: String, _ runID: Int, _ nodeID: Int) throws -> String {
        guard !realm.isEmpty, runID > 0, nodeID > 0 else { throw APIError.invalidRequest }
        let raw = "\(realm.utf8.count):\(realm):\(owner.namespace.utf8.count):\(owner.namespace):\(owner.accountID):\(scope.key):\(runID):\(nodeID)"
        return "journey-narrative.v2." + Data(raw.utf8).base64EncodedString()
    }
    public func pending(owner: PlayExperienceSession, scope: JourneyNarrativeScope, realm: String, runID: Int, nodeID: Int) throws -> Set<String> {
        guard let data = try read(key(owner, scope, realm, runID, nodeID)) else { return [] }
        let values = try JSONDecoder().decode(Set<String>.self, from: data)
        guard values.allSatisfy(JourneyQuestion.validID) else { throw PlayExperienceError.malformed }; return values
    }
    public func save(_ ids: Set<String>, owner: PlayExperienceSession, scope: JourneyNarrativeScope, realm: String, runID: Int, nodeID: Int) throws {
        guard ids.allSatisfy(JourneyQuestion.validID) else { throw APIError.invalidRequest }
        try write(JSONEncoder().encode(ids), key(owner, scope, realm, runID, nodeID))
    }
}
