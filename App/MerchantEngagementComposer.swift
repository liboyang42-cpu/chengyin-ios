import SwiftUI

struct MerchantEngagementEditorContext: Identifiable {
    enum Kind { case segment, campaign, broadcast, invitation }
    let id = UUID()
    let kind: Kind
}
@MainActor struct MerchantEngagementComposer: View {
    @Environment(\.dismiss) private var dismiss
    let context: MerchantEngagementEditorContext
    let filter: MerchantCRMFilter
    let segments: [MerchantSavedSegment]
    let coupons: [MerchantCampaignCoupon]
    let canCoupon: Bool
    let onPrepare: (MerchantEngagementCommand) -> Void
    @State private var name = ""
    @State private var title = ""
    @State private var content = ""
    @State private var segmentID = 0
    @State private var couponID = 0
    @State private var channel: MerchantCampaignChannel = .inApp
    @State private var audienceScope: MerchantBroadcastScope = .all
    @State private var groupText = ""
    @State private var inviteToken = ""
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                Text("merchant.engagement.localDraft").font(.footnote)
                switch context.kind {
                case .segment:
                    TextField("merchant.engagement.segmentName", text: $name).accessibilityIdentifier("merchant.engagement.editor.name")
                    MerchantCRMFilterSummary(filter: filter, export: false)
                case .campaign:
                    Picker("merchant.engagement.selectedSegment", selection: $segmentID) {
                        Text("merchant.engagement.choose").tag(0)
                        ForEach(segments) { Text($0.name ?? "#\($0.id)").tag($0.id) }
                    }
                    Picker("merchant.engagement.channel", selection: $channel) {
                        Text("merchant.engagement.channel.IN_APP").tag(MerchantCampaignChannel.inApp)
                        if canCoupon { Text("merchant.engagement.channel.COUPON").tag(MerchantCampaignChannel.coupon) }
                    }
                    if channel == .coupon {
                        Picker("merchant.engagement.selectedCoupon", selection: $couponID) {
                            Text("merchant.engagement.choose").tag(0); ForEach(coupons) { Text($0.name ?? "#\($0.id)").tag($0.id) }
                        }
                    }
                    TextField("merchant.engagement.messageTitle", text: $title).accessibilityIdentifier("merchant.engagement.editor.title")
                    TextField("merchant.engagement.messageContent", text: $content, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("merchant.engagement.editor.content")
                case .broadcast:
                    MerchantCRMFilterSummary(filter: filter, export: false)
                    Picker("merchant.engagement.audienceScope", selection: $audienceScope) {
                        ForEach(MerchantBroadcastScope.allCases, id: \.self) { Text(LocalizedStringKey("merchant.engagement.scope." + ($0.rawValue))).tag($0) }
                    }
                    if audienceScope != .all { TextField("merchant.engagement.groupNames", text: $groupText, axis: .vertical).lineLimit(2...5) }
                    TextField("merchant.engagement.broadcastContent", text: $content, axis: .vertical).lineLimit(3...7).accessibilityIdentifier("merchant.engagement.editor.content")
                case .invitation:
                    SecureField("merchant.engagement.inviteToken", text: $inviteToken).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("merchant.engagement.editor.inviteToken")
                    Text("merchant.engagement.invitationUnknownTarget").font(.footnote)
                }
                if invalid { Text("merchant.business.invalid").foregroundStyle(.red) }
                Button("merchant.engagement.previewReview") {
                    do { onPrepare(try command()) } catch { invalid = true }
                }.accessibilityIdentifier("merchant.engagement.editor.review")
            }
            .navigationTitle("merchant.engagement.localActions")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } } }
            .onAppear { segmentID = segments.first?.id ?? 0; couponID = coupons.first?.id ?? 0 }
            .onDisappear { inviteToken = "" }
        }
    }
    private func command() throws -> MerchantEngagementCommand {
        switch context.kind {
        case .segment: return .saveSegment(name: try MerchantEngagementValidation.text(name, minimum: 1, maximum: 30), filter: filter)
        case .campaign: return .createCampaign(try .init(segmentID: segmentID, channel: channel, couponID: couponID > 0 ? couponID : nil, title: title, content: content))
        case .broadcast:
            let groups = groupText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return .broadcast(try .init(audience: .init(filter: filter, scope: audienceScope, groups: groups), content: content))
        case .invitation: return .acceptInvitation(try .init(token: inviteToken))
        }
    }
}
struct MerchantCRMFilterSummary: View {
    let filter: MerchantCRMFilter
    let export: Bool
    var body: some View {
        LabeledContent("merchant.business.search", value: filter.keyword.isEmpty ? "—" : filter.keyword)
        LabeledContent { Text(LocalizedStringKey("merchant.business.segment." + (filter.segment))) } label: { Text("merchant.business.segment") }
        LabeledContent("merchant.engagement.tagID", value: filter.tagID.map(String.init) ?? "—")
        LabeledContent("merchant.business.sourceType", value: filter.sourceType.map(String.init) ?? "—")
        LabeledContent("merchant.business.sourceStart", value: filter.sourceStart ?? "—")
        LabeledContent("merchant.business.sourceEnd", value: filter.sourceEnd ?? "—")
        if export { Text("merchant.engagement.exportFilterExact").font(.footnote) }
    }
}
@MainActor struct MerchantEngagementReviewView: View {
    let review: MerchantEngagementReview
    let enabled: Bool
    var synthetic = true
    let busy: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section("merchant.engagement.frozenReview") {
                    Text(LocalizedStringKey("merchant.engagement.command." + (review.command.key))).font(.headline)
                    LabeledContent("merchant.engagement.accountID", value: String(review.scope.accountID))
                    if let merchant = review.proof.access.merchantID { LabeledContent("merchant.business.storeID", value: String(merchant)) }
                    details
                }
                if let audience = review.proof.audience {
                    Section("merchant.engagement.serverAudience") {
                        MerchantEngagementCounts(counts: audience.counts)
                        Text("merchant.engagement.audienceBoundary").font(.footnote)
                    }.accessibilityIdentifier("merchant.engagement.audience")
                }
                if let task = review.proof.campaign { Section("merchant.engagement.taskDetails") { MerchantCampaignTaskFields(task: task) } }
                Text("merchant.engagement.reviewRefresh").font(.footnote)
                if enabled && (synthetic || (try? review.command.validateProductionProof(review.proof)) != nil) {
                    Text(LocalizedStringKey(synthetic ? "merchant.engagement.synthetic" : "merchant.engagement.productionReview"))
                    Button(LocalizedStringKey(synthetic ? "merchant.engagement.confirmSynthetic" : "merchant.engagement.confirmProduction"), action: confirm).disabled(busy).accessibilityIdentifier("merchant.engagement.confirm")
                } else {
                    Text("merchant.engagement.actionUnavailable").accessibilityIdentifier("merchant.engagement.liveDisabled")
                    if !synthetic, let task = review.proof.campaign, !task.hasReviewableMessage { Text("merchant.engagement.messageUnavailable").font(.footnote) }
                }
                Button("action.cancel", action: cancel).disabled(busy).accessibilityIdentifier("merchant.engagement.cancelReview")
            }.navigationTitle("merchant.engagement.previewReview").interactiveDismissDisabled(busy)
        }
    }
    @ViewBuilder private var details: some View {
        switch review.command {
        case .saveSegment(let name, let filter): Text(name); MerchantCRMFilterSummary(filter: filter, export: false)
        case .createCampaign(let draft):
            LabeledContent("merchant.engagement.selectedSegment", value: review.proof.selectedSegment?.name ?? "#\(draft.segmentID)")
            Text(LocalizedStringKey("merchant.engagement.channel." + (draft.channel.rawValue)))
            if let coupon = review.proof.selectedCoupon { LabeledContent("merchant.engagement.selectedCoupon", value: coupon.name ?? "#\(coupon.id)") }
            Text(draft.title).font(.headline); Text(draft.content); Text("merchant.engagement.createStepBoundary").font(.footnote)
        case .dispatchCampaign, .retryCampaign: Text("merchant.engagement.dispatchBoundary").font(.footnote)
        case .broadcast(let draft):
            MerchantCRMFilterSummary(filter: draft.audience.filter, export: false)
            Text(LocalizedStringKey("merchant.engagement.scope." + (draft.audience.scope.rawValue)))
            ForEach(draft.audience.groups, id: \.self) { Text($0) }; Text(draft.content)
        case .createExport(let filter): MerchantCRMFilterSummary(filter: filter, export: true); Text("merchant.engagement.exportPrivacy").font(.footnote)
        case .downloadExport(let ticket, _, _): LabeledContent("merchant.engagement.taskID", value: String(ticket.task.id)); Text("merchant.engagement.noAutomaticSharing").font(.footnote)
        case .contact(let customer, let purpose):
            LabeledContent("merchant.engagement.customerID", value: String(customer.rawValue))
            if let name = review.proof.customer?.rows.first?.title { Text(name) }
            Text(LocalizedStringKey("merchant.engagement.contact." + (purpose.rawValue))); Text("merchant.engagement.contactPrivacy").font(.footnote)
        case .acceptInvitation: Text("merchant.engagement.invitationUnknownTarget"); Text("merchant.engagement.invitationConsequence").font(.footnote)
        case .uploadEvidence(let refund, let selection, _, _):
            LabeledContent("merchant.engagement.refundID", value: String(refund.rawValue)); Text(selection.filename)
            LabeledContent("merchant.engagement.byteCount", value: String(selection.bytes.count)); Text("merchant.engagement.evidenceNotSubmitted").font(.footnote)
        }
    }
}
