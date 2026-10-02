import SwiftUI

/// A local immutable review, never a permission grant or agreement signature.
struct CoopFlowRequestPreview: View {
    @Environment(\.locale) private var locale
    let operation: CoopFlowMutation
    var body: some View {
        List {
            Section("coopflow.reviewAction") {
                if let body = try? operation.body(), case .object(let fields) = body {
                    ForEach(fields.keys.sorted(), id: \.self) { key in
                        LabeledContent(LocalizedStringKey("coopflow.field." + String(key))) {
                            Text(fields[key]?.text ?? fields[key]?.rows?.compactMap(\.text).joined(separator: ", ") ?? appLocalized("coopflow.notProvided", locale: locale))
                                .textSelection(.enabled)
                        }
                    }
                } else { Text("coopflow.invalid") }
            }
            Section { CoopFlowSafetyNotice(); Text("coopflow.review.local") }
            Button("coopflow.submit") {}.disabled(true).accessibilityIdentifier("coopflow.submit.disabled")
        }.navigationTitle("coopflow.reviewAction").accessibilityIdentifier("coopflow.review")
    }
}
struct CoopFlowTemplateEditor: View {
    @State private var name = ""
    @State private var type = 0
    @State private var retail = ""
    @State private var cost = ""
    @State private var quota = ""
    @State private var validEnd = ""
    private var operation: CoopFlowMutation? {
        guard let retail = Decimal(string: retail, locale: Locale(identifier: "en_US_POSIX")), let quota = Int(quota),
              cost.isEmpty || Decimal(string: cost, locale: Locale(identifier: "en_US_POSIX")) != nil,
              let draft = try? CoopFlowPerkTemplate(name: name, type: type, retailValue: retail,
                    unitCost: cost.isEmpty ? nil : Decimal(string: cost, locale: Locale(identifier: "en_US_POSIX")),
                    quota: quota, validEnd: validEnd.isEmpty ? nil : validEnd) else { return nil }
        return .createTemplate(draft)
    }
    var body: some View {
        Form {
            Section("coopflow.template.new") {
                TextField("coopflow.field.name", text: $name).accessibilityIdentifier("coopflow.template.name")
                Picker("coopflow.field.perkType", selection: $type) {
                    Text("coopflow.perk.0").tag(0); Text("coopflow.perk.1").tag(1); Text("coopflow.perk.2").tag(2)
                }
                TextField("coopflow.field.retailValue", text: $retail).keyboardType(.decimalPad)
                TextField("coopflow.field.unitCost", text: $cost).keyboardType(.decimalPad)
                TextField("coopflow.field.quota", text: $quota).keyboardType(.numberPad)
                TextField("coopflow.field.validEnd", text: $validEnd)
            }
            Section { Text("coopflow.template.rules"); Text("coopflow.currency") }
            if let operation { NavigationLink("coopflow.reviewAction") { CoopFlowRequestPreview(operation: operation) } }
            else { Text("coopflow.template.required").foregroundStyle(.secondary) }
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.template.new")
    }
}
struct CoopFlowReasonEditor: View {
    let topicID: Int
    @State private var reason = ""
    var body: some View {
        Form {
            LabeledContent("coopflow.field.topicId", value: String(topicID))
            Section("coopflow.field.reason") {
                TextEditor(text: $reason).frame(minHeight: 140).accessibilityLabel("coopflow.field.reason")
            }
            Text("coopflow.complaint.rules")
            if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NavigationLink("coopflow.reviewAction") { CoopFlowRequestPreview(operation: .complaint(topicID: topicID, reason: reason)) }
            }
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.complaint.prepare")
    }
}
struct CoopFlowHandleEditor: View {
    let inviteID: Int
    let action: CoopFlowHandle
    let currentStatus: Int
    @State private var reason = ""
    var body: some View {
        Form {
            LabeledContent("coopflow.field.id", value: String(inviteID))
            Text(LocalizedStringKey("coopflow.handle." + String(action.rawValue)))
            TextField("coopflow.field.reason", text: $reason, axis: .vertical)
            if action == .cancel && currentStatus == 1 { Text("coopflow.cancel.reason") }
            if action != .cancel || currentStatus != 1 || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NavigationLink("coopflow.reviewAction") { CoopFlowRequestPreview(operation: .handle(inviteID: inviteID, action: action, reason: reason)) }
            }
            Text("coopflow.contract.notice")
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.reviewAction")
    }
}
/// Context is supplied only by a current, approved merchant chapter application.
struct CoopFlowOfferEditor: View {
    let context: CoopFlowOfferContext
    let eligibleTemplates: [CoopFlowJSON]
    @State private var selectedTemplate = 0
    @State private var quota = ""
    @State private var fee = ""
    private var draft: CoopFlowOfferDraft? {
        switch context.termsMode {
        case .traffic: return try? CoopFlowOfferDraft(context: context)
        case .perk:
            guard eligibleTemplates.contains(where: { $0["id"].integer == selectedTemplate && (CoopFlowMoney($0["retailValue"]).amount ?? 0) > 0 && ($0["quota"].integer ?? 0) > 0 }) else { return nil }
            return try? CoopFlowOfferDraft(context: context, templateID: selectedTemplate, quota: Int(quota))
        case .revshare: return try? CoopFlowOfferDraft(context: context, perHeadFee: Decimal(string: fee, locale: Locale(identifier: "en_US_POSIX")))
        }
    }
    var body: some View {
        Form {
            LabeledContent("coopflow.field.chapterId", value: String(context.chapterID))
            LabeledContent("coopflow.field.termsMode", value: context.termsMode.rawValue)
            if context.termsMode == .perk {
                Picker("coopflow.templates", selection: $selectedTemplate) {
                    Text("coopflow.choose").tag(0)
                    ForEach(Array(eligibleTemplates.enumerated()), id: \.offset) { _, row in
                        if let id = row["id"].integer, (CoopFlowMoney(row["retailValue"]).amount ?? 0) > 0, (row["quota"].integer ?? 0) > 0 {
                            Text(row["name"].text ?? String(id)).tag(id)
                        }
                    }
                }
                TextField("coopflow.field.quotaTotal", text: $quota).keyboardType(.numberPad)
            }
            if context.termsMode == .revshare { TextField("coopflow.field.perHeadFee", text: $fee).keyboardType(.decimalPad) }
            if let draft { NavigationLink("coopflow.reviewAction") { CoopFlowRequestPreview(operation: draft.mutation) } }
            Text("coopflow.offer.rules")
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.offer.title")
    }
}
/// Only caller-supplied current topic/recipient selections are allowed; never type a merchant ID into member space.
struct CoopFlowInviteEditor: View {
    let kind: CoopFlowTargetKind
    let recipient: CoopFlowIdentity
    let recipientName: String
    let topicID: Int
    let originApplyID: Int?
    let scope: String?
    @State private var message = ""
    @State private var fixed = false
    @State private var fee = ""
    private var draft: CoopFlowInvitation? {
        if fixed {
            guard let amount = Decimal(string: fee, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return try? CoopFlowInvitation(kind: kind, recipient: recipient, topicID: topicID, message: message, compensation: .fixed(amount), originApplyID: originApplyID, scope: scope)
        }
        return try? CoopFlowInvitation(kind: kind, recipient: recipient, topicID: topicID, message: message, originApplyID: originApplyID, scope: scope)
    }
    var body: some View {
        Form {
            LabeledContent("coopflow.field.toId", value: recipientName)
            LabeledContent("coopflow.field.toType", value: kind.wire)
            LabeledContent("coopflow.field.topicId", value: String(topicID))
            TextField("coopflow.field.message", text: $message, axis: .vertical)
            Toggle("coopflow.fixed", isOn: $fixed)
            if fixed { TextField("coopflow.field.fixedFee", text: $fee).keyboardType(.decimalPad); Text("coopflow.currency") }
            if let draft { NavigationLink("coopflow.reviewAction") { CoopFlowRequestPreview(operation: .invite(draft)) } }
            Text("coopflow.invite.rules")
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.invite.title")
    }
}
struct CoopFlowReviewEditor: View {
    let topicID: Int
    let memberID: Int
    let partnerName: String
    @State private var rating = 5
    @State private var comment = ""
    var body: some View {
        Form {
            Text(partnerName).font(.headline)
            Stepper("\(rating) / 5", value: $rating, in: 1...5).accessibilityLabel("coopflow.field.rating")
            TextField("coopflow.field.comment", text: $comment, axis: .vertical)
            NavigationLink("coopflow.reviewAction") {
                CoopFlowRequestPreview(operation: .review(topicID: topicID, memberID: memberID, rating: rating, comment: comment))
            }
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.reviews")
    }
}

@MainActor struct CoopFlowPerkPicker: View {
    @Environment(\.locale) private var locale
    let reader: any CoopFlowReading
    let inviteID: Int
    @State private var rows: [CoopFlowJSON] = []
    @State private var selected: Set<Int> = []
    @State private var loaded: CoopFlowSession?
    @State private var failed = false
    var body: some View {
        List {
            if loaded == reader.session, loaded != nil {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    if let id = row["id"].integer {
                        Toggle(isOn: Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })) {
                            Text(row["name"].text ?? appLocalized("coopflow.unnamed", locale: locale))
                        }
                    }
                }
                if rows.isEmpty { Text("coopflow.empty") }
                if !selected.isEmpty {
                    NavigationLink("coopflow.reviewAction") { CoopFlowRequestPreview(operation: .attachPerks(inviteID: inviteID, templateIDs: selected.sorted())) }
                }
            } else if failed { Text("coopflow.read.failed") }
            else { ProgressView("cooperation.loading") }
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.attach")
            .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0)") {
                rows = []; selected = []; loaded = nil; failed = false
                let session = reader.session
                do {
                    let result = try await reader.read(.templates)
                    guard !Task.isCancelled, reader.session == session else { return }
                    rows = (result.rows ?? []).filter { (CoopFlowMoney($0["retailValue"]).amount ?? 0) > 0 && ($0["quota"].integer ?? 0) > 0 }
                    loaded = session
                } catch { guard !Task.isCancelled, reader.session == session else { return }; failed = true }
            }
    }
}
struct CoopFlowSupplyManagementView: View {
    let context: CoopFlowOfferContext
    /// Provided by fresh MerchantContent application + chapter matching, not inferred from an offer ID.
    let canManageCircleSupply: Bool
    var body: some View {
        List {
            LabeledContent("coopflow.field.chapterId", value: String(context.chapterID))
            if canManageCircleSupply, let id = context.offerID {
                NavigationLink("coopflow.reconfirm") { CoopFlowRequestPreview(operation: .reconfirmOffer(id: id)) }
                NavigationLink("coopflow.pause") { CoopFlowRequestPreview(operation: .pauseOffer(id: id)) }
            }
            Text("coopflow.offer.rules")
            CoopFlowSafetyNotice()
        }.navigationTitle("coopflow.supply")
    }
}
