import SwiftUI

/// 附近下一程 card from the mini-program finish sheet. Read-only; tapping opens the
/// host-provided activity detail (where price and purchase stay behind their own gates).
@MainActor struct PlayFinishRouteCardView: View {
    let card: PlayFinishRouteCard
    var destination: ((Int) -> AnyView)?

    var body: some View {
        if let destination {
            NavigationLink { destination(card.activityID) } label: { content }
                .accessibilityIdentifier("playx.finishRoute.card")
        } else {
            content.accessibilityIdentifier("playx.finishRoute.card")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text("playx.finishRoute.eyebrow").font(.caption.bold()).foregroundStyle(.secondary)
            if let title = card.title { Text(verbatim: title).font(.headline) }
            else { Text("playx.finishRoute.untitled").font(.headline) }
            if let meta = metaLine { Text(meta).font(.subheadline).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                priceAndAction.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    price
                    Text("playx.finishRoute.action").font(.headline)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.Space.s4)
        .background(Theme.Color.bgSurface(in: .player), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }
    private var priceAndAction: some View {
            HStack {
                price
                Spacer(minLength: Theme.Space.s4)
                Text("playx.finishRoute.action").font(.footnote.bold())
            }
    }
    @ViewBuilder private var price: some View {
                switch card.price {
                case .from(let amount)?: Text("playx.finishRoute.priceFrom \(NSDecimalNumber(decimal: amount).stringValue)")
                case .free?: Text("playx.finishRoute.free")
                case nil: EmptyView()
                }
    }

    private var metaLine: LocalizedStringKey? {
        let distance = card.distanceMeters.map(PlayFinishRouteCard.distanceParts)
        switch (distance, card.address) {
        case (let d?, let address?): return d.kilometres ? "playx.finishRoute.metaKm \(d.value) \(address)" : "playx.finishRoute.metaM \(d.value) \(address)"
        case (let d?, nil): return d.kilometres ? "playx.finishRoute.km \(d.value)" : "playx.finishRoute.m \(d.value)"
        case (nil, let address?): return "playx.finishRoute.address \(address)"
        case (nil, nil): return nil
        }
    }
}
