import SwiftUI

/// Session-scoped construction for the 成为节点 hub. Reads reuse the existing session services; the
/// production MerchantContentService has no journal or offline harness, so every city-node write stays dormant.
extension AppSession {
    func merchantCityNodeHub() -> some View {
        MerchantCityNodeHubView(service: merchantContentService, businessReader: merchantBusinessReader,
                                businessJournal: merchantBusinessJournal, placeSearch: PublishingMapKitAdapter())
            .id(merchantContentService.scope)
    }
}

/// Mounts the session hub from any existing merchant entry without threading AppSession through it.
@MainActor struct SessionMerchantCityNodeHub: View {
    @EnvironmentObject private var session: AppSession
    var body: some View { session.merchantCityNodeHub() }
}

/// Optional destination so existing entries (content home `.city`, operations city locations) can open the
/// hub without AppSession; nil keeps the existing MerchantContentDocumentView(.city) path.
private struct MerchantCityNodeHubDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantCityNodeHubDestination: (@MainActor () -> AnyView)? {
        get { self[MerchantCityNodeHubDestinationKey.self] }
        set { self[MerchantCityNodeHubDestinationKey.self] = newValue }
    }
}
