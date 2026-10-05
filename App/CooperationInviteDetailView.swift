import SwiftUI

@MainActor struct CooperationInviteDetailView: View {
    let key: CooperationInviteKey
    let reader: any CooperationReading
    var peerReader: (any CoopFlowReading)? = nil
    var body: some View {
        CooperationReadScreen(reader: reader, resource: "invite.\(key.direction.rawValue).\(key.id)", operation: {
            guard key.id > 0 else { throw CooperationReadFailure.unavailable }
            return try await reader.detail(key: key)
        }) { detail in
            let row = detail.row
            Section {
                CooperationName(name: row.partner?.name).font(.title2.weight(.semibold))
                    .accessibilityIdentifier("cooperation.detail.partner")
                CooperationStatus(key: row.statusKey, symbol: row.status == 0 ? "clock" : row.status == 1 ? "checkmark.circle" : "circle")
                Text(LocalizedStringKey(key.direction == .received ? "cooperation.received" : "cooperation.sent")).font(.subheadline).foregroundStyle(.secondary)
                CooperationField(key: "cooperation.inviteID", value: "#\(row.id)")
                if let topic = row.topicId { CooperationTopicReference(id: topic) }
                CooperationTimeField(key: "cooperation.created", value: row.createTime)
                CooperationTimeField(key: "cooperation.expires", value: row.expireTime)
            }
            if let peerReader, let peer = CoopPeerMember(direction: key.direction, fromType: row.fromType, fromID: row.fromId, toType: row.toType, toID: row.toId) {
                Section { NavigationLink("context.coop.peerCredit") { CoopPeerCreditView(reader: peerReader, peer: peer) } }
            }
            Section("cooperation.terms") {
                terms(row)
                if row.termsFrozen { Label("cooperation.termsFrozen", systemImage: "lock") }
                if let occupancy = detail.occupancy {
                    CooperationField(key: occupancy.kind == .gamePending ? "cooperation.slot.game" : "cooperation.slot.topic", value: "\(occupancy.count) / \(occupancy.capacity)")
                }
                CooperationField(key: "cooperation.message", value: row.message)
                CooperationField(key: "cooperation.handleReason", value: row.handleReason)
            }
            if row.partner?.leaderName?.isEmpty == false || row.partner?.phone?.isEmpty == false {
                Section("cooperation.contact") {
                    // Display only fields actually returned; never create a conversation or infer contact data.
                    CooperationField(key: "cooperation.leader", value: row.partner?.leaderName)
                    CooperationField(key: "cooperation.phone", value: row.partner?.phone)
                }
            }
            if !row.legacyReadonly && (row.depositOwed || row.depositRefundPending) {
                Section("cooperation.deposit") {
                    if row.depositOwed {
                        Label("cooperation.depositOwed", systemImage: "info.circle")
                        if let amount = row.depositAmount { CooperationField(key: "cooperation.depositAmount", value: number(amount)); Text("cooperation.currencyUnknown").font(.footnote).foregroundStyle(.secondary) }
                        else { Text("cooperation.amountUnknown").foregroundStyle(.secondary) }
                    }
                    if row.depositRefundPending { Label("cooperation.refundPending", systemImage: "clock") }
                    Text("cooperation.financeUnavailable").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if row.legacyReadonly { Label("cooperation.legacy", systemImage: "archivebox") }
                CooperationReadOnlyNotice()
            }
        }
        .appNavigationTitle("cooperation.detail.title")
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func terms(_ row: CooperationInvite) -> some View {
        switch row.shareMode {
        case 0: Text("cooperation.terms.traffic")
        case 1:
            Text("cooperation.terms.share")
            if let rate = row.shareRate { CooperationField(key: "cooperation.shareRate", value: "\(number(rate))%") }
            else { Text("cooperation.amountUnknown").foregroundStyle(.secondary) }
        case 2:
            Text("cooperation.terms.fixed")
            if let fee = row.fixedFee { CooperationField(key: "cooperation.fixedFee", value: number(fee)); Text("cooperation.currencyUnknown").font(.footnote).foregroundStyle(.secondary) }
            else { Text("cooperation.amountUnknown").foregroundStyle(.secondary) }
        default: Text("cooperation.termsUnknown").foregroundStyle(.secondary)
        }
    }
    private func number(_ value: Double) -> String {
        // No default amount, exchange rate, estimated deposit or contract total.
        value.formatted(.number.precision(.fractionLength(0...8)))
    }
}
