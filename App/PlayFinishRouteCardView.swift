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
        VStack(alignment: .leading, spacing: 4) {
            Text("playx.finishRoute.eyebrow").font(.caption.bold()).foregroundStyle(.secondary)
            if let title = card.title { Text(verbatim: title).font(.headline) }
            else { Text("playx.finishRoute.untitled").font(.headline) }
            if let meta = metaLine { Text(meta).font(.subheadline).foregroundStyle(.secondary) }
            HStack {
                switch card.price {
                case .from(let amount)?: Text("playx.finishRoute.priceFrom \(NSDecimalNumber(decimal: amount).stringValue)")
                case .free?: Text("playx.finishRoute.free")
                case nil: EmptyView()
                }
                Spacer()
                Text("playx.finishRoute.action").font(.footnote.bold())
            }
        }
        .accessibilityElement(children: .combine)
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
