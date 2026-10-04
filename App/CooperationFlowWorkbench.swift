import SwiftUI

/// Injectable cooperation routes. Compose with existing inbox/pool/candidate readers; no automatic writes.
@MainActor struct CooperationFlowWorkbench: View {
    let reader: any CoopFlowReading
    var operationScope: String? = nil
    var body: some View {
        List {
            Section("coopflow.business") {
                link("coopflow.finance", resource: .finance)
                link("coopflow.mybiz", resource: .myBusiness)
                link("coopflow.relations", resource: .relations)
                link("coopflow.clubs", resource: .clubs(name: nil))
                NavigationLink { CoopFlowNearbyGate(reader: reader) } label: { Text("coopflow.nearby") }
                    .accessibilityIdentifier("coopflow.route.coopflow.nearby")
            }
            Section("coopflow.supply") {
                link("coopflow.templates", resource: .templates)
                NavigationLink { CoopFlowTemplateEditor() } label: { Label("coopflow.template.new", systemImage: "plus.circle") }
            }
            Section("coopflow.workflows") {
                NavigationLink { CoopFlowNewInvitationView(reader: reader, operationScope: operationScope) } label: { Label("context.coop.new", systemImage: "person.crop.circle.badge.plus") }
                    .accessibilityIdentifier("context.coop.new")
                link("coopflow.invitations", resource: .invitations)
                link("coopflow.pool", resource: .pool)
                link("coopflow.applications", resource: .applications)
                link("coopflow.receivedApplications", resource: .receivedApplications)
                link("coopflow.registrations", resource: .registrations)
                link("coopflow.complaints", resource: .complaintTopics)
            }
            Section { CoopFlowSafetyNotice() }
        }.navigationTitle("coopflow.title").accessibilityIdentifier("coopflow.workbench")
    }
    private func link(_ key: String, resource: CoopFlowRead) -> some View {
        NavigationLink { CoopFlowReadView(reader: reader, resource: resource, title: key) } label: { Text(LocalizedStringKey(key)) }.accessibilityIdentifier("coopflow.route.\(key)")
    }
}
/// Reachable before a location provider is approved. Opening this page never requests permission.
@MainActor struct CoopFlowNearbyGate: View {
    @Environment(\.cooperationNearbyDestination) private var nearbyDestination
    let reader: any CoopFlowReading
    var body: some View {
        if let nearbyDestination { nearbyDestination() }
        else { gate }
    }
    private var gate: some View {
        List {
            Section {
                Label("coopflow.nearby.purpose", systemImage: "location")
                if reader.session == nil { Text("cooperation.login") }
                else { Text("coopflow.nearby.unavailable") }
            }
            Section { Text("coopflow.nearby.privacy"); CoopFlowSafetyNotice() }
        }.navigationTitle("coopflow.nearby")
            .accessibilityIdentifier("coopflow.nearby.gate")
    }
}

