import Foundation
import CryptoKit

/// Non-secret immutable original request. Stored in the existing OperationPendingRecord,
/// via the separate minimal shared-field candidate, never in a second Defaults/file store.
public struct NativeWebhookPendingMetadata: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var binding: NativeWebhookBinding
    public let requestID: NativeWebhookRequestID
    public let method: NativeWebhookHTTPMethod
    public let path: String
    public let family: NativeWebhookFamily
    public let resourceID: NativeWebhookID?
    public let returnsDelivery: Bool
    public let mayReturnCredential: Bool
    public let expectedDeliveryID: NativeWebhookID?
    public let expectedEventID: String?
    public let expectedEventType: String?
    public let expectedResourceRevision: Int
    public let expectedKeyVersion: Int
    public let expectedDeleted: Bool
    public let expectedStatus: NativeWebhookResourceStatus?
    public let safeBody: Data
    public let redactedFields: Set<String>
    public let bodySHA256: String
    public var needsOriginalInput: Bool { !redactedFields.isEmpty }
    public static func digest(_ body: Data) -> String { SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined() }
    @MainActor public init(_ request: NativeWebhookMutationRequest) throws {
        try request.validateOriginal()
        version = 1; binding = request.binding; requestID = request.requestID; method = request.method
        path = request.path; family = request.family; resourceID = request.resourceID
        returnsDelivery = request.returnsDelivery; mayReturnCredential = request.mayReturnCredential
        expectedDeliveryID = request.expectedDeliveryID; expectedEventID = request.expectedEventID; expectedEventType = request.expectedEventType
        expectedResourceRevision = request.expectedResourceRevision; expectedKeyVersion = request.expectedKeyVersion
        expectedDeleted = request.expectedDeleted; expectedStatus = request.expectedStatus
        bodySHA256 = Self.digest(request.body)
        if let change = try? JSONDecoder().decode(NativeWebhookChange.self, from: request.body) {
            var safe = change; var fields = Set<String>()
            if safe.url != nil { fields.insert("url"); safe.url = nil }
            if safe.avatarURL != nil { fields.insert("avatar_url"); safe.avatarURL = nil }
            safeBody = try NativeWebhookHTTPService.encoded(safe); redactedFields = fields
        } else {
            let action = try JSONDecoder().decode(NativeWebhookAction.self, from: request.body)
            guard action.requestID == requestID else { throw NativeWebhookClientError.invalidWire }
            safeBody = try NativeWebhookHTTPService.encoded(action); redactedFields = []
        }
    }
    /// Only replaces a volatile authorization binding after the caller obtains a current
    /// context. Durable account/origin/channel identity and every original intent byte stay fixed.
    /// This is not permission to send: HTTPService revalidates the current binding before I/O.
    public func rebound(to current: NativeWebhookBinding) throws -> Self {
        guard binding.accountID.utf8.elementsEqual(current.accountID.utf8),
              binding.market.utf8.elementsEqual(current.market.utf8),
              binding.namespace.utf8.elementsEqual(current.namespace.utf8),
              binding.origin.absoluteString.utf8.elementsEqual(current.origin.absoluteString.utf8),
              binding.scope == current.scope else { throw NativeWebhookClientError.scopeChanged }
        var copy = self; copy.binding = current; return copy
    }
    fileprivate func sameOriginal(as current: Self) throws -> Bool {
        try rebound(to: current.binding) == current
    }
    /// Called only after explicit review. Input must recreate the exact original bytes/hash;
    /// it never changes request ID, revision, event, scope, method or endpoint.
    @MainActor public func originalRequest(url: String? = nil, avatarURL: String? = nil) throws -> NativeWebhookMutationRequest {
        guard version == 1, bodySHA256.count == 64,
              redactedFields.isSubset(of: ["url", "avatar_url"]), method != .get else { throw NativeWebhookClientError.invalidWire }
        let body: Data
        if var change = try? JSONDecoder().decode(NativeWebhookChange.self, from: safeBody) {
            guard change.requestID == requestID, change.url == nil, change.avatarURL == nil else { throw NativeWebhookClientError.invalidWire }
            if redactedFields.contains("url") { guard let url else { throw NativeWebhookClientError.originalInputRequired }; change.url = url }
            if redactedFields.contains("avatar_url") { guard let avatarURL else { throw NativeWebhookClientError.originalInputRequired }; change.avatarURL = avatarURL }
            body = try NativeWebhookHTTPService.encoded(change)
        } else {
            let action = try JSONDecoder().decode(NativeWebhookAction.self, from: safeBody)
            guard action.requestID == requestID, redactedFields.isEmpty else { throw NativeWebhookClientError.invalidWire }
            body = try NativeWebhookHTTPService.encoded(action)
        }
        guard Self.digest(body) == bodySHA256 else { throw NativeWebhookClientError.conflict(code: "ORIGINAL_BODY_MISMATCH", traceID: nil) }
        let request = NativeWebhookMutationRequest(binding: binding, requestID: requestID, method: method, path: path, body: body,
            family: family, returnsDelivery: returnsDelivery, resourceID: resourceID, mayReturnCredential: mayReturnCredential,
            expectedDeliveryID: expectedDeliveryID, expectedEventID: expectedEventID, expectedEventType: expectedEventType, expectedResourceRevision: expectedResourceRevision,
            expectedKeyVersion: expectedKeyVersion, expectedDeleted: expectedDeleted, expectedStatus: expectedStatus)
        try request.validateOriginal(); return request
    }
}

