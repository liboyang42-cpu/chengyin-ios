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
    private var generation: UInt64 = 0
    @Published public private(set) var phase: Phase = .idle
    /// Detail rule version after a successful receipt. It does not replace the receipt.
    @Published public private(set) var laterRuleVersion: Int?

    public init(service: MerchantBusinessService, journal: any MerchantBusinessIntentStore, scope: MerchantBusinessScope,
                production: @escaping @MainActor (MerchantBusinessMutation, Int) -> MerchantBusinessService? = { _, _ in nil }) {
        self.service = service
        self.journal = journal
        self.scope = scope
        self.production = production
    }

    /// Exit or cancel. A late result from this generation cannot clear the journal.
    public func retire() { generation &+= 1 }

    public func present(productID: Int, skuID: Int, access: MerchantBusinessAccess, accountID: Int64, token: String) async {
        guard access.role == "MERCHANT_OWNER", accountID > 0, accountID != Int64(access.merchantID),
              Int64(scope.accountID) == accountID else {
            phase = .failed(.denied)
            return
        }
        let started = generation
        do {
            if let pending = try matching(skuID: skuID, productID: productID, merchantID: access.merchantID) {
                guard same(started) else { return }
                phase = .unknown(requestID: pending.requestID)
                return
            }
            let detail = try await service.read(.productDetail(productID: productID), access: access, token: token)
            guard same(started) else { return }
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
        } catch let error as APIError where error == .unauthorized {
            if same(started) { retire() }
        } catch let error as MerchantBusinessFailure {
            if same(started) { phase = .failed(error) }
        } catch {
            if same(started) { phase = .failed(.unknown) }
        }
    }

    public func load(productID: Int, skuID: Int, edit: Edit, access: MerchantBusinessAccess, accountID: Int64, token: String) async {
        guard access.role == "MERCHANT_OWNER", accountID > 0, accountID != Int64(access.merchantID),
              Int64(scope.accountID) == accountID else {
            phase = .failed(.denied)
            return
        }
        let started = generation
        let pendingRow: MerchantBusinessIntent?
        do { pendingRow = try matching(skuID: skuID, productID: productID, merchantID: access.merchantID) }
        catch { if same(started) { phase = .failed(.journal) }; return }
        if let pendingRow {
            guard same(started) else { return }
            phase = .unknown(requestID: pendingRow.requestID)
            return
        }
        do {
            let detail = try await service.read(.productDetail(productID: productID), access: access, token: token)
            guard same(started) else { return }
            guard let product = detail.object, product["editable"]?.bool == true,
                  let row = skuRow(detail, productID: productID, skuID: skuID),
                  let kept = kept(row) else {
                phase = .failed(.invalid)
                return
            }
            let requestID = "desk-" + UUID().uuidString.lowercased()
            guard let intent = journey.freeze(access: access, accountID: accountID, productID: Int64(productID),
                                               skuID: Int64(skuID), requestID: requestID, skuName: edit.skuName,
                                               price: edit.price, stock: edit.stock, originalPrice: kept.originalPrice,
                                               pic: kept.pic, bookable: kept.bookable, slotMinutes: kept.slotMinutes,
                                               capacityPerSlot: kept.capacityPerSlot, ruleVersion: row["ruleVersion"]?.integer) else {
                phase = .failed(.invalid)
                return
            }
            phase = .frozen(intent)
        } catch let error as APIError where error == .unauthorized {
            if same(started) { retire() }
        } catch let error as MerchantBusinessFailure {
            if same(started) { phase = .failed(error) }
        } catch {
            if same(started) { phase = .failed(.unknown) }
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
        let writer = reviewed ?? service
        let stored = storedIntent(intent, merchantID: access.merchantID)
        guard let sku = Int(exactly: intent.skuID), let product = Int(exactly: intent.productID) else {
            phase = .failed(.invalid)
            return
        }
        do {
            if try matching(skuID: sku, productID: product, merchantID: access.merchantID) != nil {
                guard same(started) else { return }
                phase = .unknown(requestID: intent.requestID)
                return
            }
        } catch {
            if same(started) { phase = .failed(.journal) }
            return
        }
        do {
            try journal.reserve(stored)
        } catch {
            if same(started) { phase = .unknown(requestID: intent.requestID) }
            return
        }
        do {
            let receipt = try await writer.executeDeskSku(change, requestID: intent.requestID, token: token,
                                                           access: access, scope: scope, check: { [started] in
                guard started == self.generation else { throw MerchantBusinessFailure.stale }
            })
            guard same(started) else { return }
            guard appliedTarget(receipt.data, requestID: intent.requestID, skuID: intent.skuID) != nil else {
                phase = .unknown(requestID: intent.requestID)
                return
            }
            guard stored.merchantID == access.merchantID, stored.target == Self.target(skuID: sku, productID: product) else {
                phase = .unknown(requestID: intent.requestID)
                return
            }
            try journal.complete(stored)
            guard same(started) else { return }
            phase = .applied(requestID: intent.requestID, skuID: intent.skuID)
        } catch let error as APIError where error == .unauthorized {
            if same(started) {
                phase = .unknown(requestID: intent.requestID)
                retire()
            }
        } catch {
            if same(started) { phase = .unknown(requestID: intent.requestID) }
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
        do {
            let receipt = try await service.read(.receipt(requestID: pending.requestID), access: access, token: token)
            guard same(started) else { return }
            guard appliedTarget(receipt, requestID: pending.requestID, skuID: Int64(skuID)) != nil else {
                phase = .unknown(requestID: pending.requestID)
                return
            }
            try journal.complete(pending)
            guard same(started) else { return }
            phase = .applied(requestID: pending.requestID, skuID: Int64(skuID))
        } catch let error as APIError where error == .unauthorized {
            if same(started) { retire() }
        } catch let error as MerchantBusinessFailure {
            if same(started) { phase = .failed(error) }
        } catch {
            if same(started) { phase = .unknown(requestID: pending.requestID) }
        }
    }

    /// Reads the current detail after the original receipt. A later version stays a detail fact.
    public func noteLater(productID: Int, skuID: Int, access: MerchantBusinessAccess, token: String) async {
        guard case .applied = phase else { return }
        let started = generation
        do {
            let detail = try await service.read(.productDetail(productID: productID), access: access, token: token)
            guard same(started) else { return }
            laterRuleVersion = skuRow(detail, productID: productID, skuID: skuID)?["ruleVersion"]?.integer
        } catch let error as APIError where error == .unauthorized {
            if same(started) { retire() }
        } catch {
            return
        }
    }

    private func same(_ started: UInt64) -> Bool { started == generation }

    private func matching(skuID: Int, productID: Int, merchantID: Int) throws -> MerchantBusinessIntent? {
        guard skuID > 0, productID > 0 else { return nil }
        let target = Self.target(skuID: skuID, productID: productID)
        return try journal.intents().first { row in
            row.realm == scope.realm && row.accountID == scope.accountID && row.merchantID == merchantID
                && row.target == target
        }
    }

    private static func target(skuID: Int, productID: Int) -> String { "sku:\(skuID)|product:\(productID)" }

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
        guard let bookable = flag(row["bookable"]),
              let slot = row["slotMinutes"]?.integer,
              let capacity = row["capacityPerSlot"]?.integer else { return nil }
        return Kept(originalPrice: moneyText(row["originalPrice"]), pic: row["pic"]?.string,
                    bookable: bookable, slotMinutes: slot, capacityPerSlot: capacity)
    }

    private func flag(_ value: MerchantBusinessValue?) -> Bool? {
        if let bool = value?.bool { return bool }
        if value?.integer == 1 { return true }
        if value?.integer == 0 { return false }
        return nil
    }

    private func moneyText(_ value: MerchantBusinessValue?) -> String? {
        if value == nil || value == .null { return nil }
        return value?.numberText
    }
}
