import SwiftUI

@MainActor struct PublicMerchantFeaturedContext {
    let scope: UUID
    let isCurrent: () -> Bool
    let activity: (Int) -> AnyView
    let couponWallet: () -> AnyView
    func destination(_ route: PublicMerchantFeaturedRoute) -> AnyView {
        switch route {
        case .activity(let id): return activity(id)
        case .couponWallet: return couponWallet()
        }
    }
}

@MainActor struct PublicMerchantFeaturedCard: View {
    let featured: PublicMerchantFeatured
    let image: ((String) -> AnyView)?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = featured.imageURL {
                if let image { image(url).accessibilityLabel(Text("merchant.publicHome.featured.image")) }
                else { Label("merchant.publicHome.featured.image", systemImage: "photo").foregroundStyle(.secondary) }
            }
            Label(LocalizedStringKey(featured.kind == .activity ? "merchant.publicHome.featured.activity" : "merchant.publicHome.featured.coupon"),
                  systemImage: featured.kind == .activity ? "calendar" : "ticket")
                .font(.caption).foregroundStyle(.secondary)
            if let name = featured.name { Text(verbatim: name).font(.headline) }
            else { Text("merchant.publicHome.featured.untitled").font(.headline) }
            if let description = featured.description { Text(verbatim: description).font(.subheadline).textSelection(.enabled) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("merchant.publicHome.featured.card")
    }
}

extension AppSession {
    func makePublicMerchantFeaturedContext(homeReader: any PublicMerchantHomeReading) -> PublicMerchantFeaturedContext {
        let scope = accountCollectionReader.scope
        let revision = sessionRevision
        let contentRevision = contentDetailRevision
        let isCurrent: () -> Bool = { [weak self] in
            guard let self else { return false }
            return homeReader.isConfigured && self.sessionRevision == revision &&
                self.contentDetailRevision == contentRevision && self.accountCollectionReader.scope == scope
        }
        return .init(scope: scope, isCurrent: isCurrent, activity: { [weak self] id in
            guard let self else { return AnyView(Text("merchant.publicHome.unavailable")) }
            return AnyView(SessionPublicMerchantFeaturedDestination(session: self, route: .activity(id), isCurrent: isCurrent))
        }, couponWallet: { [weak self] in
            guard let self else { return AnyView(Text("merchant.publicHome.unavailable")) }
            return AnyView(SessionPublicMerchantFeaturedDestination(session: self, route: .couponWallet, isCurrent: isCurrent))
        })
    }
}

/// Observe session changes even while the merchant page is behind the destination.
@MainActor private struct SessionPublicMerchantFeaturedDestination: View {
    @ObservedObject var session: AppSession
    let route: PublicMerchantFeaturedRoute
    let isCurrent: () -> Bool
    var body: some View {
        Group {
            if !isCurrent() { Text("merchant.publicHome.unavailable") }
            else {
                switch route {
                case .activity(let id):
                    ActivityDetailView(id: id, reader: session)
                case .couponWallet:
                    AccountCollectionCouponsView(reader: session.accountCollectionReader)
                        .id(session.accountCollectionReader.scope)
                        .environment(\.couponCodeFactory, nil)
                }
            }
        }.privacySensitive()
    }
}
