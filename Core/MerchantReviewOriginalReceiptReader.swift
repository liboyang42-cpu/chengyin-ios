import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Local original-input metadata, produced only when reserving a new reviewed command.
/// It grants no permission. Historical intents without it remain UNKNOWN.
public struct MerchantReviewReplyOriginal: Codable, Equatable {
    public enum Action: String, Codable {
        case reply = "MERCHANT_REVIEW_REPLIED"
        case update = "MERCHANT_REVIEW_REPLY_UPDATED"
        case delete = "MERCHANT_REVIEW_REPLY_DELETED"
    }
    public let version: Int
    public let action: Action
    init?(mutation: MerchantBusinessMutation) {
        guard case .review(_, _, let kind, _) = mutation else { return nil }
        version = 1
        switch kind {
        case .reply: action = .reply
        case .update: action = .update
        case .delete: action = .delete
        case .report: return nil
        }
    }
}
public struct MerchantReviewOriginalReceipt: Equatable {
    public enum State: String { case applied = "APPLIED", unknown = "UNKNOWN" }
    public let intent: MerchantBusinessIntent
    public let state: State
}

public struct MerchantReviewOriginalResolution: Equatable {
    public let receipt: MerchantReviewOriginalReceipt
    /// Current row facts only, never a snapshot of what the original reply said.
    public let current: MerchantReviewReplyRecovery.Result?
    public let journalCompleted: Bool
}

/// Separately reviewed read capability, off by default. Never dispatches a review
/// mutation, infers an action, or mints a host approval. Journal completion requires
/// a second default-off gate and a fresh, fully bound completion invocation.
@MainActor public final class MerchantReviewOriginalReceiptReader {
    private let reader: any MerchantBusinessReading
    private let journal: any MerchantBusinessIntentStore
    private let service: MerchantBusinessService
    private let transport: any HTTPTransport
    private let currentSession: () -> MerchantBusinessSession?
    private let enabled: () -> Bool
    private let completionEnabled: () -> Bool
    private let unauthorized: (MerchantBusinessSession) -> Void
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore,
                currentSession: @escaping () -> MerchantBusinessSession?,
                enabled: @escaping () -> Bool = { false },
                completionEnabled: @escaping () -> Bool = { false },
                onUnauthorized: @escaping (MerchantBusinessSession) -> Void = { _ in }) {
        service = .init(configuration: configuration, readTransport: transport)
        self.transport = transport; self.reader = reader; self.journal = journal
        self.currentSession = currentSession; self.enabled = enabled; self.completionEnabled = completionEnabled; unauthorized = onUnauthorized
    }
    public func read(_ intent: MerchantBusinessIntent) async throws -> MerchantReviewOriginalReceipt {
        try await resolve(intent, completing: false).receipt
    }
    /// Explicit local completion. Always obtains a new original receipt and current
    /// authorized projection; a previously returned receipt cannot be used as a ticket.
    public func complete(_ intent: MerchantBusinessIntent) async throws -> MerchantReviewOriginalResolution {
        guard completionEnabled() else { throw MerchantBusinessFailure.disabled }
        return try await resolve(intent, completing: true)
    }
    private func resolve(_ intent: MerchantBusinessIntent, completing: Bool) async throws -> MerchantReviewOriginalResolution {
        guard enabled() else { throw MerchantBusinessFailure.disabled }
        guard let original = intent.reviewOriginal, original.version == 1,
              intent.target.hasPrefix("review:"), let id = Int(intent.target.dropFirst(7)), id > 0,
              intent.target == "review:\(id)",
              intent.requestID.range(of: #"^[A-Za-z0-9._:-]{1,64}$"#, options: .regularExpression) != nil,
              !intent.requestID.contains("\n"), !intent.requestID.contains("\r") else { throw MerchantBusinessFailure.unknown }
        guard let captured = currentSession(), let scope = reader.scope,
              let authorization = reader.authorizationGeneration,
              let realm = reader.journalRealm,
              scope.accountID == captured.accountID, scope.epoch == captured.epoch,
              scope.realm == service.realm, intent.realm == realm,
              intent.accountID == captured.accountID else { throw MerchantBusinessFailure.stale }
        func check(requireJournal: Bool = true) throws {
            try Task.checkCancellation()
            guard enabled(), (!completing || completionEnabled()), reader.isConfigured, currentSession() == captured,
                  reader.scope == scope, reader.authorizationGeneration == authorization,
                  reader.journalRealm == realm else { throw MerchantBusinessFailure.stale }
            if requireJournal { guard try journal.intents().contains(intent) else { throw MerchantBusinessFailure.stale } }
        }
        try check()
        do {
            let access = try await service.access(token: captured.token)
            try check()
            guard access.merchantID == intent.merchantID else { throw MerchantBusinessFailure.stale }
            // Same permission required by MerchantReviewReplyReceiptService, not BASIC_READ.
            try access.require(["merchant:marketing:write"])
            var request = try service.makeRequest(.json("api/merchant/reviews/reply/receipt", [
                "reviewId": .string(String(id)), "action": .string(original.action.rawValue),
                "requestId": .string(intent.requestID)
            ]), token: captured.token)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false; request.timeoutInterval = 20
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            try check()
            let (data, status) = try await transport.send(request)
            try check()
            if status == 401 { throw APIError.unauthorized }
            if status == 403 { throw MerchantBusinessFailure.denied }
            guard status == 200 else { throw MerchantBusinessFailure.unknown }
            guard data.count <= 1_048_576,
                  let envelope = try JSONDecoder().decode(MerchantBusinessValue.self, from: data).object,
                  let value = try MerchantBusinessService.unwrap(envelope).object,
                  value["reviewId"]?.string == String(id),
                  value["action"]?.string == original.action.rawValue,
                  value["requestId"]?.string == intent.requestID,
                  let raw = value["state"]?.string,
                  let state = MerchantReviewOriginalReceipt.State(rawValue: raw) else {
                throw MerchantBusinessFailure.malformed
            }
            try check()
            let receipt = MerchantReviewOriginalReceipt(intent: intent, state: state)
            guard completing, state == .applied else {
                return .init(receipt: receipt, current: nil, journalCompleted: false)
            }
            var current: MerchantReviewReplyRecovery.Result?
            for page in 1...5 {
                let snapshot = try await reader.snapshot(.reviews(page: page), isCurrent: { (try? check()) != nil })
                try check()
                guard snapshot.access == access, snapshot.document.query == .reviews(page: page) else {
                    throw MerchantBusinessFailure.stale
                }
                try snapshot.access.require(["merchant:marketing:write"])
                let rows = snapshot.document.rows.filter { $0.kind == .review && $0.id == String(id) }
                guard rows.count <= 1 else { throw MerchantBusinessFailure.malformed }
                if let row = rows.first { current = .current(row); break }
                current = .notInLoadedPages(hasMore: snapshot.document.hasMore)
                if !snapshot.document.hasMore { break }
            }
            try check()
            guard current != nil else { throw MerchantBusinessFailure.malformed }
            try journal.complete(intent)
            try check(requireJournal: false)
            guard try !journal.intents().contains(intent) else { throw MerchantBusinessFailure.journal }
            return .init(receipt: receipt, current: current, journalCompleted: true)
        } catch {
            try check()
            if error as? APIError == .unauthorized { unauthorized(captured) }
            throw error
        }
    }
}
