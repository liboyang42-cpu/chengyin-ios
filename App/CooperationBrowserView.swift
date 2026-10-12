import SwiftUI

@MainActor struct CooperationBrowserView: View {
    let reader: any CooperationReading
    var onClose:(()->Void)? = nil
    var peerReader: (any CoopFlowReading)? = nil
    @State private var direction: CooperationDirection = .received
    @State private var topicFilter: CooperationInboxTopicFilter?
    private var selectedTopicID: Int? {
        guard reader.isConfigured, reader.isAuthenticated else { return nil }
        return topicFilter?.selectedTopic(owner: ObjectIdentifier(reader), scope: reader.scope)
    }
    var body: some View {
        NavigationStack {
            CooperationReadScreen(reader: reader, resource: "inbox.\(direction.rawValue)", operation: { try await reader.inbox(direction: direction) }) { snapshot in
                Section {
                    Picker("cooperation.direction", selection: $direction) {
                        Text("cooperation.received").tag(CooperationDirection.received)
                        Text("cooperation.sent").tag(CooperationDirection.sent)
                    }.pickerStyle(.segmented).accessibilityIdentifier("cooperation.direction")
                    NavigationLink {
                        CooperationPoolView(reader: reader)
                    } label: { Label("cooperation.pool.title", systemImage: "rectangle.stack") }
                        .accessibilityIdentifier("cooperation.pool.open")
                }
                topicFilterSection(snapshot)
                if snapshot.isPartial {
                    Label("cooperation.partial", systemImage: "exclamationmark.triangle").font(.footnote)
                        .accessibilityIdentifier("cooperation.partial")
                }
                invitationSection(snapshot.invitations, direction: snapshot.direction)
                applicationSection(snapshot.applications, direction: snapshot.direction)
                if let registrations = snapshot.registrations { registrationSection(registrations) }
                Section { CooperationReadOnlyNotice() }
            }
            .appNavigationTitle("cooperation.title")
            .onChange(of: reader.scope) { _, _ in topicFilter = nil }
            .onChange(of: ObjectIdentifier(reader)) { _, _ in topicFilter = nil }
            .onChange(of: reader.isAuthenticated) { _, _ in topicFilter = nil }
            .toolbar { if let onClose { ToolbarItem(placement:.cancellationAction) { Button("action.close",action:onClose) } } }
        }
    }
    @ViewBuilder private func topicFilterSection(_ inbox: CooperationInbox) -> some View {
        let owner = ObjectIdentifier(reader)
        let scope = reader.scope
        let selected = selectedTopicID
        let options = CooperationInboxTopicFilter.options(in: inbox)
        if !options.isEmpty || selected != nil {
            Section("cooperation.topicFilter.title") {
                Picker("cooperation.topicFilter.choose", selection: Binding(
                    get: { selectedTopicID ?? 0 },
                    set: { id in
                        guard reader.isConfigured, reader.isAuthenticated,
                              ObjectIdentifier(reader) == owner, reader.scope == scope else { return }
                        if id == 0 { topicFilter = nil }
                        else if let next = CooperationInboxTopicFilter(topicID: id, inbox: inbox, owner: owner, scope: scope) { topicFilter = next }
                    })) {
                    Text("cooperation.topicFilter.all").tag(0)
                    ForEach(options) { option in
                        if let name = option.name { Text(verbatim: name + " #" + String(option.id)).tag(option.id) }
                        else { Text(verbatim: "#" + String(option.id)).tag(option.id) }
                    }
                    if let selected, !options.contains(where: { $0.id == selected }) {
                        Text(verbatim: "#" + String(selected)).tag(selected)
                    }
                }.accessibilityIdentifier("cooperation.topicFilter.choose")
                Text("cooperation.topicFilter.loadedOnly").font(.footnote).foregroundStyle(.secondary)
                if selected != nil {
                    Button("cooperation.topicFilter.clear") {
                        guard ObjectIdentifier(reader) == owner, reader.scope == scope else { return }
                        topicFilter = nil
                    }.accessibilityIdentifier("cooperation.topicFilter.clear")
                }
            }
        }
    }
    @ViewBuilder private func invitationSection(_ state: CooperationSection<CooperationInvites>, direction: CooperationDirection) -> some View {
        Section("cooperation.invitations") {
            switch state {
            case .failure(let issue): CooperationIssueView(issue: issue)
            case .content(let list):
                let rows = CooperationInboxTopicFilter.visibleRows(list.rows(direction), topicID: selectedTopicID, topic: { $0.topicId })
                if rows.isEmpty { Text(selectedTopicID == nil ? "cooperation.invitations.empty" : "cooperation.topicFilter.empty").foregroundStyle(.secondary) }
                // Ordinal identities preserve duplicate server IDs without merging unrelated entries.
                ForEach(rows, id: \.offset) { index, row in
                    NavigationLink {
                        CooperationInviteDetailView(key: CooperationInviteKey(id: row.id, direction: direction), reader: reader, peerReader: peerReader)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CooperationName(name: row.partner?.name).font(.headline)
                            CooperationStatus(key: row.statusKey, symbol: row.status == 0 ? "clock" : row.status == 1 ? "checkmark.circle" : "circle")
                            if let id = row.topicId { CooperationTopicReference(id: id) }
                            CooperationTimeField(key: "cooperation.created", value: row.createTime)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("cooperation.invite.\(direction.rawValue).\(row.id).\(index)")
                }
            }
        }
    }
    @ViewBuilder private func applicationSection(_ state: CooperationSection<[CooperationApplication]>, direction: CooperationDirection) -> some View {
        Section("cooperation.applications") {
            switch state {
            case .failure(let issue): CooperationIssueView(issue: issue)
            case .content(let rows):
                let visible = CooperationInboxTopicFilter.visibleRows(rows, topicID: selectedTopicID, topic: { $0.topicId })
                if visible.isEmpty { Text(selectedTopicID == nil ? "cooperation.applications.empty" : "cooperation.topicFilter.empty").foregroundStyle(.secondary) }
                ForEach(visible, id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        CooperationName(name: row.topicName, fallback: "cooperation.unnamedTopic").font(.headline)
                        CooperationStatus(key: row.statusKey)
                        CooperationField(key: direction == .received ? "cooperation.fromClub" : "cooperation.toMerchant", value: direction == .received ? row.clubName : row.merchantNick)
                        CooperationTopicReference(id: row.topicId)
                        CooperationTimeField(key: "cooperation.start", value: row.startDate)
                        if let message = row.message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            CooperationField(key: "cooperation.message", value: message)
                        } else { Text("cooperation.application.intent").font(.footnote).foregroundStyle(.secondary) }
                        if direction == .received { CooperationCandidateLink(topicID: row.topicId, reader: reader) }
                    }.padding(.vertical, 4)
                }
            }
        }
    }
    @ViewBuilder private func registrationSection(_ state: CooperationSection<CooperationRegistrations>) -> some View {
        Section("cooperation.registrations") {
            switch state {
            case .failure(let issue): CooperationIssueView(issue: issue)
            case .content(let page):
                let visible = CooperationInboxTopicFilter.visibleRows(page.rows, topicID: selectedTopicID, topic: { $0.topicId })
                if visible.isEmpty { Text(selectedTopicID == nil ? "cooperation.registrations.empty" : "cooperation.topicFilter.empty").foregroundStyle(.secondary) }
                ForEach(visible, id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        CooperationName(name: row.merchantName, fallback: "cooperation.unnamedMerchant").font(.headline)
                        if let member = row.memberId { CooperationField(key: "cooperation.merchant", value: "#\(member)") }
                        CooperationStatus(key: row.statusKey)
                        CooperationField(key: "cooperation.topic", value: row.topicName)
                        CooperationField(key: "cooperation.location", value: row.addressName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? row.addressName : row.address)
                        CooperationField(key: "cooperation.about", value: row.merchantMeta)
                        if let topic = row.topicId {
                            CooperationTopicReference(id: topic)
                            CooperationCandidateLink(topicID: topic, reader: reader)
                        }
                    }.padding(.vertical, 4)
                }
                if page.hasMore == true {
                    Text("cooperation.registrations.more").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("cooperation.registrations.more")
                }
            }
        }
    }
}
