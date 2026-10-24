import Combine
import Foundation

/// Merchant desk SKU entry. Confirm calls the original save once.
/// Reopen reads the original receipt and does not save again.
@MainActor public final class MerchantDeskSkuDesk: ObservableObject {
    public struct Edit: Equatable, Sendable {
        public var skuName: String
        public var price: String
        public var stock: Int
        public var originalPrice: String?
        public var pic: String?
        public var bookable: Bool
        public var slotMinutes: Int
        public var capacityPerSlot: Int
        public init(skuName: String, price: String, stock: Int, originalPrice: String? = nil, pic: String? = nil,
                    bookable: Bool = false, slotMinutes: Int = 60, capacityPerSlot: Int = 0) {
            self.skuName = skuName
            self.price = price
            self.stock = stock
            self.originalPrice = originalPrice
            self.pic = pic
            self.bookable = bookable
            self.slotMinutes = slotMinutes
            self.capacityPerSlot = capacityPerSlot
        }
    }

    public enum Phase: Equatable {
        case idle
        case editing(Edit)
        case frozen(MerchantSkuSaveJourney.Intent)
        case applied(requestID: String, skuID: Int64)
        case unknown(requestID: String)
        case failed(MerchantBusinessFailure)
    }

    private let service: MerchantBusinessService
    private let journal: any MerchantBusinessIntentStore
    private let journey = MerchantSkuSaveJourney()
    private let scope: MerchantBusinessScope
    private let production: @MainActor (MerchantBusinessMutation, Int) -> MerchantBusinessService?
    private let currentSession: @MainActor () -> MerchantBusinessSession?
    private let authorizationGeneration: @MainActor () -> UUID?
    private let onUnauthorized: @MainActor (MerchantBusinessSession) -> Void
    private var generation: UInt64 = 0
    @Published public private(set) var phase: Phase = .idle
    /// Detail rule version after a successful receipt. It does not replace the receipt.
    @Published public private(set) var laterRuleVersion: Int?
    private var sourceDetail: MerchantBusinessValue?
    private var baselineName: String?
    private var baselineStock: Int?
    private var baselineRuleVersion: Int?

    public init(service: MerchantBusinessService, journal: any MerchantBusinessIntentStore, scope: MerchantBusinessScope,
                production: @escaping @MainActor (MerchantBusinessMutation, Int) -> MerchantBusinessService? = { _, _ in nil },
                currentSession: @escaping @MainActor () -> MerchantBusinessSession? = { nil },
                authorizationGeneration: @escaping @MainActor () -> UUID? = { nil },
                onUnauthorized: @escaping @MainActor (MerchantBusinessSession) -> Void = { _ in }) {
        self.service = service
        self.journal = journal
        self.scope = scope
        self.production = production
        self.currentSession = currentSession
        self.authorizationGeneration = authorizationGeneration
        self.onUnauthorized = onUnauthorized
    }

    /// Exit or cancel. A late result from this generation cannot clear the journal or reuse the frozen detail.
    public func retire() {
        generation &+= 1
        sourceDetail = nil
        if case .frozen = phase { phase = .idle }
    }

