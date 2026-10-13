import SwiftUI
import UIKit

struct MerchantBusinessField: View {
    let key: String
    let value: MerchantBusinessValue
    var money = false
    var body: some View {
        LabeledContent {
            if money { Text((try? MerchantBusinessMoney(value).display) ?? "—").monospacedDigit() }
            else if let boolean = value.bool { Text(boolean ? "merchant.business.yes" : "merchant.business.no") }
            else if value == .null { Text("merchant.business.notProvided").foregroundStyle(.secondary) }
            else if let raw = value.numberText {
                if Self.stateKeys.contains(key), Self.knownStates.contains(raw) { Text(LocalizedStringKey("merchant.business.state." + String(raw))) }
                else if key == "replyRatePct" { Text("\(raw)%").monospacedDigit() }
                else { Text(raw) }
            }
        } label: { Text(LocalizedStringKey("merchant.business.field." + String(key))) }
        .font(.subheadline)
    }
    static let stateKeys = ["processing", "merchantOpinion", "status", "decision", "roleCode", "displayState", "settlementState", "refundState", "paymentState", "invoiceState", "holdState", "netDirection", "tier", "sourceType"]
    static let knownStates: Set<String> = ["WAITING_PLATFORM_REVIEW", "PLATFORM_REJECTED", "REFUND_PROCESSING", "MANUAL_REFUND_PENDING", "MANUAL_REFUND_REVIEW", "REFUNDED", "UNKNOWN", "PENDING", "AGREE", "REJECT", "EVIDENCE", "VISIBLE", "PENDING_REVIEW", "HIDDEN", "ACTIVE", "REVOKED", "ACCEPTED", "EXPIRED", "MERCHANT_MANAGER", "MERCHANT_CHECKIN", "MERCHANT_MARKETING", "MERCHANT_FINANCE", "NO_CASH_SETTLEMENT", "PENDING_SETTLEMENT", "SETTLED", "REVIEWING", "REJECTED", "REFUNDING", "PAID", "PLATFORM_PAYS_MERCHANT", "MERCHANT_PAYS_PLATFORM", "pending", "abnormal", "dormant", "repeat", "new", "TOPIC", "ACTIVITY", "MIXED"]
}
@MainActor struct MerchantBusinessRecordFields: View {
    let row: MerchantBusinessRecord
    let access: MerchantBusinessAccess
    var compact: Bool
    var settlementEntries = false
    var reviewPhotoOwner: MerchantBusinessViewModel? = nil
    var settlementReader: (any MerchantBusinessReading)? = nil
    var settlementSnapshot: (() -> MerchantBusinessSnapshot?)? = nil
    private var keys: [String] {
        switch row.kind {
        case .customer: return compact ? ["tier", "lastAction", "lastTime"] : ["phone", "contactHint", "arrivedCount", "pendingCount", "refundedCount", "paidAmount", "lastInteractionTime", "lastTime", "latestNote", "teamName", "roleName"]
        case .refund: return compact ? ["customerNickname", "activityTitle", "reason", "processing", "merchantOpinion", "refundAmount"] : ["sourceType", "sourceId", "customerNickname", "activityTitle", "refundAmount", "reason", "processing", "merchantOpinion", "refundPolicyCode", "refundPolicyVersion", "refundDeadline", "createTime"]
        case .review: return ["rating", "content", "verifiedRedemption", "status", "merchantReply", "createTime", "repliedAt", "version"]
        case .redemption: return compact ? ["displayState", "settlementAmount", "noCashReason", "refundState"] : ["topicName", "chapterName", "storeName", "customerDisplayName", "verificationCodeTail", "fulfillmentState", "settlementState", "settlementRoute", "displayState", "settlementAmount", "noCashReason", "refundState", "occurredAt", "unitFee", "headCount"]
        case .entry: return ["entryKind", "settlementRoute", "source", "destination", "signedAmount", "headCount", "displayState", "occurredAt", "arrivalAt"]
        case .batch: return ["periodYm", "amountTotal", "netDirection", "paymentState", "invoiceState", "holdState", "displayState", "paidAt", "payVoucherNo"]
        case .operatorMember: return ["roleCode", "status", "acceptedAt", "version"]
        case .invite: return ["roleCode", "status", "expiresAt", "version"]
        case .role: return ["roleCode", "name"]
        case .timeline: return ["type", "description", "occurredAt", "noteVersion", "correctsNoteId"]
        case .tag: return ["tagName", "tagColor"]
        case .response: return ["decision", "content", "actorRoleCode", "createTime"]
        case .verification: return ["verificationCodeTail", "topicName", "chapterName", "customerDisplayName", "operatorName", "createTime", "occurredAt", "status"]
        }
    }
    private let moneyKeys: Set<String> = ["paidAmount", "refundAmount", "settlementAmount", "signedAmount", "amountTotal", "unitFee"]
    private let financeKeys: Set<String> = ["settlementAmount", "settlementState", "settlementRoute", "displayState", "unitFee", "headCount"]
    var body: some View {
        ForEach(keys, id: \.self) { key in
            if visible(key), let value = row.fields[key] {
                if settlementEntries, row.kind == .entry, key == "signedAmount" {
                    let entry = MerchantSettlementEntryPresentation(fields: row.fields)
                    LabeledContent("merchant.business.field.signedAmount") {
                        if let amount = entry.amount { Text(verbatim: amount).monospacedDigit() }
                        else { Text("merchant.business.amountPending").foregroundStyle(.secondary) }
                    }.font(.subheadline)
                        .accessibilityIdentifier("merchant.settlementEntry.amount")
                } else if row.kind == .batch, key == "paidAt" {
                    LabeledContent("merchant.business.field.paidAt") {
                        MerchantSettlementTimestampText(raw: value.string)
                    }.font(.subheadline)
                } else {
                    MerchantBusinessField(key: key, value: value, money: moneyKeys.contains(key))
                }
            }
        }
        if settlementEntries, row.kind == .entry {
            Text(LocalizedStringKey(MerchantSettlementEntryPresentation(fields: row.fields).sourceKey))
                .font(.subheadline).accessibilityIdentifier("merchant.settlementEntry.meaning")
            if row.fields["signedAmount"] == nil {
                Text("merchant.business.amountPending").foregroundStyle(.secondary)
            }
        }
        if row.kind == .refund, !compact, let reader = settlementReader,
           let currentSnapshot = settlementSnapshot, let snapshot = currentSnapshot(),
           MerchantRefundNumberCopyModel.number(in: row, snapshot: snapshot) != nil {
            MerchantRefundNumberCopyView(row: row, snapshot: snapshot, reader: reader, currentSnapshot: currentSnapshot)
                .id(MerchantRefundNumberCopyModel.displayIdentity(row))
        }
        if row.kind == .customer, compact {
            MerchantCustomerContactSummary(record: row, access: access)
        }
        if row.kind == .batch, !compact, access.allows("merchant:finance:read"),
           let reader = settlementReader, let currentSnapshot = settlementSnapshot,
           let progress = try? MerchantSettlementProgress(record: row) {
            MerchantSettlementProgressView(progress: progress, reader: reader, currentSnapshot: currentSnapshot)
                .id(row.id)
        }
        if row.kind == .redemption, !compact,
           let progress = MerchantRedemptionProgress(record: row, access: access) {
            MerchantRedemptionProgressView(progress: progress)
        }
        if row.kind == .redemption, !compact, let reader = settlementReader, let currentSnapshot = settlementSnapshot {
            MerchantPersonalIncomeEntry(row: row, reader: reader, currentSnapshot: currentSnapshot)
        }
        if row.kind == .redemption, access.allows("merchant:finance:read"), row.fields["settlementAmount"] == nil || row.fields["settlementAmount"] == .null {
            Text(row.fields.mbText("displayState") == "NO_CASH_SETTLEMENT" ? "merchant.business.noCash" : "merchant.business.amountPending").font(.footnote).foregroundStyle(.secondary)
        }
        if row.kind == .customer, row.fields["paidAmount"] == nil || row.fields["paidAmount"] == .null {
            Text("merchant.business.sensitiveUnavailable").font(.footnote).foregroundStyle(.secondary)
        }
        if row.kind == .review, let reviewPhotoOwner {
            MerchantReviewPhotoGalleryEntry(owner: reviewPhotoOwner, row: row)
                .id(ObjectIdentifier(reviewPhotoOwner))
        }
    }
    private func visible(_ key: String) -> Bool {
        if key == "paidAmount" { return access.allows("merchant:crm:sensitive:read") }
        if row.kind == .redemption && financeKeys.contains(key) {
            guard access.allows("merchant:finance:read") else { return false }
            if !compact { return ["settlementState", "settlementRoute", "displayState"].allSatisfy { row.fields.mbText($0) != nil } }
        }
        return true
    }
}

