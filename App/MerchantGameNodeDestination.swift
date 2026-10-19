import SwiftUI

/// Host-registered source game-node page. Absent (e.g. the generic content fixture) keeps the
/// existing station document; the session host supplies the dedicated read-first page.
enum MerchantGameNodeRoute: Equatable {
    case station(activityID: Int)
    case entries(topicID: Int, focusPause: Bool)
}
private struct MerchantGameNodeDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor (any MerchantContentServing, MerchantGameNodeRoute) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantGameNodeDestination: (@MainActor (any MerchantContentServing, MerchantGameNodeRoute) -> AnyView)? {
        get { self[MerchantGameNodeDestinationKey.self] }
        set { self[MerchantGameNodeDestinationKey.self] = newValue }
    }
}
extension MerchantGameNodeRoute {
    @MainActor func view(service: any MerchantContentServing) -> AnyView {
        let reader = MerchantGameNodeContentReader(service: service)
        switch self {
        case .station(let activityID): return AnyView(MerchantGameNodeView(service: reader, activityID: activityID))
        case .entries(let topicID, let focusPause): return AnyView(MerchantGameNodeEntryView(service: reader, topicID: topicID, focusPause: focusPause))
        }
    }
}
