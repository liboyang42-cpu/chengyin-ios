import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WalletCommerceScope: Equatable, Hashable {
    public let namespace: String
    public let accountID: Int
    public let epoch: UUID
    public init(namespace: String, accountID: Int, epoch: UUID) {
        self.namespace = namespace; self.accountID = accountID; self.epoch = epoch
    }
    // Epoch intentionally excluded from durable replay owner; restart/login must not unlock.
    var owner: String { "wallet:\(namespace.utf8.count):\(namespace):\(accountID)" }
    var valid: Bool { !namespace.isEmpty && accountID > 0 }
}
public enum WalletCommerceSafetyError: Error, Equatable {
    case unavailable, staleSession, reviewRequired, unresolvedOutcome, changedPreview
}
public struct WalletCommerceVisibility {
    public var assets = false
    public var income = false
    public var points = false
    public var mall = false
    public var withdrawalRecords = false
    public init() {}
    // Host copies existing source feature flags. This module never changes navigation policy.
}
@MainActor public final class WalletCommerceReader {
    private let service: WalletCommerceService?
    private let session: () -> (scope: WalletCommerceScope, token: String)?
    private let onUnauthorized: (WalletCommerceScope) -> Void
    public init(service: WalletCommerceService? = nil, onUnauthorized: @escaping (WalletCommerceScope) -> Void = { _ in }, session: @escaping () -> (scope: WalletCommerceScope, token: String)?) {
        self.service = service; self.session = session; self.onUnauthorized = onUnauthorized
    }
    /// Reuses this reader's authority while narrowing it to one retained presentation.
    /// Returning nil from the captured session also suppresses stale 401 callbacks.
    public func restrictedToPresentation(_ isCurrent: @escaping () -> Bool) -> WalletCommerceReader {
        WalletCommerceReader(service: service, onUnauthorized: { [self] scope in
            guard isCurrent() else { return }
            onUnauthorized(scope)
        }, session: { [self] in
            guard isCurrent() else { return nil }
            return session()
        })
    }
    public var scope: WalletCommerceScope? { session()?.scope }
    public var isConfigured: Bool { service != nil }
    public func checkout(cartIDs: [Int]) async throws -> WalletCheckoutSnapshot {
        guard let scope else { throw APIError.unauthorized }
        let preview = try await read { try await $0.checkout(cartIDs: cartIDs, token: $1) }
        return WalletCheckoutSnapshot(scope: scope, cartIDs: cartIDs, preview: preview, created: Date())
    }
    public func read<T>(_ operation: (WalletCommerceService, String) async throws -> T) async throws -> T {
        guard let service else { throw WalletCommerceSafetyError.unavailable }
        guard let captured = session(), captured.scope.valid else { throw APIError.unauthorized }
        let value: T
        do { value = try await operation(service.bound(to: captured.scope), captured.token) }
        catch {
            try Task.checkCancellation()
            guard let current = session(), current.scope == captured.scope, current.token == captured.token else { throw WalletCommerceSafetyError.staleSession }
            if (error as? APIError) == .unauthorized { onUnauthorized(captured.scope) }
            throw error
        }
        try Task.checkCancellation()
        guard let current = session(), current.scope == captured.scope, current.token == captured.token else { throw WalletCommerceSafetyError.staleSession }
        return value
    }
}
public enum WalletCommerceCommand: Equatable {
    case add(productID: Int, skuID: Int, quantity: Int)
    case update(cartID: Int, skuID: Int, quantity: Int)
    case delete(cartID: Int)
    case redeem(cartIDs: [Int], remark: String, addressID: Int)
    public var path: String {
        switch self {
        case .add: return "api/cart/cart/add"
        case .update: return "api/cart/update"
        case .delete: return "api/cart/delete"
        case .redeem: return "api/cart/order/settlement"
        }
    }
    public func fields() throws -> [String: String] {
        switch self {
        case .add(let product, let sku, let quantity):
            guard product > 0, sku > 0, quantity > 0 else { throw APIError.invalidRequest }
            return ["product_id": String(product), "sku_id": String(sku), "quantity": String(quantity), "is_buy": "0"]
        case .update(let cart, let sku, let quantity):
            guard cart > 0, sku > 0, quantity > 0 else { throw APIError.invalidRequest }
            return ["cart_id": String(cart), "sku_id": String(sku), "quantity": String(quantity)]
        case .delete(let cart):
            guard cart > 0 else { throw APIError.invalidRequest }; return ["cartids": String(cart)]
        case .redeem(let ids, let remark, let address):
            guard address > 0 else { throw APIError.invalidRequest }
            return ["cartids": try Self.cartIDs(ids), "remark": remark, "addressid": String(address)]
        }
    }
    static func cartIDs(_ ids: [Int]) throws -> String {
        guard !ids.isEmpty, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { throw APIError.invalidRequest }
        return ids.map(String.init).joined(separator: ",")
    }
}
/// Reviews bind the entire immutable command and checkout snapshot to account + session epoch.
public struct WalletCheckoutSnapshot: Equatable {
    public let scope: WalletCommerceScope
    public let cartIDs: [Int]
    public let preview: WalletCheckoutPreview
    let created: Date
}
public struct WalletCommerceReview: Equatable {
    fileprivate let id: UUID
    public let scope: WalletCommerceScope
    public let command: WalletCommerceCommand
    public let preview: WalletCheckoutPreview?
    fileprivate let created: Date
}
/// Never installed in the app factory. Default live gate is closed, including cart mutations.
/// Test suites inject fake HTTPTransport; endpoint approval alone never opens the gate.
@MainActor public final class WalletCommerceDormantAdapter {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let approval: OperationEndpointApproval?
    private let enableReviewedWrites: Bool
    private let currentScope: () -> WalletCommerceScope?
    private let now: () -> Date
    private var reviewed: WalletCommerceReview?
    private let lockTarget = "cart-and-redemption" // Account-wide to block overlapping cart attempts.
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                journal: any OperationPendingJournal, approval: OperationEndpointApproval? = nil,
                enableReviewedWrites: Bool = false, currentScope: @escaping () -> WalletCommerceScope?,
                now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.transport = transport; self.journal = journal
        self.approval = approval; self.enableReviewedWrites = enableReviewedWrites
        self.currentScope = currentScope; self.now = now
    }
    public func review(_ command: WalletCommerceCommand, snapshot: WalletCheckoutSnapshot? = nil) throws -> WalletCommerceReview {
        _ = try command.fields()
        guard let scope = currentScope(), scope.valid else { throw APIError.unauthorized }
        guard try journal.pending(ownerKey: scope.owner, targetKey: lockTarget) == nil else { throw WalletCommerceSafetyError.unresolvedOutcome }
        let preview = snapshot?.preview
        if case .redeem(let ids, _, let addressID) = command {
            guard let snapshot, snapshot.scope == scope, snapshot.cartIDs == ids,
                  now().timeIntervalSince(snapshot.created) >= 0,
                  now().timeIntervalSince(snapshot.created) < 120, let preview, preview.address?.id == addressID, preview.hasEnoughPoints == true,
                  let products = preview.productList,
                  Set(products.map(\.id)) == Set(ids), products.count == ids.count,
                  products.allSatisfy({ $0.quantity > 0 && $0.price != nil }),
                  preview.productAmount != nil, preview.deliveryFee != nil, preview.taxFee != nil else {
                throw WalletCommerceSafetyError.changedPreview
            }
        }
        let value = WalletCommerceReview(id: UUID(), scope: scope, command: command, preview: preview, created: now())
        reviewed = value; return value
    }
    public func cancelReview() { reviewed = nil }
    /// Returns an order reference only for a confirmed redemption receipt. It is not payment,
    /// fulfillment, refund or payout evidence. Failures after dispatch retain the durable lock.
    public func execute(_ review: WalletCommerceReview, token: String) async throws -> Int? {
        guard enableReviewedWrites else { throw APIError.notConfigured }
        guard reviewed == review, now().timeIntervalSince(review.created) >= 0,
              now().timeIntervalSince(review.created) < 120 else { throw WalletCommerceSafetyError.reviewRequired }
        guard currentScope() == review.scope else { throw WalletCommerceSafetyError.staleSession }
        guard approval?.allows(configuration: configuration, namespace: review.scope.namespace,
                               accountID: review.scope.accountID, path: review.command.path) == true else { throw APIError.notConfigured }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(review.command.path), fields: review.command.fields(), token: token)
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        guard try journal.pending(ownerKey: review.scope.owner, targetKey: lockTarget) == nil else { throw WalletCommerceSafetyError.unresolvedOutcome }
        try Task.checkCancellation()
        let pending = OperationPendingRecord(ownerKey: review.scope.owner, targetKey: lockTarget)
        try journal.write(pending) // Persist before first possible network dispatch; no body or token stored.
        reviewed = nil
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard currentScope() == review.scope else { throw WalletCommerceSafetyError.staleSession }
        try WalletCommerceService.validateEnvelope(data, status: status)
        var orderID: Int?
        if case .redeem = review.command {
            struct Receipt: Decodable {
                let data: Int
                enum CodingKeys: String, CodingKey { case data }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    if let id = try? c.decode(Int.self, forKey: .data) { data = id }
                    else if let id = Int(try c.decode(String.self, forKey: .data)) { data = id }
                    else { throw APIError.malformedResponse }
                }
            }
            let receipt = try JSONDecoder().decode(Receipt.self, from: data)
            guard receipt.data > 0 else { throw APIError.malformedResponse }; orderID = receipt.data
        }
        try journal.clear(pending)
        return orderID
    }
    // No public reset/force retry. Source supplies no idempotency/receipt correlation endpoint.
    // Bank withdrawal is a separate, explicitly requested app flow in BankWithdrawalAdapter.
    // This commerce adapter remains unrelated to bank operations.
}