@MainActor struct MerchantScanPreviewView: View {
    @State private var raw = ""
    @State private var preview: MerchantRedemptionContext?
    @State private var issue: String?
    var body: some View {
        Form {
            Section {
                Text("merchant.business.scanBoundary")
                SecureField("merchant.business.scanInput", text: $raw).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("merchant.business.scanInput")
                Button("merchant.business.previewRoute") {
                    do { preview = try .parse(raw); issue = nil }
                    catch { preview = nil; issue = error as? MerchantRedemptionFailure == .unsupported ? "merchant.business.unsupportedCode" : "merchant.business.invalid" }
                    raw = ""
                }.disabled(raw.isEmpty).accessibilityIdentifier("merchant.business.previewRoute")
            }
            if let preview {
                Section("merchant.business.preview") {
                    Text(LocalizedStringKey("merchant.business.scanKind." + String(preview.kind.rawValue)))
                    Text(preview.endpoint).font(.caption).textSelection(.enabled)
                    Text("merchant.business.unverifiedCode").foregroundStyle(.secondary)
                    Text("merchant.business.disabled").font(.footnote)
                }.accessibilityIdentifier("merchant.business.routePreview")
            }
            if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) }
        }.appNavigationTitle("merchant.business.scan")
        .onDisappear { raw = ""; preview = nil }
    }
}


