import Foundation

/// P040 selects a single real home-data pool before taking three examples; it never mixes or seeds drafts.
public struct TemplateAuthoringIntroExamples: Equatable {
    public enum Pool: String, Equatable { case recommended, hot, latest }
    public struct SysCategory: Codable, Equatable, Sendable {
        public let categoryName: String?
        public init(categoryName: String? = nil) { self.categoryName = categoryName }
    }
    private struct CategoryEnvelope: Decodable {
        struct Item: Decodable { let sysCategoryList: [SysCategory]? }
        let recommendList: [Item]?
        let hotList: [Item]?
        let latestList: [Item]?
    }
    public static let maximum = 3
    public static let defaultCategoryName = "节点玩法"
    public let pool: Pool
    public let rows: [DiscoveryPlayTemplate]
    public let categoryNames: [String]
    public init(home: DiscoveryTemplateHome, categoryNames: [String]? = nil) {
        let source: [DiscoveryPlayTemplate]
        if !home.recommended.isEmpty { pool = .recommended; source = home.recommended }
        else if !home.hot.isEmpty { pool = .hot; source = home.hot }
        else { pool = .latest; source = home.latest }
        let selected = Array(source.prefix(Self.maximum))
        rows = selected
        self.categoryNames = (0..<selected.count).map { index in
            Self.normalizedCategoryName(categoryNames?.indices.contains(index) == true ? categoryNames?[index] : nil)
        }
    }
    public init(homeData: Data) throws {
        let home = try JSONDecoder().decode(DiscoveryTemplateHome.self, from: homeData)
        let selectedPool: Pool = !home.recommended.isEmpty ? .recommended : (!home.hot.isEmpty ? .hot : .latest)
        let decodedCategories = Self.decodeCategoryNames(from: homeData, pool: selectedPool)
        self.init(home: home, categoryNames: decodedCategories)
    }
    public func categoryName(at index: Int) -> String {
        categoryNames.indices.contains(index) ? categoryNames[index] : Self.defaultCategoryName
    }
    public static func categoryName(from sysCategoryList: [SysCategory]?) -> String {
        normalizedCategoryName(sysCategoryList?.first?.categoryName)
    }
    public static func normalizedCategoryName(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCategoryName : trimmed
    }
    public static func decodeCategoryNames(from homeData: Data, pool: Pool) -> [String] {
        guard let envelope = try? JSONDecoder().decode(CategoryEnvelope.self, from: homeData) else { return [] }
        let items: [CategoryEnvelope.Item]
        switch pool {
        case .recommended: items = envelope.recommendList ?? []
        case .hot: items = envelope.hotList ?? []
        case .latest: items = envelope.latestList ?? []
        }
        return items.prefix(maximum).map { categoryName(from: $0.sysCategoryList) }
    }
}
