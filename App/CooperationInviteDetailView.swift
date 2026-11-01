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
    @Environment(\.cooperationProjectDestination) private var topicDestination
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var phoneCopy: CooperationPhoneCopyOwner
    @State private var openedTopic: Int?
    @State private var topicReturn: UInt64 = 0
    init(key: CooperationInviteKey, reader: any CooperationReading, peerReader: (any CoopFlowReading)? = nil) {
        self.key = key; self.reader = reader; self.peerReader = peerReader
        _phoneCopy = StateObject(wrappedValue: CooperationPhoneCopyOwner(reader: reader, key: key))
    }
    var body: some View {
        CooperationReadScreen(reader: reader, resource: "invite.\(key.direction.rawValue).\(key.id).return.\(topicReturn)", operation: {
            guard key.id > 0 else { throw CooperationReadFailure.unavailable }
            return try await phoneCopy.load(reader: reader, key: key)
        }) { detail in
            let row = detail.row
            let view = CooperationInvitePresentation(invite: row, direction: key.direction)
            Section {
                CooperationStatus(key: row.statusKey, symbol: row.status == 0 ? "clock" : row.status == 1 ? "checkmark.circle" : "circle")
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(key.direction == .received ? "cooperation.detail.from" : "cooperation.detail.to")).foregroundStyle(.secondary)
                    if let name = row.partner?.name, !name.isEmpty { Text(verbatim: name) } else { Text("cooperation.detail.counterparty") }
                }.font(.title3.weight(.semibold)).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("cooperation.detail.partner")
                if let name = row.topicName { Text(verbatim: name).font(.headline) }
                if let topic = row.topicId {
                    CooperationTopicReference(id: topic)
                    CooperationProjectNavigationLink(topicID: topic, invite: key, destination: topicDestination, openedTopic: $openedTopic)
                }
                if let party = row.viewerPartyName {
                    LabeledContent { Text(verbatim: party) } label: { Text(LocalizedStringKey(key.direction == .received ? "cooperation.detail.receivingClub" : "cooperation.detail.sendingClub")) }
                        .accessibilityIdentifier("cooperation.detail.viewerParty")
                }
                CooperationField(key: "cooperation.inviteID", value: "#\(row.id)")
                CooperationTimeField(key: "cooperation.created", value: row.createTime)
                CooperationTimeField(key: "cooperation.expires", value: row.expireTime)
            }
            if let peerReader, let peer = CoopPeerMember(direction: key.direction, fromType: row.fromType, fromID: row.fromId, toType: row.toType, toID: row.toId) {
                Section { NavigationLink("context.coop.peerCredit") { CoopPeerCreditView(reader: peerReader, peer: peer) } }
            }
            Section("cooperation.detail.section.contact") {
                switch view.contact {
                case .visible(let text):
                    Text(verbatim: text).textSelection(.enabled).accessibilityIdentifier("cooperation.detail.contact")
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
                case .afterAcceptReceived: Text("cooperation.detail.contact.afterAcceptReceived").foregroundStyle(.secondary)
                case .afterAcceptSent: Text("cooperation.detail.contact.afterAcceptSent").foregroundStyle(.secondary)
                case .acceptedWithoutContact: Text("cooperation.detail.contact.none").foregroundStyle(.secondary)
                case .ended: Text("cooperation.detail.contact.ended").foregroundStyle(.secondary)
                }
            }
            Section("cooperation.detail.section.terms") {
                // Mini-program invite detail lists the two parties first (utils/coop-invite-view.js typeText).
                LabeledContent { CooperationInvitePartyText(view: view) } label: { Text("cooperation.parties") }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.detail.parties")
                LabeledContent { CooperationInviteTermsText(terms: view.terms) } label: { Text("cooperation.detail.share") }
                    .accessibilityIdentifier("cooperation.detail.terms")
                if let occupancy = detail.occupancy {
                    CooperationField(key: occupancy.kind == .gamePending ? "cooperation.slot.game" : "cooperation.slot.topic", value: "\(occupancy.count) / \(occupancy.capacity)")
                }
                LabeledContent { CooperationInviteDepositText(deposit: view.deposit) } label: { Text("cooperation.detail.section.deposit") }
                    .accessibilityIdentifier("cooperation.detail.deposit")
                if row.termsFrozen { Label("cooperation.termsFrozen", systemImage: "lock") }
            }
            Section("cooperation.detail.messages") {
                if let message = row.message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: message)
                        HStack(spacing: 4) {
                            Text(LocalizedStringKey(view.messageIsOurs ? "cooperation.detail.us" : "cooperation.detail.them"))
                            CooperationTimeField(key: "cooperation.created", value: row.createTime)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("cooperation.detail.message")
                }
                if let reason = row.handleReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: reason)
                        Text(LocalizedStringKey(view.handleReasonIsOurs ? "cooperation.detail.reason.us" : "cooperation.detail.reason.them")).font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("cooperation.detail.handleReason")
                }
                if (row.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (row.handleReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("cooperation.detail.noMessages").foregroundStyle(.secondary)
                }
                if view.input == .hidden && row.status == 1 && !row.legacyReadonly { Text("cooperation.detail.contactHint").font(.footnote).foregroundStyle(.secondary) }
            }
            CooperationInviteActionSections(view: view, peerReader: peerReader)
            if !row.legacyReadonly && row.depositRefundPending {
                Section("cooperation.deposit") {
                    Label("cooperation.refundPending", systemImage: "clock")
                    Text("cooperation.financeUnavailable").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section { CooperationReadOnlyNotice() }
        }
        .appNavigationTitle("cooperation.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { phoneCopy.appear(active: scenePhase == .active) }
        .onDisappear { phoneCopy.disappear() }
        .onChange(of: scenePhase) { _, phase in phoneCopy.sceneChanged(active: phase == .active) }
        .onChange(of: reader.scope) { _, _ in phoneCopy.retire(); openedTopic = nil }
        .onChange(of: ObjectIdentifier(reader)) { _, _ in phoneCopy.retire(); openedTopic = nil }
        .onChange(of: reader.isAuthenticated) { _, _ in openedTopic = nil }
        .onChange(of: key) { _, _ in phoneCopy.retire(); openedTopic = nil }
        .onChange(of: openedTopic) { previous, next in
            guard previous != nil, next == nil else { return }
            topicReturn &+= 1
        }
        .navigationDestination(item: $openedTopic) { topicID in
            CooperationProjectNavigationDestination(topicID: topicID, invite: key, destination: topicDestination)
        }
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