/// Memory-only selection of an existing income row. No detail endpoint or payout state is invented.
public struct WalletIncomeDetailSelection: Identifiable {
    public let id = UUID()
    fileprivate let row: WalletLedgerRow
    fileprivate let scope: WalletCommerceScope
    fileprivate let kind: WalletLedgerKind
    fileprivate let snapshotID: UUID
    fileprivate let readerID: ObjectIdentifier
}

/// Stable ordering, raw-page pagination and no advance on failure. Filtering is only presentation.
@MainActor public final class WalletLedgerPager {
    public private(set) var rows: [WalletLedgerRow] = []
    public private(set) var hasMore = true
    public private(set) var isLoading = false
    public private(set) var failed = false
    public private(set) var requiresLogin = false
    public private(set) var unavailable = false
    public private(set) var hasLoadedPage = false
    public private(set) var loadedScope: WalletCommerceScope?
    private var requestedScope: WalletCommerceScope?
    private var requestedKind: WalletLedgerKind?
    private var requestedReaderID: ObjectIdentifier?
    private var nextPage = 1
    private var snapshotID = UUID()
    private var generation = UUID()
    public init() {}
    public func cancel() { generation = UUID(); snapshotID = UUID(); isLoading = false }
    public func reset() {
        generation = UUID(); snapshotID = UUID(); rows = []; nextPage = 1; hasMore = true
        isLoading = false; failed = false; requiresLogin = false; unavailable = false
        hasLoadedPage = false; loadedScope = nil; requestedScope = nil; requestedKind = nil; requestedReaderID = nil
    }
    /// Selection is admitted only from this pager's successfully loaded, current-owner income page.
    public func incomeDetail(rowID: Int, reader: WalletCommerceReader) -> WalletIncomeDetailSelection? {
        guard requestedReaderID == ObjectIdentifier(reader), let kind = requestedKind, case .income = kind,
              hasLoadedPage, !requiresLogin, !unavailable,
              let scope = loadedScope, scope == reader.scope, reader.isConfigured,
              rowID > 0, let row = rows.first(where: { $0.id == rowID }) else { return nil }
        return WalletIncomeDetailSelection(row: row, scope: scope, kind: kind, snapshotID: snapshotID, readerID: ObjectIdentifier(reader))
    }
    /// A refreshed page, changed filter, revoked read lease, or another authentication epoch retires it.
    public func incomeDetailRow(_ selection: WalletIncomeDetailSelection, reader: WalletCommerceReader) -> WalletLedgerRow? {
        guard hasLoadedPage, !requiresLogin, !unavailable, reader.isConfigured,
              requestedReaderID == ObjectIdentifier(reader), selection.readerID == ObjectIdentifier(reader), selection.snapshotID == snapshotID, selection.kind == requestedKind,
              selection.scope == loadedScope, selection.scope == reader.scope,
              rows.contains(selection.row) else { return nil }
        return selection.row
    }
    public func load(reader: WalletCommerceReader, kind: WalletLedgerKind) async {
        let scope = reader.scope
        // Bind before dispatch, not only after success: repeated first-page taps
        // must share the in-flight gate, while another owner/kind starts fresh.
        if requestedScope != scope || requestedKind != kind || requestedReaderID != ObjectIdentifier(reader) { reset() }
        requestedScope = scope; requestedKind = kind; requestedReaderID = ObjectIdentifier(reader)
        guard !isLoading, hasMore else { return }
        let captured = generation; let pageNumber = nextPage
        isLoading = true; failed = false; requiresLogin = false; unavailable = false
        defer { if generation == captured { isLoading = false } }
        do {
            let page = try await reader.read { try await $0.ledger(kind, page: pageNumber, token: $1) }
            guard generation == captured else { return }
            guard reader.scope == scope else { reset(); return }
            var seen = Set(rows.map(\.id)); let additional = page.rows.filter { seen.insert($0.id).inserted }
            if pageNumber > 1 && !page.rows.isEmpty && additional.isEmpty { throw APIError.malformedResponse }
            rows += additional
            nextPage += 1; hasMore = page.hasMore(loadedCount: rows.count)
            loadedScope = scope; hasLoadedPage = true
        } catch {
            guard generation == captured else { return }
            guard reader.scope == scope else { reset(); return }
            if error is CancellationError { return }
            if (error as? WalletCommerceSafetyError) == .staleSession { reset(); return }
            requiresLogin = (error as? APIError) == .unauthorized
            unavailable = (error as? APIError) == .notConfigured || (error as? WalletCommerceSafetyError) == .unavailable
            failed = true
            // Authorization failure invalidates the displayed snapshot. A retryable
            // network/business failure keeps earlier pages and the failed page number.
            if requiresLogin || unavailable {
                rows = []; loadedScope = nil; hasLoadedPage = false; nextPage = 1
            }
        }
    }
}