/// A local action bound to the exact displayed refund and its original read context.
@MainActor final class MerchantRefundNumberCopyModel: ObservableObject {
    @Published private(set) var intentID = UUID()
    @Published private(set) var copied = false
    private let row: MerchantBusinessRecord
    private let snapshot: MerchantBusinessSnapshot
    private let reader: any MerchantBusinessReading
    private let scope: MerchantBusinessScope?
    private let authorization: UUID?
    private let currentSnapshot: () -> MerchantBusinessSnapshot?
    private var visible = false
    private var active = false
    private var retired = false

    init(row: MerchantBusinessRecord, snapshot: MerchantBusinessSnapshot, reader: any MerchantBusinessReading,
         currentSnapshot: @escaping () -> MerchantBusinessSnapshot?) {
        self.row = row; self.snapshot = snapshot; self.reader = reader
        scope = reader.scope; authorization = reader.authorizationGeneration
        self.currentSnapshot = currentSnapshot
    }
    static func displayIdentity(_ row: MerchantBusinessRecord) -> [Data] {
        [Data(row.id.utf8), Data((row.fields["refundNo"]?.string ?? "").utf8)]
    }
    static func number(in row: MerchantBusinessRecord, snapshot: MerchantBusinessSnapshot) -> String? {
        guard row.kind == .refund, snapshot.access.allows("merchant:aftercare:read"),
              case .refund(let id) = snapshot.document.query, row.id == String(id.rawValue),
              snapshot.document.rows.filter({ $0.kind == .refund }).count == 1,
              snapshot.document.rows.contains(row), let number = row.fields["refundNo"]?.string,
              !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return number
    }
    private var matches: Bool {
        !retired && scope != nil && reader.isConfigured && reader.scope == scope &&
            reader.authorizationGeneration == authorization && currentNumberMatches
    }
    private var currentNumberMatches: Bool {
        guard let current = currentSnapshot(), current == snapshot,
              let currentRow = current.document.rows.first(where: { $0.kind == .refund && $0.id == row.id }),
              let original = Self.number(in: row, snapshot: snapshot),
              let latest = Self.number(in: currentRow, snapshot: current) else { return false }
        return original.utf8.elementsEqual(latest.utf8)
    }
    var canCopy: Bool { visible && active && matches }
    func appear(active: Bool) {
        visible = true; self.active = active; intentID = UUID(); copied = false
        if !matches { retire() }
    }
    func disappear() { visible = false; active = false; intentID = UUID(); copied = false }
    func sceneChanged(active: Bool) {
        self.active = visible && active; intentID = UUID(); copied = false
        if !matches { retire() }
    }
    func retire() { retired = true; active = false; intentID = UUID(); copied = false }
    @discardableResult func copy(intent: UUID, write: (String) -> Void) -> Bool {
        guard intent == intentID, visible, active else { return false }
        guard matches, let number = Self.number(in: row, snapshot: snapshot) else { retire(); return false }
        // Consume before the injected effect: a repeated or reentrant old callback cannot write twice.
        let completion = UUID(); intentID = completion
        write(number)
        if intentID == completion && matches && visible && active { copied = true }
        return true
    }
}

@MainActor private struct MerchantRefundNumberCopyView: View {
    let row: MerchantBusinessRecord
    let snapshot: MerchantBusinessSnapshot
    let reader: any MerchantBusinessReading
    @StateObject private var model: MerchantRefundNumberCopyModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    init(row: MerchantBusinessRecord, snapshot: MerchantBusinessSnapshot, reader: any MerchantBusinessReading,
         currentSnapshot: @escaping () -> MerchantBusinessSnapshot?) {
        self.row = row; self.snapshot = snapshot; self.reader = reader
        _model = StateObject(wrappedValue: MerchantRefundNumberCopyModel(row: row, snapshot: snapshot,
            reader: reader, currentSnapshot: currentSnapshot))
    }
    var body: some View {
        let intent = model.intentID
        let chinese = locale.languageCode == "zh"
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.copy(intent: intent) { text in
                    UIPasteboard.general.setItems([["public.utf8-plain-text": text]],
                        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                }
            } label: {
                Label { Text(verbatim: chinese ? "复制退款单号" : "Copy refund number") }
                    icon: { Image(systemName: "doc.on.doc") }
            }
            .disabled(!model.canCopy).accessibilityIdentifier("merchant.aftercare.copyRefundNumber")
            if model.copied {
                Text(verbatim: chinese ? "已复制" : "Copied").font(.footnote)
                    .accessibilityIdentifier("merchant.aftercare.copyRefundNumber.result")
            }
        }
        .onAppear { model.appear(active: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, value in model.sceneChanged(active: value == .active) }
        .onChange(of: reader.scope) { _, _ in model.retire() }
        .onChange(of: reader.authorizationGeneration) { _, _ in model.retire() }
        .onChange(of: snapshot) { _, _ in model.retire() }
        .onChange(of: row) { _, _ in model.retire() }
    }
}