@MainActor public final class NativeWebhookPendingJournal {
    private let journal: any OperationPendingJournal
    public init(journal: any OperationPendingJournal) { self.journal = journal }
    // Authorization version/epoch/token are deliberately absent from durable slot identity.
    // Recovery still requires a current provider to accept the exact stored binding.
    private func keys(_ binding: NativeWebhookBinding) throws -> (String, String) {
        let owner = try NativeWebhookHTTPService.encoded([binding.origin.absoluteString, binding.market, binding.namespace, binding.accountID])
        return ("webhook:" + owner.base64EncodedString(), "channel:" + binding.scope.ownerID.rawValue + ":" + binding.scope.channelID.rawValue)
    }
    public func pending(_ binding: NativeWebhookBinding) throws -> NativeWebhookPendingMetadata? {
        let (owner, target) = try keys(binding)
        guard let record = try journal.pending(ownerKey: owner, targetKey: target) else { return nil }
        guard let metadata = record.nativeWebhook, record.acknowledgedSteps == 0,
              metadata.version == 1, try keys(metadata.binding) == (owner, target) else { throw NativeWebhookClientError.invalidWire }
        return metadata
    }
    public func reserve(_ request: NativeWebhookMutationRequest) throws {
        let metadata = try NativeWebhookPendingMetadata(request), (owner, target) = try keys(request.binding)
        if let existing = try journal.pending(ownerKey: owner, targetKey: target) {
            guard let original = existing.nativeWebhook, try original.sameOriginal(as: metadata) else {
                throw NativeWebhookClientError.conflict(code: "ORIGINAL_REQUEST_PENDING", traceID: nil)
            }
            // Keep the originally persisted binding as historical evidence. No new request is written.
            return
        }
        var record = OperationPendingRecord(ownerKey: owner, targetKey: target)
        record.nativeWebhook = metadata
        try journal.write(record)
        guard try journal.pending(ownerKey: owner, targetKey: target) == record else { throw NativeWebhookClientError.invalidWire }
    }
    public func settle(_ request: NativeWebhookMutationRequest) throws {
        let metadata = try NativeWebhookPendingMetadata(request), (owner, target) = try keys(request.binding)
        guard let record = try journal.pending(ownerKey: owner, targetKey: target),
              let original = record.nativeWebhook, try original.sameOriginal(as: metadata) else {
            throw NativeWebhookClientError.conflict(code: "ORIGINAL_REQUEST_CHANGED", traceID: nil)
        }
        try journal.clear(record)
    }
}
