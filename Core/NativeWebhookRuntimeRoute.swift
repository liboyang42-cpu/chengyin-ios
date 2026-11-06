import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NativeWebhookHTTPMethod: String, Codable, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

public enum NativeWebhookRuntimeRoute {
    public static let prefix = "/api/im/webhook"
    public static func collection(_ family: NativeWebhookFamily) -> String {
        prefix + (family == .subscription ? "/subscriptions" : "/endpoints")
    }
    public static func resource(_ family: NativeWebhookFamily, id: NativeWebhookID) -> String {
        collection(family) + "/" + id.rawValue
    }
    public static func rotate(_ family: NativeWebhookFamily, id: NativeWebhookID) -> String {
        resource(family, id: id) + (family == .subscription ? "/rotate-secret" : "/rotate-token")
    }
    public static func deliveries(_ id: NativeWebhookID) -> String { resource(.subscription, id: id) + "/deliveries" }
    public static func inboundLogs(_ id: NativeWebhookID) -> String { resource(.endpoint, id: id) + "/logs" }
    public static func test(_ id: NativeWebhookID) -> String { resource(.subscription, id: id) + "/test" }
    public static func retry(_ id: NativeWebhookID, deliveryID: NativeWebhookID) -> String {
        deliveries(id) + "/" + deliveryID.rawValue + "/retry"
    }
    public static func url(binding: NativeWebhookBinding, path: String, query: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix(prefix + "/"), !path.contains(".."), !path.contains("?"), !path.contains("#"),
              !path.contains("%"), !path.contains("\\"), !path.contains("//"),
              !path.split(separator: "/").contains("."),
              var parts = URLComponents(url: binding.origin.appendingPathComponent(String(path.dropFirst())),
                  resolvingAgainstBaseURL: false) else {
            throw NativeWebhookClientError.invalidInput("WEBHOOK_ROUTE_INVALID")
        }
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url, url.scheme == binding.origin.scheme, url.host == binding.origin.host,
              url.port == binding.origin.port else { throw NativeWebhookClientError.scopeChanged }
        return url
    }
}

public struct NativeWebhookMutationRequest: Sendable {
    public let binding: NativeWebhookBinding
    public let requestID: NativeWebhookRequestID
    public let method: NativeWebhookHTTPMethod
    public let path: String
    public let body: Data
    public let family: NativeWebhookFamily
    public let returnsDelivery: Bool
    public let resourceID: NativeWebhookID?
    public let mayReturnCredential: Bool
    public let expectedDeliveryID: NativeWebhookID?
    public let expectedEventID: String?
    public let expectedEventType: String?
    public let expectedResourceRevision: Int
    public let expectedKeyVersion: Int
    public let expectedDeleted: Bool
    public let expectedStatus: NativeWebhookResourceStatus?

    /// Fail before dispatch if a damaged journal changes route, verb, body family,
    /// target or response binding. The URL prefix alone is insufficient.
    @MainActor public func validateOriginal() throws {
        func require(_ condition: Bool) throws { if !condition { throw NativeWebhookClientError.invalidWire } }
        try require(expectedResourceRevision > 0 && expectedKeyVersion > 0)
        if let change = try? JSONDecoder().decode(NativeWebhookChange.self, from: body) {
            try require(try NativeWebhookHTTPService.encoded(change) == body)
            try require(change.requestID == requestID && change.ownerType == "CLUB"
                && change.ownerID == binding.scope.ownerID.requestNumber && change.channelID == binding.scope.channelID.requestNumber)
            try require(!returnsDelivery && !expectedDeleted && expectedStatus != nil && expectedDeliveryID == nil && expectedEventID == nil && expectedEventType == nil)
            if let id = resourceID {
                try require(method == .put && path == NativeWebhookRuntimeRoute.resource(family, id: id) && !mayReturnCredential)
                guard let revision = change.revision, revision > 0, revision < Int.max else { throw NativeWebhookClientError.invalidWire }
                try require(expectedResourceRevision == revision + 1)
            } else {
                try require(method == .post && path == NativeWebhookRuntimeRoute.collection(family) && mayReturnCredential
                    && change.revision == nil && expectedResourceRevision == 1 && expectedKeyVersion == 1)
            }
            if let status = change.status { try require(status == expectedStatus) }
            return
        }
        let action = try JSONDecoder().decode(NativeWebhookAction.self, from: body)
        try require(try NativeWebhookHTTPService.encoded(action) == body)
        guard let id = resourceID, let revision = action.revision, revision > 0, revision < Int.max else { throw NativeWebhookClientError.invalidWire }
        try require(action.requestID == requestID)
        if path == NativeWebhookRuntimeRoute.resource(family, id: id) {
            try require(method == .delete && !returnsDelivery && !mayReturnCredential && expectedDeleted
                && expectedStatus == .paused && expectedResourceRevision == revision + 1 && action.eventType == nil
                && expectedDeliveryID == nil && expectedEventID == nil && expectedEventType == nil)
        } else if path == NativeWebhookRuntimeRoute.rotate(family, id: id) {
            try require(method == .post && !returnsDelivery && mayReturnCredential && !expectedDeleted
                && expectedStatus != nil && expectedKeyVersion > 1 && expectedResourceRevision == revision + 1 && action.eventType == nil
                && expectedDeliveryID == nil && expectedEventID == nil && expectedEventType == nil)
        } else if family == .subscription, path == NativeWebhookRuntimeRoute.test(id) {
            try require(method == .post && returnsDelivery && !mayReturnCredential && !expectedDeleted && expectedStatus == nil
                && expectedResourceRevision == revision && expectedDeliveryID == nil && expectedEventID == nil
                && action.eventType != nil && action.eventType == expectedEventType)
        } else if family == .subscription, let deliveryID = expectedDeliveryID,
                  path == NativeWebhookRuntimeRoute.retry(id, deliveryID: deliveryID) {
            try require(method == .post && returnsDelivery && !mayReturnCredential && !expectedDeleted && expectedStatus == nil
                && expectedResourceRevision == revision && action.eventType == nil
                && expectedEventID?.isEmpty == false && expectedEventType?.isEmpty == false)
        } else { throw NativeWebhookClientError.invalidWire }
    }
}
