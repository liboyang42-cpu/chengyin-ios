import Foundation

/// Deployment metadata is independent of language. No endpoint has been approved yet.
enum RegionalLaunchConfiguration {
    static var market:RegionalMarket? {
        #if DEBUG
        let args=ProcessInfo.processInfo.arguments
        if let i=args.firstIndex(of:"--uitesting-market"),args.indices.contains(i+1) {
            return try? RegionalConfiguration.market(buildValue:args[i+1])
        }
        #endif
        return try? RegionalConfiguration.market(buildValue:Bundle.main.object(forInfoDictionaryKey:"QuestifyMarket") as? String)
    }
    static var configuration:RegionalConfiguration? {
        guard let market else { return nil }
        // A reviewed registry, never an allowlist synthesized from a runtime URL.
        let approved:[RegionalMarket:Set<String>]=[:]
        return try? RegionalConfiguration(market:market,
            baseURL:Bundle.main.object(forInfoDictionaryKey:"QuestifyAPIBaseURL") as? String,
            approvedBaseURLs:approved,verifiedCapabilities:[])
    }
    static func language(_ stored:String?)->AppLanguage {
        market?.language(storedValue:stored) ?? stored.map(AppLanguage.init(storedValue:)) ?? .system
    }
}
