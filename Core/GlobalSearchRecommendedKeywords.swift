import Foundation

/// Mini-program search2 "推荐搜索": a fixed, local keyword list (no API). The words are
/// China-market content terms, so other markets show no recommendations rather than translations.
public enum GlobalSearchRecommendedKeywords {
    public static let china = ["骑行", "城市", "外滩", "书店", "美术馆", "摄影", "苏州河", "菜场"]

    public static func keywords(for market: RegionalMarket?) -> [String] {
        market == .china ? china : []
    }
}
