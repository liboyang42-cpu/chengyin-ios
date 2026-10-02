import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An endpoint URL never grants mutation permission. The composition root must inject an
/// independently reviewed, exact deployment/account/path grant. No production grant exists.
public struct OperationEndpointApproval: Equatable {
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let paths: Set<String>
    public init(baseURL: URL, namespace: String, accountID: Int, paths: Set<String>) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !namespace.isEmpty, accountID > 0, paths.allSatisfy({ $0.hasPrefix("api/") && !$0.contains("..") && !$0.contains("?") }) else { throw APIError.invalidConfiguration }
        self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID; self.paths = paths
    }
    public func allows(configuration: APIConfiguration, namespace: String, accountID: Int, path: String) -> Bool {
        baseURL == configuration.baseURL && self.namespace == namespace && self.accountID == accountID && paths.contains(path)
    }
}

/// Local replay lock only. There is no server operation ID, receipt endpoint or retry key.
public struct OperationPendingRecord: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let targetKey: String
    public var acknowledgedSteps: Int
    public init(operationID: UUID = UUID(), ownerKey: String, targetKey: String, acknowledgedSteps: Int = 0) {
        self.operationID = operationID; self.ownerKey = ownerKey; self.targetKey = targetKey; self.acknowledgedSteps = acknowledgedSteps
    }
}
@MainActor public protocol OperationPendingJournal: AnyObject {
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord?
    func write(_ record: OperationPendingRecord) throws
    func clear(_ record: OperationPendingRecord) throws
}
/// Stores only account/deployment scoped operation identity, target and acknowledged step count.
/// Never stores tokens, invite codes, drafts, media, member names or response messages.
@MainActor public final class OperationDefaultsJournal: OperationPendingJournal {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ owner: String, _ target: String) -> String {
        "questify.operations.pending.v1." + Data("\(owner.utf8.count):\(owner):\(target)".utf8).base64EncodedString()
    }
    public func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        guard let raw = defaults.object(forKey: key(ownerKey, targetKey)) else { return nil }
        guard let data = raw as? Data, let record = try? JSONDecoder().decode(OperationPendingRecord.self, from: data),
              record.ownerKey == ownerKey, record.targetKey == targetKey, record.acknowledgedSteps >= 0 else { throw APIError.malformedResponse }
        return record
    }
    public func write(_ record: OperationPendingRecord) throws {
        if let existing = try pending(ownerKey: record.ownerKey, targetKey: record.targetKey), existing.operationID != record.operationID { throw APIError.invalidRequest }
        let data = try JSONEncoder().encode(record), name = key(record.ownerKey, record.targetKey)
        defaults.set(data, forKey: name)
        guard defaults.data(forKey: name) == data else { throw APIError.malformedResponse }
    }
    public func clear(_ record: OperationPendingRecord) throws {
        guard try pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { throw APIError.invalidRequest }
        let name = key(record.ownerKey, record.targetKey); defaults.removeObject(forKey: name)
        guard defaults.object(forKey: name) == nil else { throw APIError.malformedResponse }
    }
}

enum OperationAdapterHTTP {
    static func json(configuration: APIConfiguration, path: String, body: Data, token: String) throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token, includesBody: false)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        return request
    }
    static func envelope(_ data: Data) throws -> [String: ProjectEditJSON] {
        try JSONDecoder().decode([String: ProjectEditJSON].self, from: data)
    }
    static func positiveID(_ value: ProjectEditJSON?) -> Int? {
        let id = value?.integer ?? value?.text.flatMap(Int.init)
        return id.flatMap { $0 > 0 ? $0 : nil }
    }
}
