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
        case frozen(MerchantSkuSaveJourney.Intent)
        case applied(requestID: String, skuID: Int64)
        case unknown(requestID: String)
        case failed(MerchantBusinessFailure)
    }

    private let service: MerchantBusinessService
    private let journal: any MerchantBusinessIntentStore
    private let journey = MerchantSkuSaveJourney()
    private let scope: MerchantBusinessScope
    @Published public private(set) var phase: Phase = .idle

    public init(service: MerchantBusinessService, journal: any MerchantBusinessIntentStore, scope: MerchantBusinessScope) {
        self.service = service
        self.journal = journal
        self.scope = scope
    }

    public func load(productID: Int, skuID: Int, edit: Edit, access: MerchantBusinessAccess, accountID: Int64, token: String) async {
        guard access.role == "MERCHANT_OWNER", accountID > 0, accountID != Int64(access.merchantID),
              Int64(scope.accountID) == accountID else {
            phase = .failed(.denied)
            return
        }
        let pendingRow: MerchantBusinessIntent?
        do { pendingRow = try matching(skuID: skuID, merchantID: access.merchantID) }
        catch { phase = .failed(.journal); return }
        if let pendingRow {
            phase = .unknown(requestID: pendingRow.requestID)
            return
        }
        do {
            let detail = try await service.read(.productDetail(productID: productID), access: access, token: token)
            guard let row = skuRow(detail, productID: productID, skuID: skuID) else {
                phase = .failed(.invalid)
                return
            }
            let requestID = "desk-" + UUID().uuidString.lowercased()
            guard let intent = journey.freeze(access: access, accountID: accountID, productID: Int64(productID),
                                               skuID: Int64(skuID), requestID: requestID, skuName: edit.skuName,
                                               price: edit.price, stock: edit.stock, originalPrice: edit.originalPrice,
                                               pic: edit.pic, bookable: edit.bookable, slotMinutes: edit.slotMinutes,
                                               capacityPerSlot: edit.capacityPerSlot, ruleVersion: row["ruleVersion"]?.integer) else {
                phase = .failed(.invalid)
                return
            }
            phase = .frozen(intent)
        } catch let error as MerchantBusinessFailure {
            phase = .failed(error)
        } catch {
            phase = .failed(.unknown)
        }
    }

    public func confirm(access: MerchantBusinessAccess, token: String) async {
        guard case .frozen(let intent) = phase else { return }
        guard access.role == "MERCHANT_OWNER", Int64(scope.accountID) != Int64(access.merchantID) else {
            phase = .failed(.denied)
            return
        }
        guard service.canExecuteSyntheticMutation else {
            phase = .failed(.disabled)
            return
        }
        let stored = storedIntent(intent, merchantID: access.merchantID)
        guard let sku = Int(exactly: intent.skuID) else {
            phase = .failed(.invalid)
            return
        }
        do {
            if try matching(skuID: sku, merchantID: access.merchantID) != nil {
                phase = .unknown(requestID: intent.requestID)
                return
            }
        } catch {
            phase = .failed(.journal)
            return
        }
        do {
            try journal.reserve(stored)
        } catch {
            phase = .unknown(requestID: intent.requestID)
            return
        }
        do {
            let receipt = try await service.execute(mutation(intent), requestID: intent.requestID, token: token)
            guard let skuID = appliedTarget(receipt.data, requestID: intent.requestID) else {
                phase = .unknown(requestID: intent.requestID)
                return
            }
            try journal.complete(stored)
            phase = .applied(requestID: intent.requestID, skuID: skuID)
        } catch {
            phase = .unknown(requestID: intent.requestID)
        }
    }

    public func reopen(skuID: Int, access: MerchantBusinessAccess, token: String) async {
        let pending: MerchantBusinessIntent
        do {
            guard let row = try matching(skuID: skuID, merchantID: access.merchantID) else { return }
            pending = row
        } catch {
            phase = .failed(.journal)
            return
        }
        do {
            let receipt = try await service.read(.receipt(requestID: pending.requestID), access: access, token: token)
            guard let target = appliedTarget(receipt, requestID: pending.requestID) else {
                phase = .unknown(requestID: pending.requestID)
                return
            }
            try journal.complete(pending)
            phase = .applied(requestID: pending.requestID, skuID: target)
        } catch let error as MerchantBusinessFailure {
            phase = .failed(error)
        } catch {
            phase = .unknown(requestID: pending.requestID)
        }
    }

    private func matching(skuID: Int, merchantID: Int) throws -> MerchantBusinessIntent? {
        guard skuID > 0 else { return nil }
        return try journal.intents().first { row in
            row.realm == scope.realm && row.accountID == scope.accountID && row.merchantID == merchantID
                && row.target == "sku:\(skuID)"
        }
    }

    private func storedIntent(_ intent: MerchantSkuSaveJourney.Intent, merchantID: Int) -> MerchantBusinessIntent {
        MerchantBusinessIntent(scope: scope, merchantID: merchantID, target: "sku:\(intent.skuID)", requestID: intent.requestID)
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

    private func appliedTarget(_ value: MerchantBusinessValue, requestID: String) -> Int64? {
        guard let object = value.object,
              object["requestId"]?.string == requestID,
              object["state"]?.string == "APPLIED",
              object["action"]?.string == "SKU_SAVE",
              object["targetType"]?.string == "pms_sku",
              let target = object["targetId"]?.integer, target > 0 else { return nil }
        return Int64(target)
    }
}
