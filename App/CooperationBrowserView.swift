import SwiftUI

@MainActor struct CooperationBrowserView: View {
    let reader: any CooperationReading
    var onClose:(()->Void)? = nil
    var peerReader: (any CoopFlowReading)? = nil
    @State private var direction: CooperationDirection = .received
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
            .toolbar { if let onClose { ToolbarItem(placement:.cancellationAction) { Button("action.close",action:onClose) } } }
        }
    }
    @ViewBuilder private func invitationSection(_ state: CooperationSection<CooperationInvites>, direction: CooperationDirection) -> some View {
        Section("cooperation.invitations") {
            switch state {
            case .failure(let issue): CooperationIssueView(issue: issue)
            case .content(let list):
                let rows = list.rows(direction)
                if rows.isEmpty { Text("cooperation.invitations.empty").foregroundStyle(.secondary) }
                // Ordinal identities preserve duplicate server IDs without merging unrelated entries.
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
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
                if rows.isEmpty { Text("cooperation.applications.empty").foregroundStyle(.secondary) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
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
                if page.rows.isEmpty { Text("cooperation.registrations.empty").foregroundStyle(.secondary) }
                ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in
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
