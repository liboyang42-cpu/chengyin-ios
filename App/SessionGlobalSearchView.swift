import SwiftUI

/// Production destination routing reuses only compatible entity domains.
@MainActor struct SessionGlobalSearchView: View {
    @EnvironmentObject private var session: AppSession
    var onSignIn: (() -> Void)? = nil
    @State private var publicLayers: MapPublicLayerCaller?
    var body: some View {
        GlobalSearchView(reader: session.searchMapReader, historyNamespace: session.searchMapHistoryNamespace, publicMerchant: session.publicMerchantHomeContext,
                         onSignIn: onSignIn, recommendedKeywords: GlobalSearchRecommendedKeywords.keywords(for: session.operationalMarket),
                         publicLayers: publicLayers, destination: destination)
            .environment(\.walkingNavigationFactory, session.walkingNavigationFactory)
            .id(session.searchMapReader.scope)
            .task(id: session.searchMapReader.scope) {
                if publicLayers == nil {
                    publicLayers = MapPublicLayerCaller(reader: session.searchMapReader) { id in
                        let access = try await session.activityDetail(id: id)
                        guard case .allowed(let detail) = access else { throw APIError.notConfigured }
                        return detail.summary.name
                    }
                }
                publicLayers?.noteAccount(session.account?.id)
            }
    }
    @ViewBuilder private func destination(_ value: SearchMapDestination) -> some View {
        switch value {
        case .activity(let id): ActivityDetailView(id: id, reader: session, playReaderForActivity: { session.playReader(for: .activity($0)) }, registrationEnabled: true)
        case .topic(let id): SessionTopicDetailView(id: id, session: session)
        case .club(let id): ClubDetailView(id: id, reader: session, onSignIn: onSignIn, actionCoordinator: session.clubActionCoordinator, management: session.clubManagementContext, community: session.clubCommunityContext)
        case .merchant(let id): SearchMapMerchantDetailView(id: id, reader: session.searchMapReader)
        case .cityNode(let id): SearchMapCityDetailView(id: id, reader: session.searchMapReader, destination: cityNodeRelatedDestination)
        }
    }
    @ViewBuilder private func cityNodeRelatedDestination(_ related: SearchMapDestination) -> some View {
        // City-node related links are only merchant IDs, never template IDs masquerading as topics.
        if case .merchant(let merchantID) = related {
            SearchMapMerchantDetailView(id: merchantID, reader: session.searchMapReader)
        }
    }
}
