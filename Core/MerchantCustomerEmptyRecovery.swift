import Foundation

/// Reason and recovery for an empty first CRM page, using only that response and
/// its applied query. Missing counts never mean zero; page-two navigation stays unchanged.
public struct MerchantCustomerEmptyRecovery: Equatable {
    public enum Kind: String { case search, searchInGroup, advanced, group, statisticsUnavailable, listUnavailable, noCustomers }
    public enum Action: String { case clearSearch, allGroups, clearAdvanced, retry }
    public let kind: Kind
    public let action: Action?
    public let appliedQuery: MerchantCustomerQuery

    public init?(document: MerchantBusinessDocument) {
        guard case .customers(let query) = document.query, query.page == 1, document.rows.isEmpty else { return nil }
        appliedQuery = query
        if !query.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kind = query.segment == "all" ? .search : .searchInGroup
            action = query.segment == "all" ? .clearSearch : .allGroups
        } else if query.tagID != nil || query.sourceType != nil || !(query.sourceStart ?? "").isEmpty || !(query.sourceEnd ?? "").isEmpty {
            kind = .advanced; action = .clearAdvanced
        } else if query.segment != "all" {
            kind = .group; action = .allGroups
        } else if let count = Self.count(document.summary["all"]) {
            kind = count > 0 ? .listUnavailable : .noCustomers
            action = count > 0 ? .retry : nil
        } else {
            kind = .statisticsUnavailable; action = .retry
        }
    }

    /// Mutate only the source action's named filters. Always restart at page one.
    public var recoveredQuery: MerchantCustomerQuery? {
        guard let action else { return nil }
        var result = appliedQuery; result.page = 1
        switch action {
        case .clearSearch: result.keyword = ""
        case .allGroups: result.segment = "all"
        case .clearAdvanced:
            result.tagID = nil; result.sourceType = nil; result.sourceStart = nil; result.sourceEnd = nil
        case .retry: break
        }
        return result
    }

    /// The native form has an explicit Apply button. Never discard unsubmitted edits
    /// when recovering results produced by an older applied query.
    public func matchesDraft(keyword: String, segment: String, sourceType: Int, tagID: Int,
                             sourceStart: String, sourceEnd: String) -> Bool {
        appliedQuery.keyword == keyword && appliedQuery.segment == segment &&
        (appliedQuery.sourceType ?? 0) == sourceType && (appliedQuery.tagID ?? 0) == tagID &&
        (appliedQuery.sourceStart ?? "") == sourceStart && (appliedQuery.sourceEnd ?? "") == sourceEnd
    }

    private static func count(_ value: MerchantBusinessValue?) -> Decimal? {
        let result: Decimal?
        switch value {
        case .number(let number): result = number
        case .string(let string):
            let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
            result = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
        guard let result, !result.isNaN, result >= 0 else { return nil }
        return result
    }
}
