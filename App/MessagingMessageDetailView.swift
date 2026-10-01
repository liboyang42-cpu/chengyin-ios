import SwiftUI

/// A static detail of an already-fetched message. The source declares no message-info
/// endpoint, so this never fabricates a fresh detail read or follows a card action.
@MainActor
struct MessagingMessageDetailView: View {
    let message: MessagingMessage
    let conversation: MessagingConversation?
    let reader: any MessagingReading
    let identity: MessagingReadIdentity?
    var body: some View {
        Group {
            if identity != nil, reader.identity == identity {
                List {
                    Section("messaging.message.content") {
                        MessagingMessageContent(message: message).textSelection(.enabled)
                    }
                    Section("messaging.message.details") {
                        LabeledContent("messaging.message.sender") {
                            MessagingSenderName(message: message, conversation: conversation, accountID: identity?.accountID ?? 0)
                        }
                        MessagingOptionalRow(title: "messaging.message.created", value: message.createdAt)
                        LabeledContent("messaging.message.id", value: String(message.id))
                        LabeledContent("messaging.message.conversation", value: String(message.conversationID))
                        if let type = message.type { LabeledContent("messaging.message.type", value: String(type)) }
                    }
                    if let card = message.card {
                        if let topicID = card.topicID {
                            Section {
                                LabeledContent("messaging.card.topicID", value: String(topicID))
                                Text("messaging.card.routeHint").foregroundStyle(.secondary)
                            }
                        }
                        if !card.buttonLabels.isEmpty {
                            Section("messaging.card.actions") {
                                ForEach(Array(card.buttonLabels.enumerated()), id: \.offset) { _, label in Text(verbatim: label) }
                                Text("messaging.card.actionsHint").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if let result = card.result {
                            Section("messaging.card.result") {
                                MessagingOptionalRow(title: "messaging.card.taskID", value: result.taskID)
                                MessagingOptionalRow(title: "messaging.card.businessID", value: result.businessID)
                                MessagingOptionalRow(title: "messaging.card.outcome", value: result.outcome)
                                MessagingOptionalRow(title: "messaging.card.reason", value: result.reason)
                                MessagingOptionalRow(title: "messaging.card.followUp", value: result.followUp)
                            }
                        }
                    }
                    Section { Text("messaging.snapshotHint").font(.footnote).foregroundStyle(.secondary) }
                }.accessibilityIdentifier("messaging.message.detail")
            } else {
                MessagingIssueView(issue: .init(APIError.unauthorized), identifier: "messaging.message.signedOut", retry: {})
            }
        }
        .privacySensitive()
        .navigationTitle("messaging.message.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MessagingMessageContent: View {
    let message: MessagingMessage
    var body: some View {
        switch message.type {
        case 1:
            if let text = message.content, !text.isEmpty { Text(verbatim: text) }
            else { Text("messaging.message.noText").foregroundStyle(.secondary) }
        case 2:
            // Deliberately no AsyncImage/URLSession: external image fetches can disclose
            // the reader's IP or produce tracking side effects. Native placeholder only.
            Label("messaging.imagePlaceholder", systemImage: "photo")
                .foregroundStyle(.secondary).accessibilityIdentifier("messaging.message.image")
        case 3:
            if let card = message.card { MessagingCardContent(card: card) }
            else { Label("messaging.cardUnavailable", systemImage: "rectangle.slash").foregroundStyle(.secondary) }
        default:
            Label("messaging.unsupported", systemImage: "questionmark.bubble").foregroundStyle(.secondary)
        }
    }
}

private struct MessagingCardContent: View {
    let card: MessagingCard
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch card.kind {
            case .location:
                Label("messaging.card.location", systemImage: "mappin.and.ellipse").font(.headline)
                if let title = card.title { Text(verbatim: title) }
                if let address = card.address { Text(verbatim: address).foregroundStyle(.secondary) }
                if let latitude = card.latitude, let longitude = card.longitude {
                    Text(verbatim: "\(latitude), \(longitude)").font(.caption).foregroundStyle(.secondary)
                }
            case .route:
                Label("messaging.card.route", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                if let id = card.topicID { Text(verbatim: "#\(id)") }
                Text("messaging.card.routeHint").font(.caption).foregroundStyle(.secondary)
            case .signup:
                Label("messaging.card.signup", systemImage: "ticket").font(.headline)
                if let id = card.topicID { Text(verbatim: "#\(id)") }
                Text("messaging.card.routeHint").font(.caption).foregroundStyle(.secondary)
            case .generic:
                if let title = card.title { Text(verbatim: title).font(.headline) }
                else { Text("messaging.card.notification").font(.headline) }
                if let subtitle = card.subtitle { Text(verbatim: subtitle) }
                if let meta = card.meta { Text(verbatim: meta).font(.caption).foregroundStyle(.secondary) }
                if card.result != nil { Label("messaging.card.hasResult", systemImage: "doc.text").font(.caption) }
            }
        }
    }
}