    public func present(productID: Int, skuID: Int, access: MerchantBusinessAccess, accountID: Int64, token: String) async {
        guard access.role == "MERCHANT_OWNER", accountID > 0, accountID != Int64(access.merchantID),
              Int64(scope.accountID) == accountID else {
            phase = .failed(.denied)
            return
        }
        let started = generation
        guard let (capturedSession, capturedAuthorization) = boundIdentity(token) else {
            phase = .failed(.stale)
            return
        }
        do {
            if let pending = try matching(skuID: skuID, productID: productID, merchantID: access.merchantID) {
                guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
                phase = .unknown(requestID: pending.requestID)
                return
            }
            let detail = try await service.read(.productDetail(productID: productID), access: access, token: capturedSession.token)
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            guard let product = detail.object, product["editable"]?.bool == true,
                  let row = skuRow(detail, productID: productID, skuID: skuID),
                  let kept = kept(row),
                  let name = row["skuName"]?.string, !name.isEmpty,
                  let price = row["price"]?.numberText, !price.isEmpty,
                  let stock = row["stock"]?.integer else {
                phase = .failed(.invalid)
                return
            }
            phase = .editing(Edit(skuName: name, price: price, stock: stock, originalPrice: kept.originalPrice,
                                  pic: kept.pic, bookable: kept.bookable, slotMinutes: kept.slotMinutes,
                                  capacityPerSlot: kept.capacityPerSlot))
            sourceDetail = detail
            baselineName = name
            baselineStock = stock
            baselineRuleVersion = missing(row, "ruleVersion") ? nil : strictNumber(row["ruleVersion"])
        } catch let error as APIError where error == .unauthorized {
            retireCapturedUnauthorized(started, capturedSession)
        } catch let error as MerchantBusinessFailure {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(error) }
        } catch {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(.unknown) }
        }
    }

    public func load(productID: Int, skuID: Int, edit: Edit, access: MerchantBusinessAccess, accountID: Int64, token: String) async {
        guard access.role == "MERCHANT_OWNER", accountID > 0, accountID != Int64(access.merchantID),
              Int64(scope.accountID) == accountID else {
            phase = .failed(.denied)
            return
        }
        let started = generation
        guard let (capturedSession, capturedAuthorization) = boundIdentity(token) else {
            phase = .failed(.stale)
            return
        }
        let pendingRow: MerchantBusinessIntent?
        do { pendingRow = try matching(skuID: skuID, productID: productID, merchantID: access.merchantID) }
        catch { if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(.journal) }; return }
        if let pendingRow {
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            phase = .unknown(requestID: pendingRow.requestID)
            return
        }
        do {
            let detail: MerchantBusinessValue
            if let sourceDetail {
                detail = sourceDetail
            } else {
                detail = try await service.read(.productDetail(productID: productID), access: access, token: capturedSession.token)
                guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
                sourceDetail = detail
            }
            guard detail.object?["editable"]?.bool == true,
                  let row = skuRow(detail, productID: productID, skuID: skuID),
                  let kept = kept(row),
                  let name = row["skuName"]?.string else {
                phase = .failed(.invalid)
                return
            }
            baselineName = name
            baselineStock = row["stock"]?.integer
            baselineRuleVersion = missing(row, "ruleVersion") ? nil : strictNumber(row["ruleVersion"])
            let requestID = "desk-" + UUID().uuidString.lowercased()
            guard let intent = journey.freeze(access: access, accountID: accountID, productID: Int64(productID),
                                               skuID: Int64(skuID), requestID: requestID, skuName: edit.skuName,
                                               price: edit.price, stock: edit.stock, originalPrice: kept.originalPrice,
                                               pic: kept.pic, bookable: kept.bookable, slotMinutes: kept.slotMinutes,
                                               capacityPerSlot: kept.capacityPerSlot,
                                               ruleVersion: missing(row, "ruleVersion") ? nil : strictNumber(row["ruleVersion"])) else {
                phase = .failed(.invalid)
                return
            }
            phase = .frozen(intent)
        } catch let error as APIError where error == .unauthorized {
            retireCapturedUnauthorized(started, capturedSession)
        } catch let error as MerchantBusinessFailure {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(error) }
        } catch {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(.unknown) }
        }
    }

    public func confirm(access: MerchantBusinessAccess, token: String) async {
        guard case .frozen(let intent) = phase else { return }
        guard access.role == "MERCHANT_OWNER", Int64(scope.accountID) != Int64(access.merchantID) else {
            phase = .failed(.denied)
            return
        }
        let started = generation
        guard same(started) else { return }
        let change = mutation(intent)
        let reviewed = production(change, access.merchantID)
        if reviewed == nil, !service.canExecuteSyntheticMutation {
            phase = .failed(.disabled)
            return
        }
        if reviewed != nil {
            guard journal.isDurable, currentSession() != nil, authorizationGeneration() != nil else {
                phase = .failed(.disabled)
                return
            }
        }
        guard let (capturedSession, capturedAuthorization) = boundIdentity(token) else {
            phase = .failed(.stale)
            return
        }
        let stored = storedIntent(intent, merchantID: access.merchantID)
        guard let sku = Int(exactly: intent.skuID), let product = Int(exactly: intent.productID),
              let detail = sourceDetail else {
            phase = .failed(.invalid)
            return
        }
        do {
            let fresh = try await service.read(.productDetail(productID: product), access: access, token: capturedSession.token)
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            guard fresh.object?["editable"]?.bool == true,
                  let row = skuRow(fresh, productID: product, skuID: sku),
                  row["skuName"]?.string == baselineName,
                  row["stock"]?.integer == baselineStock,
                  row["ruleVersion"]?.integer == baselineRuleVersion else {
                phase = .failed(.conflict)
                return
            }
        } catch let error as APIError where error == .unauthorized {
            retireCapturedUnauthorized(started, capturedSession)
            return
        } catch {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(.unknown) }
            return
        }
        do {
            if try matching(skuID: sku, productID: product, merchantID: access.merchantID) != nil {
                guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
                phase = .unknown(requestID: intent.requestID)
                return
            }
        } catch {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(.journal) }
            return
        }
        let fence: () throws -> Void = { [started] in
            try Task.checkCancellation()
            guard started == self.generation else { throw MerchantBusinessFailure.stale }
            guard self.currentSession() == capturedSession else { throw MerchantBusinessFailure.stale }
            if let capturedAuthorization, self.authorizationGeneration() != capturedAuthorization { throw MerchantBusinessFailure.stale }
        }
        do {
            let receipt: MerchantBusinessReceipt
            if let writer = reviewed {
                receipt = try await MerchantBusinessCoordinator.reserveDeskSkuThenDispatch(
                    journal: journal, mutation: change, intent: stored, detail: detail, access: access, scope: scope,
                    authorizationGeneration: capturedAuthorization, reader: service, service: writer,
                    token: capturedSession.token, check: fence)
            } else {
                try journal.reserve(stored)
                receipt = try await service.executeDeskSku(change, requestID: intent.requestID, token: capturedSession.token,
                                                           access: access, scope: scope, reserved: stored, detail: detail,
                                                           authorizationGeneration: capturedAuthorization, check: fence)
            }
            guard !Task.isCancelled, identityHolds(started, capturedSession, capturedAuthorization) else { return }
            guard appliedTarget(receipt.data, requestID: intent.requestID, skuID: intent.skuID) != nil else {
                phase = .unknown(requestID: intent.requestID)
                return
            }
            guard stored.merchantID == access.merchantID, stored.target == Self.target(skuID: sku, productID: product) else {
                phase = .unknown(requestID: intent.requestID)
                return
            }
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            try journal.complete(stored)
            phase = .applied(requestID: intent.requestID, skuID: intent.skuID)
        } catch is CancellationError {
            return
        } catch let error as APIError where error == .unauthorized {
            if same(started) { phase = .unknown(requestID: intent.requestID) }
            if currentSession() == capturedSession {
                onUnauthorized(capturedSession)
                if same(started) { retire() }
            }
        } catch {
            if Task.isCancelled { return }
            let stillReserved = (try? matching(skuID: sku, productID: product, merchantID: access.merchantID)) != nil
            if MerchantMutationFailureDisposition.provesNoDispatch(error) {
                if stillReserved { try? journal.complete(stored) }
                if identityHolds(started, capturedSession, capturedAuthorization) {
                    phase = .failed(error as? MerchantBusinessFailure ?? .disabled)
                }
                return
            }
            if identityHolds(started, capturedSession, capturedAuthorization) {
                phase = stillReserved ? .unknown(requestID: intent.requestID) : .failed(error as? MerchantBusinessFailure ?? .unknown)
            }
        }
    }

    public func reopen(productID: Int, skuID: Int, access: MerchantBusinessAccess, token: String) async {
        let started = generation
        let pending: MerchantBusinessIntent
        do {
            guard let row = try matching(skuID: skuID, productID: productID, merchantID: access.merchantID) else { return }
            pending = row
        } catch {
            if same(started) { phase = .failed(.journal) }
            return
        }
        guard let (capturedSession, capturedAuthorization) = boundIdentity(token) else {
            phase = .failed(.stale)
            return
        }
        do {
            let receipt = try await service.read(.receipt(requestID: pending.requestID), access: access, token: capturedSession.token)
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            guard appliedTarget(receipt, requestID: pending.requestID, skuID: Int64(skuID)) != nil else {
                phase = .unknown(requestID: pending.requestID)
                return
            }
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            try journal.complete(pending)
            phase = .applied(requestID: pending.requestID, skuID: Int64(skuID))
        } catch is CancellationError {
            return
        } catch let error as APIError where error == .unauthorized {
            if identityHolds(started, capturedSession, capturedAuthorization) {
                phase = .unknown(requestID: pending.requestID)
            }
            retireCapturedUnauthorized(started, capturedSession)
        } catch let error as MerchantBusinessFailure {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .failed(error) }
        } catch {
            if identityHolds(started, capturedSession, capturedAuthorization) { phase = .unknown(requestID: pending.requestID) }
        }
    }

    /// Reads the current detail after the original receipt. A later version stays a detail fact.
    public func noteLater(productID: Int, skuID: Int, access: MerchantBusinessAccess, token: String) async {
        guard case .applied = phase else { return }
        let started = generation
        guard let (capturedSession, capturedAuthorization) = boundIdentity(token) else {
            phase = .failed(.stale)
            return
        }
        do {
            let detail = try await service.read(.productDetail(productID: productID), access: access, token: capturedSession.token)
            guard identityHolds(started, capturedSession, capturedAuthorization) else { return }
            laterRuleVersion = skuRow(detail, productID: productID, skuID: skuID)?["ruleVersion"]?.integer
        } catch let error as APIError where error == .unauthorized {
            retireCapturedUnauthorized(started, capturedSession)
        } catch {
            return
        }
    }

    private func same(_ started: UInt64) -> Bool { started == generation }

    /// The request token is the captured session token. A different page token is not sent.
    private func boundIdentity(_ token: String) -> (MerchantBusinessSession, UUID?)? {
        guard let session = currentSession(), session.token == token,
              session.accountID == scope.accountID, session.epoch == scope.epoch else { return nil }
        return (session, authorizationGeneration())
    }

    private func identityHolds(_ started: UInt64, _ capturedSession: MerchantBusinessSession?, _ capturedAuthorization: UUID?) -> Bool {
        guard same(started), !Task.isCancelled, let capturedSession, currentSession() == capturedSession else { return false }
        if let capturedAuthorization, authorizationGeneration() != capturedAuthorization { return false }
        return true
    }

    /// 401 retires only the session whose token was sent. A replacement session is left alone.
    private func retireCapturedUnauthorized(_ started: UInt64, _ capturedSession: MerchantBusinessSession?) {
        guard let capturedSession, currentSession() == capturedSession else { return }
        onUnauthorized(capturedSession)
        if same(started) { retire() }
    }

    private func matching(skuID: Int, productID: Int, merchantID: Int) throws -> MerchantBusinessIntent? {
        guard skuID > 0, productID > 0 else { return nil }
        let target = Self.target(skuID: skuID, productID: productID)
        let legacy = "sku:\(skuID)"
        return try journal.intents().first { row in
            row.realm == scope.realm && row.accountID == scope.accountID && row.merchantID == merchantID
                && (row.target == target || row.target == legacy)
        }
    }

    private static func target(skuID: Int, productID: Int) -> String { "sku:\(skuID)" }

    private func storedIntent(_ intent: MerchantSkuSaveJourney.Intent, merchantID: Int) -> MerchantBusinessIntent {
        MerchantBusinessIntent(scope: scope, merchantID: merchantID,
                               target: Self.target(skuID: Int(intent.skuID), productID: Int(intent.productID)),
                               requestID: intent.requestID)
    }

    private func mutation(_ intent: MerchantSkuSaveJourney.Intent) -> MerchantBusinessMutation {
        .saveSku(productID: Int(intent.productID), skuID: Int(intent.skuID), name: intent.skuName,
                 price: intent.price, stock: intent.stock, originalPrice: intent.originalPrice, pic: intent.pic,
                 bookable: intent.bookable, slotMinutes: intent.slotMinutes, capacityPerSlot: intent.capacityPerSlot,
                 ruleVersion: intent.ruleVersion)
    }

    private func skuRow(_ detail: MerchantBusinessValue, productID: Int, skuID: Int) -> MerchantBusinessObject? {
        guard let product = detail.object, product["productId"]?.integer == productID,
              let skus = product["skus"]?.array else { return nil }
        return skus.compactMap(\.object).first { $0["skuId"]?.integer == skuID }
    }

    private func appliedTarget(_ value: MerchantBusinessValue, requestID: String, skuID: Int64) -> Int64? {
        guard let object = value.object,
              object["requestId"]?.string == requestID,
              object["state"]?.string == "APPLIED",
              object["action"]?.string == "SKU_SAVE",
              object["targetType"]?.string == "pms_sku",
              let target = object["targetId"]?.integer, Int64(target) == skuID else { return nil }
        return Int64(target)
    }

    private struct Kept {
        let originalPrice: String?
        let pic: String?
        let bookable: Bool
        let slotMinutes: Int
        let capacityPerSlot: Int
    }

    private func kept(_ row: MerchantBusinessObject) -> Kept? {
        let keys = ["bookable", "slotMinutes", "capacityPerSlot", "ruleVersion"]
        if keys.allSatisfy({ missing(row, $0) }) {
            return Kept(originalPrice: moneyText(row["originalPrice"]), pic: row["pic"]?.string,
                        bookable: false, slotMinutes: 60, capacityPerSlot: 0)
        }
        guard let bookable = flag(row["bookable"]),
              let slot = strictNumber(row["slotMinutes"]),
              let capacity = strictNumber(row["capacityPerSlot"]),
              strictNumber(row["ruleVersion"]) != nil else { return nil }
        return Kept(originalPrice: moneyText(row["originalPrice"]), pic: row["pic"]?.string,
                    bookable: bookable, slotMinutes: slot, capacityPerSlot: capacity)
    }

    private func missing(_ row: MerchantBusinessObject, _ key: String) -> Bool {
        row[key] == nil || row[key] == .null
    }

    private func strictNumber(_ value: MerchantBusinessValue?) -> Int? {
        guard case .number(let amount) = value else { return nil }
        let whole = NSDecimalNumber(decimal: amount).intValue
        guard Decimal(whole) == amount else { return nil }
        return whole
    }

    private func flag(_ value: MerchantBusinessValue?) -> Bool? {
        if let bool = value?.bool { return bool }
        guard let whole = strictNumber(value), whole == 0 || whole == 1 else { return nil }
        return whole == 1
    }

    private func moneyText(_ value: MerchantBusinessValue?) -> String? {
        if value == nil || value == .null { return nil }
        return value?.numberText
    }
}
