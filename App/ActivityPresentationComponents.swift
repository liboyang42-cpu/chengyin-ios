import SwiftUI

/// Presentation-only normalization. Keep source strings and their timezone/currency
/// semantics intact; blank optional metadata must not create empty visual rows.
enum ActivityPresentation {
    static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    static func place(_ summary: ActivitySummary) -> String? {
        nonempty(summary.addressName) ?? nonempty(summary.address)
    }
}

/// Same card rules as home: cover, title, one date · place line, starting price. Missing values are left out.
struct ActivityListCard: View {
    let item: ActivitySummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            if let url=QuestifyCardArtwork.safeURL(item.imageURL) {
                QuestifyCardArtwork(url:url,height:dynamicTypeSize.isAccessibilitySize ? 132 : 164)
            }
            ActivityName(name:item.name)
                .font(.title3.weight(.semibold))
            QuestifyCardSummary(meta: QuestifyCardText.metaLine(date: QuestifyCardText.date(item.startDate, locale: locale, displayTimeZone: timeZone),
                                                                place: ActivityPresentation.place(item)),
                                price: QuestifyCardText.amount(item.minimumAmount, locale: locale))
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal:false,vertical:true)
        .questifyCardSurface()
    }
}

struct ActivityDetailHeader: View {
    let summary: ActivitySummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if let url=QuestifyCardArtwork.safeURL(summary.imageURL) {
                QuestifyCardArtwork(url:url,height:dynamicTypeSize.isAccessibilitySize ? 180 : 240)
            } else {
                // No cover: a clean surface with no text.
                RoundedRectangle(cornerRadius:14,style:.continuous)
                    .fill(Color(uiColor:.tertiarySystemFill))
                    .frame(height:160)
                    .accessibilityHidden(true)
            }
            ActivityName(name:summary.name)
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("activity.detail.name")
            ActivitySummaryMetadata(summary:summary)
            if let address=ActivityPresentation.nonempty(summary.address),
               let place=ActivityPresentation.nonempty(summary.addressName), address != place {
                QuestifyMetadataLine(label:"activity.address",value:address,systemImage:"location")
            }
        }
        .questifyCardSurface()
    }
}

private struct ActivityName: View {
    let name: String
    var body: some View {
        Group {
            if ActivityPresentation.nonempty(name) != nil { Text(verbatim:name) }
            else { Text("activity.untitled") }
        }
        .fixedSize(horizontal:false,vertical:true)
    }
}

private struct ActivitySummaryMetadata: View {
    let summary: ActivitySummary
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if let date=ActivityPresentation.nonempty(summary.startDate) {
                QuestifyMetadataLine(label:"activity.date",value:date,systemImage:"calendar")
            }
            if let place=ActivityPresentation.place(summary) {
                QuestifyMetadataLine(label:"activity.location",value:place,systemImage:"mappin.and.ellipse")
            }
        }
    }
}

struct ActivityTicketCard: View {
    let ticket: ActivityTicket
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(verbatim:ticket.name)
                .font(.headline)
                .fixedSize(horizontal:false,vertical:true)
            AmountLabel(amount:ticket.price)
                .accessibilityElement(children:.combine)
                .accessibilityIdentifier("activity.ticket.price.\(ticket.id)")
            if ticket.isSoldOut {
                QuestifyStatusBadge(title:"activity.soldOut",systemImage:"xmark.circle",stateKey:"soldOut")
                    .accessibilityIdentifier("activity.ticket.soldOut.\(ticket.id)")
            } else if ticket.remainingInventory == nil {
                QuestifyStatusBadge(title:"activity.inventoryUnknown",systemImage:"questionmark.circle",stateKey:"unknown")
                    .accessibilityIdentifier("activity.ticket.inventoryUnknown.\(ticket.id)")
            }
            if let description=ActivityPresentation.nonempty(ticket.description) {
                Text(verbatim:description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }
        .questifyCardSurface()
    }
}