struct CoopFlowSafetyNotice: View {
    var body: some View {
        Label("coopflow.dormant", systemImage: "lock.shield")
            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("coopflow.dormant")
    }
}
@MainActor struct CoopFlowReadView: View {
    @Environment(\.locale) private var locale
    let reader: any CoopFlowReading
    let resource: CoopFlowRead
    let title: String
    @State private var value: CoopFlowJSON?
    @State private var loadedSession: CoopFlowSession?
    @State private var issue: String?
    @State private var generation = UUID()
    @State private var refresh = UUID()
    @State private var inviteContext: CoopFlowInvitationContext?
    var body: some View {
        List {
            if case .finance = resource {
                NavigationLink("withdrawal.support.contact") { WithdrawalSupportContactView() }
                    .accessibilityIdentifier("coopflow.withdrawal.support")
            }
            if reader.session == nil { Text("cooperation.login") }
            else if loadedSession != reader.session { ProgressView("cooperation.loading") }
            else if let issue {
                Text(issue).accessibilityIdentifier("coopflow.issue")
                Button("cooperation.refresh") { refresh = UUID() }
            } else if let value {
                content(value)
                Section { CoopFlowSafetyNotice() }
            } else { ProgressView("cooperation.loading") }
        }
        .navigationTitle(LocalizedStringKey(title))
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0):\(refresh)") { await load() }
        .refreshable { await load() }
        .onDisappear { generation = UUID() }
        .sheet(item: $inviteContext) { context in
            NavigationStack { CoopFlowInviteEditor(reader: reader, context: context) }
        }
        .onChange(of: reader.session) { _, _ in inviteContext = nil; refresh = UUID() }
    }
    private func load() async {
        let stamp = UUID(); generation = stamp; value = nil; issue = nil; loadedSession = nil
        guard let session = reader.session else { return }
        do {
            let result = try await reader.read(resource)
            guard !Task.isCancelled, generation == stamp, reader.session == session else { return }
            value = result; loadedSession = session
        } catch {
            guard !Task.isCancelled, generation == stamp, reader.session == session else { return }
            if case CoopFlowFailure.server(_, let message) = error, let message, !message.isEmpty { issue = message }
            else { issue = appLocalized("coopflow.read.failed", locale: locale) }
            loadedSession = session
        }
    }
    @ViewBuilder private func content(_ value: CoopFlowJSON) -> some View {
        switch resource {
        case .finance: settlementRows(value["topics"].rows ?? [], source: .finance)
        case .myBusiness:
            Section("coopflow.credit") { CoopFlowFields(value: value["credit"], keys: ["fulfillmentRate", "violationCount"]) }
            Section("coopflow.reviews") {
                if value["review"]["reviewCount"].integer == 0 { Text("coopflow.reviews.empty") }
                else { CoopFlowFields(value: value["review"], keys: ["reviewCount", "avgRating"]) }
            }
            settlementRows(value["settlements"].rows ?? [], source: .mybiz)
        case .relations:
            Section("coopflow.stats") { CoopFlowFields(value: value["stats"], keys: ["merchantCount", "clubCount", "pendingCoopCount"]) }
            rows(value["relations"].rows ?? [], section: "coopflow.relations")
            rows(value["discovery"]["merchants"].rows ?? [], section: "coopflow.discovery")
        case .invitations:
            rows(value["received"].rows ?? [], section: "cooperation.received")
            rows(value["sent"].rows ?? [], section: "cooperation.sent")
        case .pool: rows(value["rows"].rows ?? [], section: title)
        case .registrations: rows(value["rows"].rows ?? [], section: title)
        default:
            if let list = value.rows { rows(list, section: title) }
            else { CoopFlowFields(value: value, keys: ["paymentStatus", "fulfillmentRate", "violationCount", "reviewCount", "avgRating"]) }
        }
    }
    @ViewBuilder private func settlementRows(_ rows: [CoopFlowJSON], source: CoopFlowSettlement.Source) -> some View {
        Section("coopflow.settlements") {
            if rows.isEmpty { Text("coopflow.empty") }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let settlement = CoopFlowSettlement(source: source, record: row)
                if let id = settlement.id, id > 0 {
                    NavigationLink {
                        CoopFlowSettlementDetail(reader: reader, source: source, id: id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row["topicName"].text ?? appLocalized("cooperation.unnamedTopic", locale: locale)).font(.headline)
                            Text(LocalizedStringKey("coopflow.status." + String(settlement.status)))
                            CoopFlowMoneyLabel(value: settlement.amount)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("coopflow.settlement.\(source.rawValue).\(id)")
                }
            }
        }
    }
    @ViewBuilder private func rows(_ values: [CoopFlowJSON], section: String) -> some View {
        Section(LocalizedStringKey(section)) {
            if values.isEmpty { Text("coopflow.empty") }
            ForEach(Array(values.enumerated()), id: \.offset) { index, row in
                NavigationLink {
                    List {
                        CoopFlowFields(value: row, keys: ["name", "topicName", "clubName", "merchantName", "type", "id", "memberId", "topicId", "applyId", "scope", "state", "status", "auditStatus", "toType", "fromId", "toId", "message", "handleReason", "termsFrozen", "retailValue", "unitCost", "quota", "validEnd", "address", "distance", "category"])
                        sourceActions(row)
                        Section { CoopFlowSafetyNotice() }
                    }.navigationTitle("coopflow.details")
                } label: {
                    QuestifyImageEntityCard(
                        imageSource: row["cover"].text ?? row["topicCover"].text ?? row["clubLogo"].text ?? row["merchantLogo"].text,
                        title: row["name"].text ?? row["topicName"].text ?? row["clubName"].text ?? row["merchantName"].text ?? row["partner"]["name"].text ?? "",
                        subtitle: row["address"].text, fallbackTitle: "coopflow.unnamed", minimumHeight: 210) {
                            if let state = row["state"].text { Text(state) }
                    }
                }.accessibilityIdentifier("coopflow.row.\(index)")
            }
        }
    }
    @ViewBuilder private func sourceActions(_ row: CoopFlowJSON) -> some View {
        Section("coopflow.reviewAction") {
            switch resource {
            case .invitations:
                if let id = row["id"].integer, let status = row["status"].integer {
                    let isFrom = row["fromId"].integer == reader.session?.accountID
                    let actions = CoopFlowContractState(invite: row).actions(isFrom: isFrom, isTo: !isFrom)
                    ForEach(actions, id: \.rawValue) { action in
                        NavigationLink { CoopFlowHandleEditor(inviteID: id, action: action, currentStatus: status) } label: { Text(LocalizedStringKey("coopflow.handle." + String(action.rawValue))) }
                    }
                    if status == 1 && row["inviteType"].integer != 2 {
                        NavigationLink("coopflow.supply") { CoopFlowReadView(reader: reader, resource: .perks(inviteID: id), title: "coopflow.supply") }
                        NavigationLink("coopflow.attach") { CoopFlowPerkPicker(reader: reader, inviteID: id) }
                        preview(.contact(inviteID: id), label: "coopflow.contact")
                        if let topic = row["topicId"].integer,
                           let member = isFrom ? (row["toType"].text == "merchant" ? row["toId"].integer : nil) : row["fromId"].integer,
                           member != reader.session?.accountID {
                            NavigationLink("coopflow.reviews") { CoopFlowReviewEditor(topicID: topic, memberID: member, partnerName: row["partner"]["name"].text ?? appLocalized("coopflow.unnamed", locale: locale)) }
                        }
                    }
                }
            case .templates:
                if let id = row["id"].integer { preview(.deleteTemplate(id: id), label: "coopflow.deleteTemplate") }
            case .pool:
                if let id = row["topicId"].integer {
                    if ["open", "declined", "withdrawn"].contains(row["state"].text ?? "") { preview(.apply(topicID: id), label: "coopflow.apply") }
                    if row["state"].text == "applied" { preview(.withdraw(topicID: id), label: "coopflow.withdraw") }
                }
            case .applications:
                if row["status"].integer == 0, let id = row["topicId"].integer { preview(.withdraw(topicID: id), label: "coopflow.withdraw") }
            case .receivedApplications:
                if loadedSession == reader.session,
                   let context = CoopFlowInvitationContext(receivedApplication: row, session: loadedSession) {
                    Button("coopflow.invite.reply") { inviteContext = context }
                        .accessibilityIdentifier("coopflow.invite.reply")
                }
                if row["status"].integer == 0, let id = row["applyId"].integer { preview(.decline(applyID: id, scope: row["scope"].text), label: "coopflow.decline") }
            case .registrations:
                if row["auditStatus"].integer == 0, let id = row["id"].integer {
                    preview(.confirm(registrationID: id), label: "coopflow.confirmCandidate")
                    preview(.reject(registrationID: id), label: "coopflow.rejectCandidate")
                }
            case .complaintTopics:
                if let topic = row["topicId"].integer { NavigationLink("coopflow.complaint.prepare") { CoopFlowReasonEditor(topicID: topic) } }
            default: EmptyView()
            }
        }
    }
    private func preview(_ op: CoopFlowMutation, label: String) -> some View {
        NavigationLink { CoopFlowRequestPreview(operation: op) } label: { Text(LocalizedStringKey(label)) }
    }
}
struct CoopFlowMoneyLabel: View {
    let value: CoopFlowMoney
    var body: some View {
        if let amount = value.amount { Text("\(value.currency) \(NSDecimalNumber(decimal: amount).stringValue)").monospacedDigit() }
        else { Text("coopflow.amount.unknown").foregroundStyle(.secondary) }
    }
}
struct CoopFlowFields: View {
    let value: CoopFlowJSON
    let keys: [String]
    var body: some View {
        ForEach(keys, id: \.self) { key in
            if let text = value[key].text {
                LabeledContent(LocalizedStringKey("coopflow.field." + String(key))) { Text(text).textSelection(.enabled) }
            } else if let flag = value[key].flag {
                LabeledContent(LocalizedStringKey("coopflow.field." + String(key))) { Text(flag ? "coopflow.yes" : "coopflow.no") }
            }
        }
    }
}
@MainActor struct CoopFlowSettlementDetail: View {
    let reader: any CoopFlowReading
    let source: CoopFlowSettlement.Source
    let id: Int
    @State private var row: CoopFlowSettlement?
    @State private var scope: CoopFlowSession?
    @State private var failed = false
    var body: some View {
        List {
            if scope == reader.session, let row {
                Section { CoopFlowMoneyLabel(value: row.amount); Text(LocalizedStringKey("coopflow.status." + String(row.status))) }
                CoopFlowFields(value: row.record, keys: ["topicName", "topicId", "payeeType", "totalSales", "verifiedSales", "platformAmount", "merchantTotal", "merchantPaid", "shareMode", "shareRate", "fixedFee", "verifiedHeads", "createTime", "settleTime", "payableTime", "payoutTime", "merchantPayableTime", "merchantPayoutTime", "updateTime"])
                Section { CoopFlowSafetyNotice() }
            } else if failed { Text("coopflow.read.failed") }
            else { ProgressView("cooperation.loading") }
        }.navigationTitle("coopflow.settlement.detail")
            .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0)") {
                row = nil; scope = nil; failed = false
                let captured = reader.session
                do {
                    let result = try await reader.settlement(source: source, id: id)
                    guard !Task.isCancelled, reader.session == captured else { return }
                    row = result; scope = captured
                } catch { guard !Task.isCancelled, reader.session == captured else { return }; failed = true }
            }
    }
}
