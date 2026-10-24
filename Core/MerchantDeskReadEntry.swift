import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opens the existing desk reads: access, product list, detail, and the original receipt.
/// The original save stays the only writer and is not called. A nil production approval keeps it closed.
@MainActor public struct MerchantDeskReadEntry {
    public struct Opened: Equatable {
        public let productID: Int
        public let detail: MerchantBusinessValue
        public let receipt: MerchantBusinessValue?
    }

    private let service: MerchantBusinessService
    private let production: MerchantBusinessProductionFactory?

    public init(service: MerchantBusinessService, production: MerchantBusinessProductionFactory? = nil) {
        self.service = service
        self.production = production
    }

    /// The product id must be one returned by the list. That same id is the detail id.
    /// A receipt is returned only when its request id is the one that was read.
    public func open(productID: Int, requestID: String, token: String) async throws -> Opened? {
        let access = try await service.access(token: token)
        let listed = try await productIDs(access: access, token: token)
        guard listed.contains(productID) else { return nil }
        guard let detail = try await detail(productID: productID, access: access, token: token) else { return nil }
        let receipt = try await receipt(requestID: requestID, access: access, token: token)
        return Opened(productID: productID, detail: detail, receipt: receipt)
    }

    public func productIDs(access: MerchantBusinessAccess, token: String) async throws -> [Int] {
        let value = try await service.read(.products, access: access, token: token)
        guard let rows = value.array else { throw MerchantBusinessFailure.malformed }
        var ids: [Int] = []
        for row in rows {
            guard let id = row.object?["productId"]?.integer, id > 0, !ids.contains(id) else { continue }
            ids.append(id)
        }
        return ids
    }

    /// Detail is that product only when the payload id is the requested id.
    public func detail(productID: Int, access: MerchantBusinessAccess, token: String) async throws -> MerchantBusinessValue? {
        guard productID > 0 else { return nil }
        let value = try await service.read(.productDetail(productID: productID), access: access, token: token)
        guard value.object?["productId"]?.integer == productID else { return nil }
        return value
    }

    /// The original receipt read. Another request id on the payload is not returned.
    public func receipt(requestID: String, access: MerchantBusinessAccess, token: String) async throws -> MerchantBusinessValue? {
        let value = try await service.read(.receipt(requestID: requestID), access: access, token: token)
        guard value.object?["requestId"]?.string == MerchantSkuSaveJourney.javaTrim(requestID) else { return nil }
        return value
    }

    /// Does not call save. Nil approval leaves the original writer closed.
    public func saveStaysClosed(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool {
        guard let production else { return true }
        return production.service(for: mutation, merchantID: merchantID) == nil
    }
}
