import SwiftUI

/// A static detail of an already-fetched message. The source declares no message-info
/// endpoint, so this never fabricates a fresh detail read. Optional card actions resolve
/// only into typed native destinations; arbitrary payload paths remain disabled.
@MainActor
struct MessagingMessageDetailView: View {
    let message: MessagingMessage
    let conversation: MessagingConversation?
    let reader: any MessagingReading
    let identity: MessagingReadIdentity?
    var mediaReader: (any SocialMessageMediaReading)? = nil
    var expanded: IMExpandedNavigationContext? = nil
    /// Resolve refreshed history by ID; a vanished row must not fall back to its old payload.
    var currentMessage: (() -> MessagingMessage?)? = nil
    private var currentSnapshot: MessagingMessage? {
        if let currentMessage { return currentMessage() }
        return message
    }
    @State private var selectedTopicID: Int?
    @State private var selectedReview: MessagingCardResult?
    var body: some View {
        Group {
            if identity != nil, reader.identity == identity, let message = currentSnapshot {
                List {
                    Section("messaging.message.content") {
                        MessagingMessageContent(message: message).textSelection(.enabled)
                    }
                    if message.isPayloadVisible, message.type == 2, let preview = expanded?.attachmentPreview?(message) {
                        Section {
                            NavigationLink("原附件审核状态与受权预览") {
                                NativeChannelAttachmentPreviewEntry(flow: preview, current: {
                                    reader.identity == identity && currentSnapshot == message && message.isPayloadVisible
                                })
                            }
                        }
                    }
                    if message.isPayloadVisible, message.type == 2, let mediaReader, let identity {
                        Section {
                            NavigationLink { SocialMessageMediaView(message: message, reader: mediaReader, expectedIdentity: identity,
                                isMessageCurrent: { reader.identity == identity && currentSnapshot == message && message.isPayloadVisible }) } label: {
                                Label("social.media.title", systemImage: "photo.on.rectangle.angled")
                            }.accessibilityIdentifier("messaging.message.preview")
                        }
                    }
                    if IMVoiceReference.read(message) != nil, let owner = expanded?.voiceCoordinator?(message.conversationID) {
                        Section {
                            NavigationLink("读取并播放原语音") { IMVoicePlaybackView(message: message, owner: owner, current: {
                                reader.identity == identity && currentSnapshot == message && message.isPayloadVisible
                            }) }
                        }
                    }
                    if IMFileReference.read(message) != nil, let owner = expanded?.fileCoordinator?(message.conversationID) {
                        Section {
                            NavigationLink("读取并预览原文件") { IMFilePreviewView(message: message, owner: owner, current: {
                                reader.identity == identity && currentSnapshot == message && message.isPayloadVisible
                            }) }
                        }
                    }
                    if IMVideoReference.read(message) != nil, let owner = expanded?.videoCoordinator?(message.conversationID) {
                        Section {
                            NavigationLink("读取原视频与封面") { IMVideoPlaybackView(message: message, owner: owner, current: {
                                reader.identity == identity && currentSnapshot == message && message.isPayloadVisible
                            }) }
                        }
                    }
                    if message.isPayloadVisible, let reference = message.pollReference {
                        Section {
                            NavigationLink {
                                if currentSnapshot?.isPayloadVisible == true, currentSnapshot?.pollReference == reference,
                                   let owner = expanded?.pollCoordinator?(message.conversationID, reference) {
                                    if message.type == 9 {
                                        GroupPollOriginalResultView(owner: owner, reference: reference, current: {
                                            reader.identity == identity && currentSnapshot == message && message.isPayloadVisible
                                        })
                                    } else {
                                        GroupPollView(owner: owner, current: {
                                            reader.identity == identity && currentSnapshot == message && message.isPayloadVisible
                                                && owner.reference == reference && owner.scope.conversationID == message.conversationID
                                        })
                                    }
                                }
                                else { GroupPollUnavailableView() }
                            } label: { Label("poll.openResults", systemImage: "chart.bar.xaxis") }
                            .accessibilityIdentifier("poll.messageEntry")
                        }
                    }
                    if let notice = NativeChannelGovernanceNotice.parse(message: message, conversation: conversation, identity: identity) {
                        Section("原频道处置") {
                            NavigationLink {
                                if reader.identity == identity, currentSnapshot == message,
                                   let destination = expanded?.channelGovernanceDestination?(notice) { destination }
                                else { Text("当前无法读取原处置与申诉进度。请返回后重试。") }
                            } label: { Label("查看原处置与申诉进度", systemImage: "doc.text.magnifyingglass") }
                            .accessibilityIdentifier("channel.governance.originalNotice")
                            Text("目的页将回读本人的原处置记录；通知内容不授予操作权限。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
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
                    if message.isPayloadVisible, expanded != nil, message.card != nil {
                        Section("messaging.card.actions") {
                            IMCardActionsView(message: message) { destination in
                                guard reader.identity == identity, currentSnapshot == message, message.isPayloadVisible else { return }
                                switch destination {
                                case .topic(let id): selectedTopicID = id
                                case .review(let result): selectedReview = result
                                case .unsupported: break
                                }
                            }
                        }
                    }
                    if let card = message.card {
                        if let topicID = card.topicID {
                            Section {
                                // w2-20: source route/signup cards read their display fresh.
                                if let topicReader = expanded?.topicReader {
                                    IMRouteCardPreview(topicID: topicID, isSignup: card.kind == .signup, reader: topicReader)
                                }
                                LabeledContent("messaging.card.topicID", value: String(topicID))
                                Text("messaging.card.routeHint").foregroundStyle(.secondary)
                            }
                        }
                        if card.kind == .location, let latitude = card.latitude, let longitude = card.longitude {
                            Section { IMLocationCardMap(title: card.title, latitude: latitude, longitude: longitude) }
                        }
                        if expanded == nil, !card.buttonLabels.isEmpty {
                            Section("messaging.card.actions") {
                                ForEach(Array(card.buttonLabels.enumerated()), id: \.offset) { _, label in Text(verbatim: label) }
                                Text("messaging.card.actionsHint").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if message.senderID == 0, let result = card.result {
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
                }.environment(\.defaultMinListRowHeight, 44)
                .accessibilityIdentifier("messaging.message.detail")
            } else {
                MessagingIssueView(issue: .init(APIError.unauthorized), identifier: "messaging.message.signedOut", retry: {})
            }
        }
        .navigationDestination(item: $selectedTopicID) { id in
            if reader.identity == identity, currentSnapshot?.isPayloadVisible == true, let expanded { TopicDetailView(id: id, reader: expanded.topicReader) }
        }
        .sheet(isPresented: Binding(get: { selectedReview != nil }, set: { if !$0 { selectedReview = nil } })) {
            if reader.identity == identity, currentSnapshot?.isPayloadVisible == true, let result = selectedReview {
                NavigationStack {
                    List {
                        MessagingOptionalRow(title: "messaging.card.taskID", value: result.taskID)
                        MessagingOptionalRow(title: "messaging.card.businessID", value: result.businessID)
                        MessagingOptionalRow(title: "messaging.card.outcome", value: result.outcome)
                        MessagingOptionalRow(title: "messaging.card.reason", value: result.reason)
                        MessagingOptionalRow(title: "messaging.card.followUp", value: result.followUp)
                    }.navigationTitle(Text("im.full.reviewResult"))
                    .toolbar { Button("action.cancel") { selectedReview = nil } }
                }.privacySensitive()
            }
        }
        .onChange(of: currentSnapshot) { _, _ in selectedTopicID = nil; selectedReview = nil }
        .onChange(of: reader.identity) { _, _ in selectedTopicID = nil; selectedReview = nil }
        .privacySensitive()
        .appNavigationTitle("messaging.message.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MessagingMessageContent: View {
    let message: MessagingMessage
    var body: some View {
        if !message.isPayloadVisible {
            Label(LocalizedStringKey(message.status == .recalled ? "messaging.message.recalled" : "messaging.message.withheld"), systemImage: "eye.slash")
                .foregroundStyle(.secondary).accessibilityIdentifier("messaging.message.withheld")
        } else {
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
            if let card = message.card { MessagingCardContent(card: card, isTrustedSystem: message.senderID == 0) }
            else { Label("messaging.cardUnavailable", systemImage: "rectangle.slash").foregroundStyle(.secondary) }
        case 4:
            if message.pollReference != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label("poll.title", systemImage: "chart.bar.xaxis").font(.headline)
                    Text("poll.cardHint").font(.caption)
                }.accessibilityIdentifier("poll.messageCard")
            } else { Label("poll.invalidCard", systemImage: "exclamationmark.bubble").accessibilityIdentifier("poll.invalidCard") }
        case 13:
            if let place = IMStaticLocation.read(message) { IMStaticLocationCardView(place: place) }
            else { Label("messaging.unsupported", systemImage: "questionmark.bubble").foregroundStyle(.secondary) }
        case 9:
            if message.pollReference != nil {
                Label("poll.openResults", systemImage: "chart.bar.xaxis")
            } else { Label("messaging.unsupported", systemImage: "questionmark.bubble").foregroundStyle(.secondary) }
        default:
            Label("messaging.unsupported", systemImage: "questionmark.bubble").foregroundStyle(.secondary)
        }
    }
    }
}

private struct MessagingCardContent: View {
    let card: MessagingCard
    let isTrustedSystem: Bool
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
                if isTrustedSystem, card.result != nil { Label("messaging.card.hasResult", systemImage: "doc.text").font(.caption) }
            }
        }
    }
}
