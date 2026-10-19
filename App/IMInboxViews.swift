import SwiftUI

/// Source im/list cy-tabs label: 私信 / 系统 (+ native-only 群聊) with a count badge.
struct IMInboxTabLabel: View {
    let tab: IMInboxTab
    let badge: Int
    /// A single Text: segmented pickers only render Text/Image segment labels.
    var body: Text {
        guard let text = IMInboxSummary.badgeText(badge) else { return Text(title) }
        return Text(title) + Text(verbatim: " \(text)")
    }
    private var title: LocalizedStringKey {
        switch tab {
        case .direct: return "im.inbox.tab.direct"
        case .system: return "im.inbox.tab.system"
        case .group: return "im.inbox.tab.group"
        }
    }
}

/// Source list time text (`fmtTime`), China-anchored; unparseable stays hidden.
struct IMInboxTimeLabel: View {
    let raw: String?
    var now = Date()
    var body: some View {
        switch IMInboxTime.listText(raw, now: now) {
        case .justNow?: Text("im.time.justNow")
        case .minutesAgo(let minutes)?: Text("im.time.minutesAgo \(minutes)")
        case .clock(let value)?: Text(verbatim: value)
        case .yesterday?: Text("im.time.yesterday")
        case .weekday(let day)?: Text(Self.weekdayKey(day))
        case .monthDay(let month, let day)?: Text("im.time.monthDay \(month) \(day)")
        case nil: EmptyView()
        }
    }
    static func weekdayKey(_ day: Int) -> LocalizedStringKey {
        switch day {
        case 0: return "im.time.weekday.0"
        case 1: return "im.time.weekday.1"
        case 2: return "im.time.weekday.2"
        case 3: return "im.time.weekday.3"
        case 4: return "im.time.weekday.4"
        case 5: return "im.time.weekday.5"
        default: return "im.time.weekday.6"
        }
    }
}

/// Source chat `fmtAbs` divider text.
struct IMChatDividerLabel: View {
    let divider: IMInboxTime.DividerText
    var body: some View {
        switch divider {
        case .today(let clock): Text(verbatim: clock)
        case .yesterday(let clock): Text("im.time.yesterdayAt \(clock)")
        case .date(let month, let day, let clock): Text("im.time.monthDayAt \(month) \(day) \(clock)")
        }
    }
}

/// Source unread badge: `unread > 99 ? '99+' : unread`, muted rows use the quiet style.
struct IMUnreadBadge: View {
    let count: Int?
    var muted = false
    var body: some View {
        if let text = IMInboxSummary.badgeText(count) {
            Text(verbatim: text)
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(muted ? Color.secondary : Color.white)
                .background(Capsule().fill(muted ? Color.secondary.opacity(0.25) : Color.red))
                .accessibilityLabel(Text("messaging.unread"))
                .accessibilityValue(Text(verbatim: text))
        }
    }
}

/// Source conversation row: avatar (bell for system), name, 官方 tag (type 3),
/// mute mark, time, preview line and unread badge. No remote avatar is loaded.
struct IMInboxRow: View {
    let conversation: MessagingConversation
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2).frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    MessagingConversationName(conversation: conversation).font(.headline).lineLimit(1)
                    if conversation.kind == .merchant {
                        Text("im.inbox.officialTag").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Capsule().stroke(Color.accentColor))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("im.inbox.official.\(conversation.id)")
                    }
                    if conversation.muted == true {
                        Image(systemName: "bell.slash").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel(Text("im.inbox.mutedLabel"))
                    }
                    Spacer(minLength: 4)
                    IMInboxTimeLabel(raw: conversation.lastMessageAt).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    MessagingPreview(conversation: conversation).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 4)
                    IMUnreadBadge(count: conversation.unread, muted: conversation.muted == true)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
    private var symbol: String {
        switch conversation.kind {
        case .system: return "bell.fill"
        case .group: return "person.3.fill"
        default: return "person.crop.circle.fill"
        }
    }
}

/// Entry-point badge for "消息" rows/icons (source talent/list `imUnread`). The
/// read is optional: unconfigured, signed out or failed reads show no badge.
@MainActor struct IMUnreadEntryBadge: View {
    let reader: (any IMUnreadTotalReading)?
    @State private var total: Int?
    @State private var loadedFor: MessagingReadIdentity?
    var body: some View {
        IMUnreadBadge(count: total)
            .accessibilityIdentifier("im.entry.unreadBadge")
            .task(id: reader?.identity) { await load() }
    }
    private func load() async {
        guard let reader, reader.isConfigured, let identity = reader.identity else { total = nil; loadedFor = nil; return }
        if loadedFor != identity { total = nil }
        do {
            let value = try await reader.unreadTotal()
            guard !Task.isCancelled, reader.identity == identity else { return }
            total = value; loadedFor = identity
        } catch { if reader.identity == identity { total = nil } }
    }
}
