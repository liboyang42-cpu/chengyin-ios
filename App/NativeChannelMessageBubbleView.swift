import SwiftUI

@MainActor struct NativeChannelMessageBubbleView: View {
    @Environment(\.locale) private var locale
    @Environment(\.themeDomain) private var domain
    @Environment(\.dynamicTypeSize) private var typeSize
    let snapshot: NativeChannelMessageSnapshot
    let isCurrent: () -> Bool
    let locateOriginal: (NativeChannelMessageID) -> Void
    /// Existing owner consumes its own trusted poll/chain/card/attachment contracts.
    var videoOwner: IMVideoCoordinator? = nil
    var fileOwner: IMFileCoordinator? = nil
    var voiceOwner: IMVoiceCoordinator? = nil
    var attachmentPreview: NativeChannelAttachmentPreviewFlow? = nil
    var pollCoordinator: ((Int, GroupPollReference?) -> GroupPollCoordinator?)? = nil
    var chainCoordinator: ((Int, NativeChannelChainReference?) -> NativeChannelChainFlow?)? = nil
    var checkinCoordinator: ((Int) -> NativeChannelCheckinFlow?)? = nil
    var openExistingType: ((NativeChannelMessageSnapshot) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1_5) {
            if !isCurrent() { Text("message.unavailable", tableName: "NativeChannelMessage") }
            else if snapshot.status == 1 { Text("message.recalled", tableName: "NativeChannelMessage").foregroundStyle(.secondary) }
            else if snapshot.status != 0 { Text("message.unavailable", tableName: "NativeChannelMessage").foregroundStyle(.secondary) }
            else {
                if let quote = snapshot.reply {
                    Button { if isCurrent(), quote.state == "VISIBLE" { locateOriginal(quote.id) } } label: {
                        Text(quote.summary ?? placeholder(quote.state))
                            .font(Theme.Font.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, Theme.Space.s3)
                            .frame(minHeight: 44, alignment: .leading)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.Color.borderSubtle(in: domain)).frame(width: 2).accessibilityHidden(true) }
                    }.disabled(quote.state != "VISIBLE")
                    .accessibilityIdentifier("ncm47.quote")
                }
                switch snapshot.kind {
                case .image:
                    MessagingMessageContent(message: snapshot.message)
                    if let attachmentPreview {
                        NavigationLink("原附件审核状态与受权预览") { NativeChannelAttachmentPreviewEntry(flow:attachmentPreview,current:isCurrent) }
                    } else { Text("原附件预览尚不可用") }
                case .text, .poll:
                    MessagingMessageContent(message: snapshot.message)
                case .card:
                    if let day = NativeChannelCheckinReminder.day(in: snapshot) {
                        Label("频道日签 · \(day)", systemImage: "calendar.badge.checkmark")
                        if let checkinCoordinator {
                            NavigationLink("读取服务器今日签到与原请求") {
                                NativeChannelCheckinLaunchView(makeFlow: { checkinCoordinator(snapshot.message.conversationID) },
                                    current: isCurrent, reminderDate: day)
                            }
                        } else { Text("原日签入口当前不可用") }
                    } else { MessagingMessageContent(message: snapshot.message) }
                case .joined, .left, .renamed, .pinned, .pollResult:
                    Text(snapshot.content ?? String(localized: LocalizedStringResource("message.system", table: "NativeChannelMessage", locale: locale)))
                        .font(Theme.Font.label).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                case .location:
                    if let place=IMStaticLocation.read(snapshot.message) { IMStaticLocationCardView(place:place) }
                    else { Text("地点来源不可确认").foregroundStyle(.secondary) }
                case .voice:
                    if let voiceOwner, IMVoiceReference.read(snapshot.message) != nil {
                        NavigationLink("读取并播放原语音") { IMVoicePlaybackView(message: snapshot.message, owner: voiceOwner, current: isCurrent) }
                    } else { Text("原语音当前不可用") }
                case .file:
                    if let fileOwner, IMFileReference.read(snapshot.message) != nil {
                        NavigationLink("读取并预览原文件") { IMFilePreviewView(message: snapshot.message, owner: fileOwner, current: isCurrent) }
                    } else { Text("原文件当前不可用") }
                case .video:
                    if let videoOwner, IMVideoReference.read(snapshot.message) != nil {
                        NavigationLink("读取原视频与封面") { IMVideoPlaybackView(message: snapshot.message, owner: videoOwner, current: isCurrent) }
                    } else { Text("原视频当前不可用") }
                case .chain:
                    Label("接龙", systemImage: "list.number")
                    if let content = snapshot.content { Text(verbatim: content).lineLimit(typeSize.isAccessibilitySize ? nil : 3) }
                    if let reference = NativeChannelChainReference(message: snapshot.message), let chainCoordinator {
                        NavigationLink("展开原接龙与我的接龙操作") {
                            NativeChannelChainLaunchView(makeFlow: { chainCoordinator(snapshot.message.conversationID, reference) }, current: isCurrent)
                        }.accessibilityIdentifier("ncm47.originalChain")
                    } else if let openExistingType {
                        Button { if isCurrent() { openExistingType(snapshot) } } label: { Text("type.open", tableName: "NativeChannelMessage") }
                    } else { Text("type.sourceRequired", tableName: "NativeChannelMessage").font(Theme.Font.label).foregroundStyle(.secondary) }
                case .redPacket:
                    Label { Text("type.15", tableName: "NativeChannelMessage") } icon: { Image(systemName: icon) }
                    if let content = snapshot.content { Text(verbatim: content).lineLimit(typeSize.isAccessibilitySize ? nil : 3) }
                    if let openExistingType {
                        Button { if isCurrent() { openExistingType(snapshot) } } label: { Text("type.open", tableName: "NativeChannelMessage") }
                    } else { Text("type.sourceRequired", tableName: "NativeChannelMessage").font(Theme.Font.label).foregroundStyle(.secondary) }
                case .unknown: Text("type.unknown", tableName: "NativeChannelMessage").foregroundStyle(.secondary)
                }
                if let reference = snapshot.message.pollReference,
                   let owner = pollCoordinator?(snapshot.message.conversationID, reference),
                   owner.isCurrent, owner.reference == reference, owner.canRead {
                    NavigationLink("查看原投票结果（只读）") {
                        GroupPollOriginalResultView(owner: owner, reference: reference, current: isCurrent)
                    }.accessibilityIdentifier("ncm47.originalPollResult")
                }
                if snapshot.editedAt != nil { Label { Text("message.edited", tableName: "NativeChannelMessage") } icon: { Image(systemName: "pencil").accessibilityHidden(true) }.font(Theme.Font.caption).foregroundStyle(.secondary) }
            }
        }
        .font(Theme.Font.body)
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitive().accessibilityIdentifier("ncm47.message.\(snapshot.id.rawValue)")
    }
    private var icon: String {
        switch snapshot.kind { case .voice: return "waveform"; case .video: return "video"; case .file: return "doc"; case .location: return "mappin"; case .chain: return "list.number"; case .redPacket: return "gift"; default: return "bubble.left" }
    }
    private func placeholder(_ state: String) -> String {
        switch state {
        case "BLOCKED": return String(localized: LocalizedStringResource("quote.blocked", table: "NativeChannelMessage", locale: locale))
        case "RECALLED": return String(localized: LocalizedStringResource("message.recalled", table: "NativeChannelMessage", locale: locale))
        default: return String(localized: LocalizedStringResource("message.unavailable", table: "NativeChannelMessage", locale: locale))
        }
    }
}
