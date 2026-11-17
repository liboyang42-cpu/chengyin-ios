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

struct ActivityListCard: View {
    let item: ActivitySummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment:.leading,spacing:QuestifyDesign.Space.between) {
            if let url=QuestifyCardArtwork.safeURL(item.imageURL) {
                QuestifyCardArtwork(url:url,height:dynamicTypeSize.isAccessibilitySize ? 132 : 164)
            }
            ActivityName(name:item.name)
                .font(.title3.weight(.semibold))
            ActivitySummaryMetadata(summary:item)
            Divider()
            VStack(alignment:.leading,spacing:QuestifyDesign.Space.xs) {
                Text("activity.startingPrice").font(.caption).foregroundStyle(.secondary)
                AmountLabel(amount:item.minimumAmount).font(.headline)
            }
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
        VStack(alignment:.leading,spacing:QuestifyDesign.Space.lg) {
            ActivityName(name:summary.name)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("activity.detail.name")
            if let text=ActivityPresentation.nonempty(summary.description) {
                Text(verbatim:text)
                    .font(.body)
                    .fixedSize(horizontal:false,vertical:true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("activity.detail.introduction")
            }
        }
        .padding(.top, 160)
        .padding(QuestifyDesign.Space.lg)
        .frame(maxWidth:.infinity, minHeight:dynamicTypeSize.isAccessibilitySize ? 480 : 420, alignment:.bottomLeading)
        .foregroundStyle(QuestifyCardArtwork.safeURL(summary.imageURL) == nil ? Color.primary : Color.white)
        .background {
            if let url=QuestifyCardArtwork.safeURL(summary.imageURL) {
                GeometryReader { geometry in
                    QuestifyCardArtwork(url:url,height:geometry.size.height)
                        .overlay {
                            LinearGradient(colors:[.black.opacity(0.15), .black.opacity(0.9)], startPoint:.top, endPoint:.bottom)
                        }
                }
            }
        }
    }
}

struct ActivityDetailFacts: View {
    let summary: ActivitySummary
    var body: some View {
        VStack(alignment:.leading,spacing:QuestifyDesign.Space.sm) {
            ActivitySummaryMetadata(summary:summary)
            if !summary.categoryNames.isEmpty {
                Text(verbatim:summary.categoryNames.joined(separator:" · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            if let end=ActivityPresentation.nonempty(summary.endDate) {
                LabeledContent("topic.end", value:end)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let address=ActivityPresentation.nonempty(summary.address),
               let place=ActivityPresentation.nonempty(summary.addressName), address != place {
                QuestifyMetadataLine(label:"activity.address",value:address,systemImage:"location")
            }
        }
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
        VStack(alignment:.leading,spacing:QuestifyDesign.Space.sm) {
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
        VStack(alignment:.leading,spacing:QuestifyDesign.Space.control) {
            Text(verbatim:ticket.name)
                .font(.headline)
                .fixedSize(horizontal:false,vertical:true)
            AmountLabel(amount:ticket.price)
                .font(.title3.weight(.semibold))
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
    }
}
