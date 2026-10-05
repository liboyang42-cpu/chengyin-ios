import SwiftUI

@MainActor struct OfficialInboxView: View {
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var publisher = false
    var onLogin: (() -> Void)? = nil
    var body: some View {
        OfficialReadScreen(reader: reader, isPrivate: true, requestID: "inbox", onLogin: onLogin, load: { try await reader.partyInbox() }) { rows in
            List {
                if rows.isEmpty { Text("official.emptyInbox") }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        if row.title.isEmpty { Text("official.inviteUntitled").font(.headline) }
                        else { Text(verbatim: row.title).font(.headline) }
                        if let title = row.eventTitle, !title.isEmpty { Text(verbatim: title) }
                        if let city = row.city, !city.isEmpty { Text(verbatim: city) }
                        if let type = row.partyType { LabeledContent("official.partyType", value: type).font(.caption) }
                        Label(LocalizedStringKey(row.statusKey), systemImage: "envelope")
                        if let status = row.status, row.statusKey == "official.status.unknown" { Text(verbatim: status).font(.caption) }
                        Text("official.inviteActionsDeferred").font(.footnote).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("official.invite.\(row.id)")
                    if let actions { OfficialInviteResponseActions(coordinator: actions, invite: row, publisher: publisher) }
                }
                Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
            }.accessibilityIdentifier("official.inbox.content")
        }.appNavigationTitle("official.inbox").navigationBarTitleDisplayMode(.inline)
    }
}
@MainActor struct OfficialPublishedView: View {
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var onLogin: (() -> Void)? = nil
    var body: some View {
        OfficialReadScreen(reader: reader, isPrivate: true, requestID: "published", onLogin: onLogin, load: { try await reader.myPublished() }) { value in
            List {
                if let actions {
                    Section {
                        NavigationLink("officialAction.publish") { OfficialPublishEditor(coordinator: actions) }
                        NavigationLink("officialAction.broadcast") { OfficialBroadcastEditor(coordinator: actions) }
                    }
                }
                if value.isEmpty { Text("official.emptyPublished") }
                if !value.events.isEmpty {
                    Section("official.publishedEvents") {
                        ForEach(OfficialEventFilter.visible(value.events, bucket: .mine)) { event in
                            NavigationLink { OfficialEventDetailView(id: event.id, reader: reader, actions: actions, onLogin: onLogin) } label: { OfficialEventCard(event: event) }
                                .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                        }
                    }
                }
                if !value.broadcasts.isEmpty {
                    Section("official.broadcasts") {
                        ForEach(Array(value.broadcasts.enumerated()), id: \.offset) { _, broadcast in
                            if broadcast.id > 0 {
                                NavigationLink { OfficialBroadcastStatsView(id: broadcast.id, reader: reader, onLogin: onLogin) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if broadcast.title.isEmpty { Text("official.untitled") }
                                        else { Text(verbatim: broadcast.title).font(.headline) }
                                        if let content = broadcast.content { Text(verbatim: content).lineLimit(3) }
                                        if let reach = broadcast.reach { LabeledContent("official.reach", value: String(reach)).font(.caption) }
                                        Text("official.reachExplanation").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("official.broadcast.\(broadcast.id)")
                            }
                        }
                    }
                }
                Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
            }.accessibilityIdentifier("official.published.content")
        }.appNavigationTitle("official.published").navigationBarTitleDisplayMode(.inline)
    }
}
@MainActor struct OfficialBroadcastStatsView: View {
    let id: Int
    let reader: any OfficialEventReading
    var onLogin: (() -> Void)? = nil
    var body: some View {
        OfficialReadScreen(reader: reader, isPrivate: true, requestID: "stats.\(id)", onLogin: onLogin, load: { try await reader.broadcastStats(id: id) }) { stats in
            List {
                if stats.rows.isEmpty { Text("official.emptyStats") }
                ForEach(stats.rows) { row in
                    LabeledContent {
                        switch row.value {
                        case .text(let value): Text(verbatim: value)
                        case .number(let value): Text(verbatim: NSDecimalNumber(decimal: value).stringValue)
                        case .flag(let value): Text(value ? "official.yes" : "official.no")
                        case .unsupported: EmptyView()
                        }
                    } label: {
                        switch row.id {
                        case "reach": Text("official.reach")
                        case "read", "reads": Text("official.reads")
                        case "click", "clicks": Text("official.clicks")
                        default: Text(verbatim: row.id)
                        }
                    }
                }
                Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
            }.accessibilityIdentifier("official.stats.content")
        }.appNavigationTitle("official.stats").navigationBarTitleDisplayMode(.inline)
    }
}
