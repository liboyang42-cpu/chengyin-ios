import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NativeWebhookManagementAction: Sendable {
    case delete, rotate, test(eventType: String), retry(deliveryID: NativeWebhookID)
}

@MainActor public final class NativeWebhookHTTPService {
    private let provider: any NativeWebhookScopeProvider
    private let authorizer: any NativeWebhookRequestAuthorizer
    private let transport: any HTTPTransport
    public init(provider: any NativeWebhookScopeProvider, authorizer: any NativeWebhookRequestAuthorizer,
                transport: any HTTPTransport) {
        self.provider = provider; self.authorizer = authorizer; self.transport = transport
    }
    public static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public func resources(_ family: NativeWebhookFamily, context: NativeWebhookContext, cursor: String? = nil,
                          limit: Int = 20) async throws -> NativeWebhookPage<NativeWebhookResource> {
        var query = try pageQuery(cursor, limit: limit)
        query += [URLQueryItem(name: "owner_type", value: "CLUB"), URLQueryItem(name: "owner_id", value: context.binding.scope.ownerID.rawValue),
                  URLQueryItem(name: "channel_id", value: context.binding.scope.channelID.rawValue)]
        let page: NativeWebhookPage<NativeWebhookResource> = try await read(context, path: NativeWebhookRuntimeRoute.collection(family), query: query)
        try validPage(page, limit: limit, previous: cursor)
        for resource in page.list { try validate(resource, family: family, context: context) }
        return page
    }
    public func resource(_ family: NativeWebhookFamily, id: NativeWebhookID, context: NativeWebhookContext) async throws -> NativeWebhookResource {
        let value: NativeWebhookResource = try await read(context, path: NativeWebhookRuntimeRoute.resource(family, id: id))
        guard value.id == id else { throw NativeWebhookClientError.invalidWire }
        try validate(value, family: family, context: context); return value
    }
    public func deliveries(_ id: NativeWebhookID, context: NativeWebhookContext, state: NativeWebhookDeliveryState? = nil,
                           cursor: String? = nil, limit: Int = 20, includePayload: Bool = false) async throws -> NativeWebhookPage<NativeWebhookDelivery> {
        var query = try pageQuery(cursor, limit: limit)
        query.append(URLQueryItem(name: "include_payload", value: includePayload ? "1" : "0"))
        if let state { query.append(URLQueryItem(name: "state", value: state.rawValue)) }
        let page: NativeWebhookPage<NativeWebhookDelivery> = try await read(context, path: NativeWebhookRuntimeRoute.deliveries(id), query: query)
        try validPage(page, limit: limit, previous: cursor)
        guard page.list.allSatisfy({ $0.id == $0.deliveryID && !$0.eventID.isEmpty && !$0.eventType.isEmpty && $0.attempt >= 0 }) else { throw NativeWebhookClientError.invalidWire }
        guard state == nil || page.list.allSatisfy({ $0.state == state }) else { throw NativeWebhookClientError.invalidWire }
        return page
    }
    public func inboundLogs(_ id: NativeWebhookID, context: NativeWebhookContext, result: NativeWebhookInboundState? = nil,
                            cursor: String? = nil, limit: Int = 20) async throws -> NativeWebhookPage<NativeWebhookInboundLog> {
        var query = try pageQuery(cursor, limit: limit)
        if let result { query.append(URLQueryItem(name: "result", value: result.rawValue)) }
        let page: NativeWebhookPage<NativeWebhookInboundLog> = try await read(context, path: NativeWebhookRuntimeRoute.inboundLogs(id), query: query)
        try validPage(page, limit: limit, previous: cursor)
        guard result == nil || page.list.allSatisfy({ $0.result == result }) else { throw NativeWebhookClientError.invalidWire }
        guard page.list.allSatisfy({ row in
            guard row.result == row.state else { return false }
            if row.result == .accepted {
                // Accepted requires the actual original im_message sender identity.
                return (row.endpointID == nil || row.endpointID == id) && row.webhookID == id
                    && row.senderType == 4 && row.messageID != nil
            }
            if row.result == .pendingReview || (row.result == .blocked && row.messageID != nil) {
                // Same original inserted image and final callback identity, not a rejected pre-insert attempt.
                return row.originalMessageStored == true && row.endpointID == id && row.webhookID == id
                    && row.senderType == 4 && row.messageID != nil
            }
            // A rejected pre-insert attempt never pretends that a webhook message was inserted.
            return [.rejected, .blocked, .rateLimited].contains(row.result) && row.endpointID == id
                && row.originalMessageStored != true && row.messageID == nil && row.senderType == nil && row.webhookID == nil
        }) else { throw NativeWebhookClientError.invalidWire }
        return page
    }
    public func changeRequest(_ family: NativeWebhookFamily, change: NativeWebhookChange, original: NativeWebhookResource?,
                              context: NativeWebhookContext) throws -> NativeWebhookMutationRequest {
        let scope = context.binding.scope
        guard change.ownerType == "CLUB", change.ownerID == scope.ownerID.requestNumber,
              change.channelID == scope.channelID.requestNumber, !change.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              change.name.utf16.count <= 64 else { throw NativeWebhookClientError.invalidInput("WEBHOOK_CHANGE_INVALID") }
        if let original {
            try validate(original, family: family, context: context)
            guard original.revision < Int.max else { throw NativeWebhookClientError.invalidWire }
            guard change.revision == original.revision else { throw NativeWebhookClientError.invalidInput("REVISION_CONFLICT") }
        } else if change.revision != nil { throw NativeWebhookClientError.invalidInput("REVISION_CONFLICT") }
        if family == .subscription {
            guard let events = change.events, !events.isEmpty, events.count <= 32, Set(events).count == events.count else {
                throw NativeWebhookClientError.invalidInput("EVENT_UNKNOWN")
            }
            if let catalogue = context.eventCatalogue.options {
                guard Set(events).isSubset(of: Set(catalogue.map(\.id))) else { throw NativeWebhookClientError.invalidInput("EVENT_UNKNOWN") }
            } else if original?.events != events {
                throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_EVENT_CATALOGUE_UNAVAILABLE")
            }
            if original == nil && change.url == nil { throw NativeWebhookClientError.invalidInput("URL_REQUIRED") }
            if let raw = change.url {
                guard let url = URL(string: raw), url.scheme == "https", url.host != nil, url.user == nil,
                      url.password == nil, url.fragment == nil else { throw NativeWebhookClientError.invalidInput("URL_INVALID") }
            }
        } else {
            guard let rate = change.rateLimitPerMinute, (1...300).contains(rate), let ips = change.allowedIPs, ips.count <= 32 else {
                throw NativeWebhookClientError.invalidInput("ENDPOINT_SETTINGS_REQUIRED")
            }
        }
        return NativeWebhookMutationRequest(binding: context.binding, requestID: change.requestID,
            method: original == nil ? .post : .put,
            path: original.map { NativeWebhookRuntimeRoute.resource(family, id: $0.id) } ?? NativeWebhookRuntimeRoute.collection(family),
            body: try Self.encoded(change), family: family, returnsDelivery: false, resourceID: original?.id, mayReturnCredential: original == nil, expectedDeliveryID: nil, expectedEventID: nil, expectedEventType: nil,
            expectedResourceRevision: original.map { $0.revision + 1 } ?? 1, expectedKeyVersion: original?.keyVersion ?? 1,
            expectedDeleted: false, expectedStatus: change.status ?? original?.status ?? .active)
    }
    public func actionRequest(_ action: NativeWebhookManagementAction, family: NativeWebhookFamily, resource: NativeWebhookResource,
                              context: NativeWebhookContext, requestID: NativeWebhookRequestID, delivery: NativeWebhookDelivery? = nil) throws -> NativeWebhookMutationRequest {
        try validate(resource, family: family, context: context)
        guard resource.revision < Int.max, resource.keyVersion < Int.max else { throw NativeWebhookClientError.invalidWire }
        let path: String, method: NativeWebhookHTTPMethod, eventType: String?, returnsDelivery: Bool, credential: Bool
        switch action {
        case .delete:
            path = NativeWebhookRuntimeRoute.resource(family, id: resource.id); method = .delete
            eventType = nil; returnsDelivery = false; credential = false
        case .rotate:
            path = NativeWebhookRuntimeRoute.rotate(family, id: resource.id); method = .post
            eventType = nil; returnsDelivery = false; credential = true
        case .test(let type):
            guard family == .subscription, resource.status == .active, resource.events?.contains(type) == true,
                  let options = context.eventCatalogue.options, options.contains(where: { $0.id == type }) else {
                throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_EVENT_CATALOGUE_UNAVAILABLE")
            }
            path = NativeWebhookRuntimeRoute.test(resource.id); method = .post; eventType = type; returnsDelivery = true; credential = false
        case .retry(let id):
            guard family == .subscription, resource.status == .active, let delivery,
                  delivery.deliveryID == id, delivery.offersExplicitRetry else { throw NativeWebhookClientError.invalidInput("DELIVERY_NOT_RETRYABLE") }
            path = NativeWebhookRuntimeRoute.retry(resource.id, deliveryID: id); method = .post
            eventType = nil; returnsDelivery = true; credential = false
        }
        let deleting: Bool, rotating: Bool
        if case .delete = action { deleting = true } else { deleting = false }
        if case .rotate = action { rotating = true } else { rotating = false }
        let body = NativeWebhookAction(requestID: requestID, revision: resource.revision, eventType: eventType)
        return NativeWebhookMutationRequest(binding: context.binding, requestID: requestID, method: method, path: path,
            body: try Self.encoded(body), family: family, returnsDelivery: returnsDelivery, resourceID: resource.id, mayReturnCredential: credential,
            expectedDeliveryID: delivery?.deliveryID, expectedEventID: delivery?.eventID, expectedEventType: eventType ?? delivery?.eventType,
            expectedResourceRevision: resource.revision + (returnsDelivery ? 0 : 1), expectedKeyVersion: resource.keyVersion + (rotating ? 1 : 0),
            expectedDeleted: deleting, expectedStatus: returnsDelivery ? nil : (deleting ? .paused : resource.status))
    }
    /// Only the original method/path/body is accepted. There is no invented status/receipt endpoint.
    public func perform(_ operation: NativeWebhookMutationRequest) async throws -> NativeWebhookMutationReceipt {
        try operation.validateOriginal()
        let data = try await exchange(binding: operation.binding, method: operation.method, path: operation.path, body: operation.body)
        do {
        if operation.returnsDelivery {
            let value: NativeWebhookDelivery = try envelope(data)
            guard value.id == value.deliveryID, value.attempt >= 0,
                  operation.expectedDeliveryID == nil || value.deliveryID == operation.expectedDeliveryID,
                  operation.expectedEventID == nil || value.eventID == operation.expectedEventID,
                  operation.expectedEventType == nil || value.eventType == operation.expectedEventType else { throw NativeWebhookClientError.invalidWire }
            return .delivery(value)
        }
        let value: ResourceWire = try envelope(data)
        let context = try await provider.revalidate(operation.binding)
        guard context.binding == operation.binding else { throw NativeWebhookClientError.scopeChanged }
        try validate(value.resource, family: operation.family, context: context)
        if let id = operation.resourceID, id != value.resource.id { throw NativeWebhookClientError.invalidWire }
        guard value.resource.revision == operation.expectedResourceRevision, value.resource.keyVersion == operation.expectedKeyVersion,
              value.resource.deleted == operation.expectedDeleted, value.resource.status == operation.expectedStatus else {
            throw NativeWebhookClientError.invalidWire
        }
        if let change = try? JSONDecoder().decode(NativeWebhookChange.self, from: operation.body) {
            guard value.resource.name == change.name else { throw NativeWebhookClientError.invalidWire }
            if operation.family == .subscription {
                guard value.resource.events == change.events else { throw NativeWebhookClientError.invalidWire }
            } else {
                guard value.resource.rateLimitPerMinute == change.rateLimitPerMinute,
                      value.resource.allowedIPs == change.allowedIPs, value.resource.avatarURL == change.avatarURL else { throw NativeWebhookClientError.invalidWire }
            }
        }
        let replayed = value.replayed == true
        var credential: NativeWebhookOneTimeCredential?
        if operation.mayReturnCredential && !replayed && value.secretShownOnce == true {
            if operation.family == .subscription, let secret = value.secret, !secret.isEmpty {
                credential = NativeWebhookOneTimeCredential(requestID: operation.requestID, secret: secret, endpointURL: nil, oldTokenInvalidAfter: value.oldTokenInvalidAfter)
            } else if operation.family == .endpoint, value.urlShownOnce == true,
                      let secret = value.signingSecret, !secret.isEmpty, let url = value.url, !url.isEmpty {
                guard let endpoint = URL(string: url), endpoint.scheme == "https", endpoint.host != nil,
                      endpoint.user == nil, endpoint.password == nil, endpoint.fragment == nil else { throw NativeWebhookClientError.invalidWire }
                credential = NativeWebhookOneTimeCredential(requestID: operation.requestID, secret: secret, endpointURL: url, oldTokenInvalidAfter: value.oldTokenInvalidAfter)
            }
        }
        return .resource(NativeWebhookResourceReceipt(resource: value.resource, replayed: replayed, credential: credential,
            credentialWasNotRecovered: operation.mayReturnCredential && credential == nil))
        } catch NativeWebhookClientError.invalidWire { throw NativeWebhookClientError.resultUnknown(traceID: nil) }
          catch is DecodingError { throw NativeWebhookClientError.resultUnknown(traceID: nil) }
    }
    private func read<T: Decodable>(_ context: NativeWebhookContext, path: String, query: [URLQueryItem] = []) async throws -> T {
        try envelope(await exchange(binding: context.binding, method: .get, path: path, query: query))
    }
    private func exchange(binding: NativeWebhookBinding, method: NativeWebhookHTTPMethod, path: String,
                          query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        let current = try await provider.revalidate(binding)
        try Task.checkCancellation()
        guard current.binding == binding else { throw NativeWebhookClientError.scopeChanged }
        var request = URLRequest(url: try NativeWebhookRuntimeRoute.url(binding: binding, path: path, query: query))
        request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.httpMethod = method.rawValue; request.httpBody = body; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation()
        let authorized = try await authorizer.authorize(request, binding: binding)
        try Task.checkCancellation()
        guard authorized.url == request.url, authorized.httpMethod == request.httpMethod, authorized.httpBody == request.httpBody,
              !authorized.httpShouldHandleCookies else {
            throw NativeWebhookClientError.scopeChanged
        }
        let data: Data, status: Int
        try Task.checkCancellation()
        do { (data, status) = try await transport.send(authorized) }
        catch { throw method == .get ? NativeWebhookClientError.sourceUnavailable("WEBHOOK_READ_UNAVAILABLE") : .resultUnknown(traceID: nil) }
        try Task.checkCancellation()
        // A definite HTTP denial remains a denial even when a gateway returns HTML,
        // an empty body or an oversized response. Never retain private cache on it.
        if status == 401 || status == 403 {
            let header: Header?
            if data.count <= 4 * 1024 * 1024 { header = try? JSONDecoder().decode(Header.self, from: data) }
            else { header = nil }
            if status == 401 { authorizer.unauthorized(binding) }
            throw NativeWebhookClientError.denied(code: Self.safeCode(header?.err), traceID: header?.traceID)
        }
        try Task.checkCancellation()
        let latest = try await provider.revalidate(binding)
        try Task.checkCancellation()
        guard latest.binding == binding else { throw NativeWebhookClientError.scopeChanged }
        try Task.checkCancellation()
        let reauthorized = try await authorizer.authorize(request, binding: binding)
        try Task.checkCancellation()
        guard reauthorized.url == authorized.url, reauthorized.httpMethod == authorized.httpMethod,
              reauthorized.httpBody == authorized.httpBody, !reauthorized.httpShouldHandleCookies,
              reauthorized.value(forHTTPHeaderField: "Authorization") == authorized.value(forHTTPHeaderField: "Authorization") else {
            throw NativeWebhookClientError.scopeChanged
        }
        // A gateway/server failure can follow a committed mutation. Keep the
        // original identity recoverable even when the error body looks definite.
        if method != .get, (500...599).contains(status) {
            throw NativeWebhookClientError.resultUnknown(traceID: nil)
        }
        guard data.count <= 4 * 1024 * 1024 else { throw method == .get ? NativeWebhookClientError.invalidWire : .resultUnknown(traceID: nil) }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw method == .get ? NativeWebhookClientError.invalidWire : .resultUnknown(traceID: nil) }
        guard (200...299).contains(status), header.code == 200 else {
            if method != .get, (500...599).contains(header.code) {
                throw NativeWebhookClientError.resultUnknown(traceID: header.traceID)
            }
            let code = Self.safeCode(header.err)
            if code == "WEBHOOK_RESULT_UNKNOWN" { throw NativeWebhookClientError.resultUnknown(traceID: header.traceID) }
            if status == 401 || status == 403 || header.code == 401 || header.code == 403 {
                if status == 401 || header.code == 401 { authorizer.unauthorized(binding) }
                throw NativeWebhookClientError.denied(code: code, traceID: header.traceID)
            }
            if status == 409 || header.code == 409 { throw NativeWebhookClientError.conflict(code: code, traceID: header.traceID) }
            throw NativeWebhookClientError.rejected(status: status, code: code, traceID: header.traceID)
        }
        return data
    }
    private static func safeCode(_ value: String?) -> String {
        guard let value, value.range(of: "^[A-Z][A-Z0-9_]{0,63}$", options: .regularExpression) != nil else { return "WEBHOOK_REQUEST_REJECTED" }
        return value
    }
    private func envelope<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(Envelope<T>.self, from: data).data }
        catch { throw NativeWebhookClientError.invalidWire }
    }
    private func pageQuery(_ cursor: String?, limit: Int) throws -> [URLQueryItem] {
        guard (1...100).contains(limit) else { throw NativeWebhookClientError.invalidInput("LIMIT_INVALID") }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }; return query
    }
    private func validPage<Item: Decodable & Sendable & Identifiable>(_ page: NativeWebhookPage<Item>, limit: Int, previous: String?) throws where Item.ID: Hashable {
        guard page.list.count <= limit, Set(page.list.map(\.id)).count == page.list.count,
              !page.hasMore || (!page.list.isEmpty && page.nextCursor != nil && page.nextCursor != "" && page.nextCursor != previous) else {
            throw NativeWebhookClientError.invalidWire
        }
    }
    private func validate(_ resource: NativeWebhookResource, family: NativeWebhookFamily, context: NativeWebhookContext) throws {
        guard resource.ownerType == "CLUB", resource.ownerID == context.binding.scope.ownerID,
              resource.channelID == context.binding.scope.channelID, resource.revision > 0, resource.keyVersion > 0 else {
            throw NativeWebhookClientError.invalidWire
        }
        if family == .subscription {
            guard resource.events != nil else { throw NativeWebhookClientError.invalidWire }
        } else if resource.allowedIPs == nil || resource.rateLimitPerMinute == nil { throw NativeWebhookClientError.invalidWire }
    }
    private struct Header: Decodable {
        let code: Int; let err: String?; let traceID: String?
        private enum CodingKeys: String, CodingKey { case code, err, traceID = "trace_id" }
    }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct ResourceWire: Decodable {
        let resource: NativeWebhookResource
        let replayed: Bool?; let secretShownOnce: Bool?; let urlShownOnce: Bool?
        let secret: String?; let signingSecret: String?; let url: String?; let oldTokenInvalidAfter: NativeWebhookServerTime?
        private enum CodingKeys: String, CodingKey {
            case replayed, secret, url, secretShownOnce = "secret_shown_once", urlShownOnce = "url_shown_once"
            case signingSecret = "signing_secret", oldTokenInvalidAfter = "old_token_invalid_after"
        }
        init(from decoder: Decoder) throws {
            resource = try NativeWebhookResource(from: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            replayed = try values.decodeIfPresent(Bool.self, forKey: .replayed)
            secretShownOnce = try values.decodeIfPresent(Bool.self, forKey: .secretShownOnce)
            urlShownOnce = try values.decodeIfPresent(Bool.self, forKey: .urlShownOnce)
            secret = try values.decodeIfPresent(String.self, forKey: .secret)
            signingSecret = try values.decodeIfPresent(String.self, forKey: .signingSecret)
            url = try values.decodeIfPresent(String.self, forKey: .url)
            oldTokenInvalidAfter = try values.decodeIfPresent(NativeWebhookServerTime.self, forKey: .oldTokenInvalidAfter)
        }
    }
}
