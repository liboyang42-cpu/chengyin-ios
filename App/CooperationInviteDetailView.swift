import SwiftUI
import UIKit

@MainActor struct CooperationInviteDetailView: View {
    let key: CooperationInviteKey
    let reader: any CooperationReading
    var peerReader: (any CoopFlowReading)? = nil
    private struct CopyHost: Hashable { let reader: ObjectIdentifier; let key: CooperationInviteKey }
    var body: some View {
        CooperationInviteDetailContent(key: key, reader: reader, peerReader: peerReader)
            .id(CopyHost(reader: ObjectIdentifier(reader), key: key))
    }
}

@MainActor private struct CooperationInviteDetailContent: View {
    let key: CooperationInviteKey
    let reader: any CooperationReading
    var peerReader: (any CoopFlowReading)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var phoneCopy: CooperationPhoneCopyOwner
    init(key: CooperationInviteKey, reader: any CooperationReading, peerReader: (any CoopFlowReading)? = nil) {
        self.key = key; self.reader = reader; self.peerReader = peerReader
        _phoneCopy = StateObject(wrappedValue: CooperationPhoneCopyOwner(reader: reader, key: key))
    }
    var body: some View {
        CooperationReadScreen(reader: reader, resource: "invite.\(key.direction.rawValue).\(key.id)", operation: {
            guard key.id > 0 else { throw CooperationReadFailure.unavailable }
            return try await phoneCopy.load(reader: reader, key: key)
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
                // Mini-program invite detail lists the two parties first (utils/coop-invite-view.js TYPE_LABEL).
                if let type = row.inviteType, (0...2).contains(type) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("cooperation.parties").font(.caption).foregroundStyle(.secondary)
                        Text(LocalizedStringKey("cooperation.inviteType." + String(type)))
                    }.padding(.vertical, 2).accessibilityElement(children: .combine)
                        .accessibilityIdentifier("cooperation.detail.parties")
                }
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
                    if let intent = phoneCopy.intent(detail: detail, reader: reader, key: key) {
                        Button("cooperation.phone.copy") {
                            phoneCopy.copy(intent) { phone in
                                UIPasteboard.general.setItems([["public.utf8-plain-text": phone]],
                                    options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                            }
                        }.accessibilityIdentifier("cooperation.phone.copy")
                    }
                    if let result = phoneCopy.resultKey {
                        Text(LocalizedStringKey(result)).accessibilityIdentifier("cooperation.phone.copy.result")
                    }
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
        .onAppear { phoneCopy.appear(active: scenePhase == .active) }
        .onDisappear { phoneCopy.disappear() }
        .onChange(of: scenePhase) { _, phase in phoneCopy.sceneChanged(active: phase == .active) }
        .onChange(of: reader.scope) { _, _ in phoneCopy.retire() }
        .onChange(of: ObjectIdentifier(reader)) { _, _ in phoneCopy.retire() }
        .onChange(of: key) { _, _ in phoneCopy.retire() }
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

/// A local device action belongs to one successful detail read and one explicit gesture.
@MainActor final class CooperationPhoneCopyOwner: ObservableObject {
    struct Intent {
        fileprivate let id: UUID
        fileprivate let readID: UUID
        fileprivate let scope: UUID
        fileprivate let phone: String
    }
    private let reader: any CooperationReading
    private let key: CooperationInviteKey
    private var visible = false, active = false
    private var readID = UUID(), gestureID = UUID()
    private var loadedScope: UUID?
    private var detail: CooperationInviteDetail?
    @Published private var result: String?
    @Published private var revision = 0
    init(reader: any CooperationReading, key: CooperationInviteKey) { self.reader = reader; self.key = key }
    private var current: Bool {
        reader.isConfigured && reader.isAuthenticated && loadedScope == reader.scope
    }
    var resultKey: String? { visible && active && current ? result : nil }
    func appear(active: Bool) {
        visible = true; self.active = active
        if !active { retire() }
    }
    func disappear() { visible = false; active = false; retire() }
    func sceneChanged(active: Bool) {
        self.active = visible && active
        if !self.active { retire() }
    }
    func retire() {
        readID = UUID(); gestureID = UUID(); loadedScope = nil; detail = nil; result = nil; revision += 1
    }
    func load(reader supplied: any CooperationReading, key suppliedKey: CooperationInviteKey) async throws -> CooperationInviteDetail {
        // The original read remains authoritative even when local copying is unavailable.
        let observes = suppliedKey == key && ObjectIdentifier(supplied) == ObjectIdentifier(reader)
        if observes { retire() }
        let request = readID, scope = supplied.scope
        let value = try await supplied.detail(key: suppliedKey)
        if observes, !Task.isCancelled, request == readID, scope == reader.scope,
           reader.isConfigured, reader.isAuthenticated, value.row.id == key.id {
            detail = value; loadedScope = scope; revision += 1
        }
        return value
    }
    func intent(detail displayed: CooperationInviteDetail, reader supplied: any CooperationReading,
                key suppliedKey: CooperationInviteKey) -> Intent? {
        guard visible, active, current, suppliedKey == key,
              ObjectIdentifier(supplied) == ObjectIdentifier(reader), let detail, detail == displayed,
              let phone = detail.row.partner?.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let displayedPhone = displayed.row.partner?.phone, phone.utf8.elementsEqual(displayedPhone.utf8),
              let loadedScope else { return nil }
        return Intent(id: gestureID, readID: readID, scope: loadedScope, phone: phone)
    }
    @discardableResult func copy(_ intent: Intent, write: (String) throws -> Void) -> Bool {
        guard visible, active, current, intent.id == gestureID, intent.readID == readID,
              intent.scope == loadedScope, let phone = detail?.row.partner?.phone,
              phone.utf8.elementsEqual(intent.phone.utf8) else { return false }
        let completion = UUID(); gestureID = completion; result = nil
        do {
            try write(phone)
            guard visible, active, current, gestureID == completion, readID == intent.readID else { return true }
            result = "cooperation.phone.copied"
        } catch {
            guard visible, active, current, gestureID == completion, readID == intent.readID else { return false }
            result = "cooperation.phone.copyFailed"
            return false
        }
        return true
    }
}
