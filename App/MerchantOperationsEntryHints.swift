import Foundation

/// Mini-program pages/merchant/decor entry subtitles (index.wxml:69-119, coop view 187-323),
/// mapped onto the iOS 品牌中心 destinations. Counts the source page prefetches (photos,
/// perks) are not invented here; the hint states the content instead.
extension MerchantOperationsDestination {
    var entryHintKey: String {
        switch self {
        case .profile: return "merchant.operationsHint.profile"
        case .businessStatus: return "merchant.operationsHint.businessStatus"
        case .decor: return "merchant.operationsHint.decor"
        case .gallery: return "merchant.operationsHint.gallery"
        case .story: return "merchant.operationsHint.story"
        case .cooperation: return "merchant.operationsHint.cooperation"
        case .character: return "merchant.operationsHint.character"
        case .assets: return "merchant.operationsHint.assets"
        case .cityNodes: return "merchant.operationsHint.cityNodes"
        case .templates, .template, .npcMapPoint: return "merchant.operations.entryHint"
        }
    }
}