/// Exact read grant enforcement. This wrapper never accepts cart mutations or redemption.
public final class WalletCommerceApprovedReadTransport: HTTPTransport {
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval
    private let transport: any HTTPTransport
    private let currentSession: @MainActor () -> (scope: WalletCommerceScope, token: String)?
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval, transport: any HTTPTransport,
                currentSession: @escaping @MainActor () -> (scope: WalletCommerceScope, token: String)?) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.currentSession = currentSession
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        throw APIError.notConfigured // Unbound requests must never dispatch.
    }
    @MainActor public func send(_ request: URLRequest, scope: WalletCommerceScope, token: String) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let current = currentSession(), current.scope == scope, current.token == token,
              request.value(forHTTPHeaderField: "Authorization") == token else { throw WalletCommerceSafetyError.staleSession }
        let reads = ["api/user/info", "api/wallet/stages", "api/balance/list", "api/points/list", "api/user/points/list", "api/user/balance/list",
                     "api/points/result_list", "api/product/list", "api/product/info", "api/cart/list", "api/cart/settlement", "api/withdrawal/list"]
        guard request.httpMethod == "POST",
              let path = reads.first(where: { configuration.baseURL.appendingPathComponent($0) == request.url }),
              approval.allows(configuration: configuration, namespace: scope.namespace, accountID: scope.accountID, path: path) else { throw APIError.notConfigured }
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard let current = currentSession(), current.scope == scope, current.token == token else { throw WalletCommerceSafetyError.staleSession }; return response
    }
}
