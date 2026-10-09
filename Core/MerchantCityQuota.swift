import Foundation

/// Existing city-node/list numbers describe online-node capacity, not a permission grant.
public struct MerchantCityQuota: Equatable, Sendable {
    public enum State: Equatable, Sendable { case unknown, available, none, full }
    public let used: Int?
    public let maximum: Int?
    public let state: State
    public var canPlace: Bool { state == .available }

    public init(catalog: MerchantContentValue) {
        // Match the mini client's numeric, non-negative integer check. A string or
        // Boolean must never turn an unknown quota into permission to place a node.
        guard case .integer(let used) = catalog["used"], used >= 0,
              case .integer(let maximum) = catalog["max"], maximum >= 0 else {
            self.used = nil; self.maximum = nil; state = .unknown; return
        }
        self.used = used; self.maximum = maximum
        state = maximum == 0 ? .none : used >= maximum ? .full : .available
    }
}
