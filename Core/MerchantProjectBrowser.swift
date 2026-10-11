import Foundation

/// Source Mini's two project kinds; Other is only a fallback for new server kinds.
/// Template management keeps its existing separate native destination.
public enum MerchantProjectBrowserTab: String, Equatable, CaseIterable {
    case topic, activity, other
    public var titleKey: String { "merchant.projectBrowser." + rawValue }
    public func contains(_ project: MerchantProject) -> Bool {
        switch self {
        case .topic: return project.bizType == "topic"
        case .activity: return project.bizType == "activity"
        case .other: return project.bizType != "topic" && project.bizType != "activity"
        }
    }
}

/// Presentation of an already authorized loaded page, never a new query or capability.
public struct MerchantProjectBrowser: Equatable {
    public let page: MerchantProjectPage
    public let tab: MerchantProjectBrowserTab
    public init(page: MerchantProjectPage, tab: MerchantProjectBrowserTab) { self.page = page; self.tab = tab }
    public var tabs: [MerchantProjectBrowserTab] {
        [.topic, .activity] + (page.rows.contains(where: MerchantProjectBrowserTab.other.contains) ? [.other] : [])
    }
    public func count(_ tab: MerchantProjectBrowserTab) -> Int { page.rows.filter(tab.contains).count }
    public var rows: [MerchantProject] {
        page.rows.enumerated().filter { tab.contains($0.element) }.sorted { lhs, rhs in
            let first = Self.rank(lhs.element), second = Self.rank(rhs.element)
            return first == second ? lhs.offset < rhs.offset : first < second
        }.map(\.element)
    }
    public var alternatives: [MerchantProjectBrowserTab] { tabs.filter { $0 != tab && count($0) > 0 } }
    public static func rank(_ project: MerchantProject) -> Int {
        switch project.state { case "rejected": return 0; case "draft": return 1; case "pending": return 2; default: return 9 }
    }
}

/// Server fields only. Displaying hosting/fulfillment facts does not permit edits,
/// verification, publishing, cancellation, refunds or reading another project's data.
public struct MerchantProjectCardFacts: Equatable {
    public enum Role: String { case host, fulfiller }
    public let role: Role?
    public let address: String?
    public let pendingVerifications: Int?
    public let attention: Bool
    public init(_ project: MerchantProject) {
        if project.bizType == "activity", project.ownerType == "merchant" { role = .fulfiller }
        else if ["topic", "activity"].contains(project.bizType), ["member", "club"].contains(project.ownerType ?? "") { role = .host }
        else { role = nil }
        let address = project.addressName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address.flatMap { $0.isEmpty ? nil : $0 }
        pendingVerifications = role == .fulfiller ? project.pendingVerifyCount : nil
        attention = MerchantProjectBrowser.rank(project) < 9
    }
}
