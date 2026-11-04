import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read identity, not merchant ownership or permission to invoke AI.
public struct MerchantGamePlayerSession: Equatable, Sendable {
    public let namespace: String
    public let accountID: Int
    public let epoch: UInt64
    let credential: String
    public init(namespace: String, accountID: Int, epoch: UInt64, credential: String) throws {
        guard !namespace.isEmpty, accountID > 0, AuthRequestBuilder.isValidToken(credential) else { throw APIError.invalidConfiguration }
        self.namespace = namespace; self.accountID = accountID; self.epoch = epoch; self.credential = credential
    }
}
public enum MerchantGamePlayerFailure: Error, Equatable {
    case configuration, unauthorized, unknown, malformed, stale
}
public enum MerchantGamePlayerPublication: Equatable {
    case none, withdrawn
    case published(releaseID: String, version: Int, facts: [String: String])
}
public struct MerchantGamePlayerOriginal: Equatable {
    public let requestID: UUID
    public let merchantID: Int
    public let outcome: String
    public let safety: String
    public let safeText: String
    public let errorCode: String?
    public let retryable: Bool
    public let ai: Bool
    public var terminal: Bool { ["SUCCEEDED", "FAILED", "REJECTED"].contains(outcome) }
    public var succeeded: Bool { outcome == "SUCCEEDED" && safety == "PASS" && !retryable }
    init(row: [String: ProjectEditJSON], merchantID: Int, requestID: UUID) throws {
        guard row["merchantId"]?.integer == merchantID,
              row["requestId"]?.text == requestID.uuidString,
              let outcome = row["outcomeStatus"]?.text, ["SUCCEEDED", "FAILED", "REJECTED", "PROCESSING"].contains(outcome),
              let safety = row["safetyDecision"]?.text,
              ["PASS", "BLOCKED", "NOT_RUN"].contains(safety) || (outcome == "PROCESSING" && safety == "UNKNOWN"),
              case .bool(let retryable)? = row["retryable"], case .bool(let ai)? = row["ai"] else { throw MerchantGamePlayerFailure.malformed }
        let text = row["safeText"]?.text ?? ""
        guard text.utf8.count <= 32_768,
              outcome != "SUCCEEDED" || (safety == "PASS" && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { throw MerchantGamePlayerFailure.malformed }
        self.requestID = requestID; self.merchantID = merchantID; self.outcome = outcome; self.safety = safety
        self.safeText = text; self.errorCode = row["errorCode"]?.text; self.retryable = retryable; self.ai = ai
    }
}

/// Uses the exact existing public merchant-chat journal key. A read never resends its lost prompt.
@MainActor public final class MerchantGamePlayerService {
    public let merchantID: Int
    private let api: APIConfiguration
    private let captured: MerchantGamePlayerSession
    private let grant: MerchantGamePlayerReadGrant?
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let current: () -> MerchantGamePlayerSession?
    private var verified: (OperationPendingRecord, MerchantGamePlayerOriginal)?
    private var readbackGeneration: UInt64 = 0
    public init(configuration: APIConfiguration, merchantID: Int, session: MerchantGamePlayerSession,
                grant: MerchantGamePlayerReadGrant?, transport: any HTTPTransport, journal: any OperationPendingJournal,
                current: @escaping () -> MerchantGamePlayerSession?) throws {
        guard merchantID > 0 else { throw APIError.invalidRequest }
        api = configuration; self.merchantID = merchantID; captured = session; self.grant = grant
        self.transport = transport; self.journal = journal; self.current = current
    }
    public var isCurrent: Bool { current() == captured }
    private var ownerKey: String { "merchant-public-chat:\(api.baseURL.absoluteString):\(captured.namespace.utf8.count):\(captured.namespace):\(captured.accountID)" }
    private var targetKey: String { "merchant-row:\(merchantID)" }
    public func pending() throws -> OperationPendingRecord? {
        guard isCurrent else { throw MerchantGamePlayerFailure.stale }
        guard let record = try journal.pending(ownerKey: ownerKey, targetKey: targetKey) else { return nil }
        guard record.ownerKey == ownerKey, record.targetKey == targetKey else { throw MerchantGamePlayerFailure.malformed }
        return record
    }
    public func publication() async throws -> MerchantGamePlayerPublication {
        let row = try await read("api/merchant/authoring/player/\(merchantID)/game")
        guard row["merchantId"]?.integer == merchantID, let outcome = row["outcome"]?.text else { throw MerchantGamePlayerFailure.malformed }
        if outcome == "NONE" { return .none }
        if outcome == "WITHDRAWN" { return .withdrawn }
        guard outcome == "PUBLISHED", let id = row["releaseId"]?.integer, id > 0,
              let version = row["revisionVersion"]?.integer, version > 0,
              let fields = row["facts"]?.object else { throw MerchantGamePlayerFailure.malformed }
        var facts: [String: String] = [:]
        for (key, value) in fields where MerchantGamePlayerReadGrant.publicFactKeys.contains(key) {
            if let text = value.text { facts[key] = text }
            else if let number = value.integer { facts[key] = String(number) }
            else if let array = value.array?.compactMap(\.text) { facts[key] = array.joined(separator: ",") }
        }
        guard !facts.isEmpty else { throw MerchantGamePlayerFailure.malformed }
        return .published(releaseID: String(id), version: version, facts: facts)
    }
    public func original(_ record: OperationPendingRecord) async throws -> MerchantGamePlayerOriginal {
        discardReadback()
        let generation = readbackGeneration
        guard try pending() == record else { throw MerchantGamePlayerFailure.stale }
        let row = try await read("api/merchant/authoring/player/\(merchantID)/requests/\(record.operationID.uuidString)")
        // Revocation or a newer original read retires this response even when
        // the account and durable request ID have not changed.
        guard readbackGeneration == generation, try pending() == record else { throw MerchantGamePlayerFailure.stale }
        let result = try MerchantGamePlayerOriginal(row: row, merchantID: merchantID, requestID: record.operationID)
        verified = (record, result)
        return result
    }
    public func discardReadback() { readbackGeneration &+= 1; verified = nil }
    /// Explicit local acknowledgement, never a server mutation or a new game/model request.
    public func acknowledge(_ result: MerchantGamePlayerOriginal, record: OperationPendingRecord) throws {
        guard isCurrent, MerchantGamePlayerReceipt.canAcknowledge(result, record: record, merchantID: merchantID),
              verified?.0 == record, verified?.1 == result, try pending() == record else { throw MerchantGamePlayerFailure.stale }
        try journal.clear(record); discardReadback()
    }
    private func read(_ path: String) async throws -> [String: ProjectEditJSON] {
        guard isCurrent, !Task.isCancelled else { throw MerchantGamePlayerFailure.stale }
        guard let grant, grant.allows(configuration: api, namespace: captured.namespace, accountID: captured.accountID, path: path) else { throw MerchantGamePlayerFailure.configuration }
        var request = try OperationAdapterHTTP.json(configuration: api, path: path, body: Data(), token: captured.credential)
        request.httpMethod = "GET"; request.httpBody = nil; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let response: (Data, Int)
        do { response = try await transport.send(request) } catch {
            guard isCurrent, !Task.isCancelled else { throw MerchantGamePlayerFailure.stale }
            throw MerchantGamePlayerFailure.unknown
        }
        guard isCurrent, !Task.isCancelled else { throw MerchantGamePlayerFailure.stale }
        if response.1 == 401 || response.1 == 403 { throw MerchantGamePlayerFailure.unauthorized }
        guard (200..<300).contains(response.1), response.0.count <= 1_048_576 else { throw MerchantGamePlayerFailure.unknown }
        let body = try OperationAdapterHTTP.envelope(response.0)
        if body["code"]?.integer == 401 || body["code"]?.integer == 403 { throw MerchantGamePlayerFailure.unauthorized }
        guard body["code"]?.integer == 200 else { throw MerchantGamePlayerFailure.unknown }
        guard let row = body["data"]?.object else { throw MerchantGamePlayerFailure.malformed }
        return row
    }
}

@MainActor @Observable public final class MerchantGamePlayerCoordinator {
    public private(set) var publication: MerchantGamePlayerPublication?
    public private(set) var pending: OperationPendingRecord?
    public private(set) var original: MerchantGamePlayerOriginal?
    public private(set) var failure: MerchantGamePlayerFailure?
    public private(set) var busy = false
    public private(set) var acknowledged = false
    public private(set) var active = true
    private let service: MerchantGamePlayerService
    private var epoch: UInt64 = 0
    private var loadedPending = false
    public init(service: MerchantGamePlayerService) { self.service = service }
    public var canAcknowledge: Bool {
        guard active, service.isCurrent, !busy, let original, let pending else { return false }
        return MerchantGamePlayerReceipt.canAcknowledge(original, record: pending, merchantID: service.merchantID)
    }
    public var canOpenChat: Bool { loadedPending && active && service.isCurrent && !busy && pending == nil && failure == nil }
    public func activate() { guard service.isCurrent else { revoke(); return }; active = true; failure = nil }
    public func load() async {
        guard active, !busy else { return }
        let stamp = epoch; busy = true; defer { if epoch == stamp { busy = false } }
        loadedPending = false
        original = nil; publication = nil; failure = nil; acknowledged = false
        do { pending = try service.pending(); loadedPending = true } catch { fail(error); return }
        do {
            let value = try await service.publication()
            guard active, epoch == stamp else { return }
            publication = value
        } catch { guard active, epoch == stamp else { return }; fail(error) }
    }
    public func readOriginal() async {
        guard active, !busy, let pending else { return }
        let stamp = epoch; busy = true; defer { if epoch == stamp { busy = false } }
        original = nil; failure = nil; acknowledged = false
        do {
            let value = try await service.original(pending)
            guard active, epoch == stamp else { return }
            original = value
        } catch { guard active, epoch == stamp else { return }; fail(error) }
    }
    public func acknowledgeOriginal() {
        guard canAcknowledge, let original, let pending else { return }
        do { try service.acknowledge(original, record: pending); self.pending = nil; acknowledged = true; failure = nil }
        catch { fail(error) }
    }
    public func revoke() { loadedPending = false; service.discardReadback(); epoch &+= 1; active = false; publication = nil; pending = nil; original = nil; failure = .stale; busy = false; acknowledged = false }
    private func fail(_ error: Error) {
        let error = error as? MerchantGamePlayerFailure ?? .unknown
        if error == .unauthorized || error == .stale { revoke() }
        failure = error
    }
}
