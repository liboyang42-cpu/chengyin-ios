import SwiftUI

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
                else { Text(raw) }
            }
        } label: { Text(LocalizedStringKey("merchant.business.field." + String(key))) }
        .font(.subheadline)
    }
    static let stateKeys = ["processing", "merchantOpinion", "status", "decision", "roleCode", "displayState", "settlementState", "refundState", "paymentState", "invoiceState", "holdState", "netDirection", "tier", "sourceType"]
    static let knownStates: Set<String> = ["WAITING_PLATFORM_REVIEW", "PLATFORM_REJECTED", "REFUND_PROCESSING", "MANUAL_REFUND_PENDING", "MANUAL_REFUND_REVIEW", "REFUNDED", "UNKNOWN", "PENDING", "AGREE", "REJECT", "EVIDENCE", "VISIBLE", "PENDING_REVIEW", "HIDDEN", "ACTIVE", "REVOKED", "ACCEPTED", "EXPIRED", "MERCHANT_MANAGER", "MERCHANT_CHECKIN", "MERCHANT_MARKETING", "MERCHANT_FINANCE", "NO_CASH_SETTLEMENT", "PENDING_SETTLEMENT", "SETTLED", "REVIEWING", "REJECTED", "REFUNDING", "PAID", "PLATFORM_PAYS_MERCHANT", "MERCHANT_PAYS_PLATFORM", "pending", "abnormal", "dormant", "repeat", "new", "TOPIC", "ACTIVITY", "MIXED"]
}
struct MerchantBusinessRecordFields: View {
    let row: MerchantBusinessRecord
    let access: MerchantBusinessAccess
    var compact: Bool
    private var keys: [String] {
        switch row.kind {
        case .customer: return compact ? ["tier", "lastAction", "lastTime"] : ["phone", "contactHint", "arrivedCount", "pendingCount", "refundedCount", "paidAmount", "lastInteractionTime", "lastTime", "latestNote", "teamName", "roleName"]
        case .refund: return compact ? ["processing", "merchantOpinion", "refundAmount"] : ["sourceType", "sourceId", "refundAmount", "reason", "processing", "merchantOpinion", "refundPolicyCode", "refundPolicyVersion", "refundDeadline", "createTime"]
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
                MerchantBusinessField(key: key, value: value, money: moneyKeys.contains(key))
            }
        }
        if row.kind == .redemption, access.allows("merchant:finance:read"), row.fields["settlementAmount"] == nil || row.fields["settlementAmount"] == .null {
            Text(row.fields.mbText("displayState") == "NO_CASH_SETTLEMENT" ? "merchant.business.noCash" : "merchant.business.amountPending").font(.footnote).foregroundStyle(.secondary)
        }
        if row.kind == .customer, row.fields["paidAmount"] == nil || row.fields["paidAmount"] == .null {
            Text("merchant.business.sensitiveUnavailable").font(.footnote).foregroundStyle(.secondary)
        }
        if row.kind == .review, let images = row.fields["imageUrls"]?.array, !images.isEmpty {
            NavigationLink {
                List {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        if let value = image.string, MerchantBusinessRecord.safeHTTPS(value), let url = URL(string: value) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFit().accessibilityLabel(Text("merchant.business.reviewImage"))
                                case .failure: Label("merchant.business.imageUnavailable", systemImage: "photo.badge.exclamationmark")
                                default: ProgressView()
                                }
                            }.frame(minHeight: 120).accessibilityIdentifier("merchant.business.image.\(index)")
                        }
                    }
                }.navigationTitle("merchant.business.imagesAvailable")
            } label: { Label("merchant.business.imagesAvailable", systemImage: "photo.on.rectangle") }
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
