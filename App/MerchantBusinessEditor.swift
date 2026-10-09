import SwiftUI

struct MerchantBusinessEditorContext: Identifiable {
    let id = UUID()
    enum Kind {
        case note(MerchantCustomerID, corrects: Int?), tag([MerchantCustomerID]), aftercare(MerchantBusinessRecord)
        case review(MerchantBusinessRecord, MerchantReviewReplyAction), invite, role(MerchantBusinessRecord), removeOperator(MerchantBusinessRecord), revokeInvite(MerchantBusinessRecord)
    }
    let kind: Kind
}
@MainActor struct MerchantBusinessEditor: View {
    @Environment(\.dismiss) private var dismiss
    let context: MerchantBusinessEditorContext
    let snapshot: MerchantBusinessSnapshot?
    let onReview: (MerchantBusinessMutation) -> Void
    @State private var content = ""
    @State private var name = ""
    @State private var color = "#2E6D5A"
    @State private var role = ""
    @State private var decision: MerchantAftercareDecision = .agree
    @State private var evidence = ""
    @State private var issue: String?
    @State private var noteCorrectionCancelled = false
    @State private var confirmCancelCorrection = false
    private var noteCorrectionID: Int? {
        guard !noteCorrectionCancelled, case .note(_, let correction) = context.kind else { return nil }
        return correction
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("merchant.business.localDraft").foregroundStyle(.secondary)
                switch context.kind {
                case .note(let customer, _):
                    Text(noteCorrectionID == nil ? "merchant.business.addNote" : "merchant.business.correctNote")
                        .font(.headline).accessibilityIdentifier("merchant.noteCorrection.mode")
                    LabeledContent("merchant.business.target", value: "customer:\(customer.rawValue)")
                    if let note = noteCorrectionID {
                        LabeledContent("merchant.business.field.correctsNoteId", value: String(note))
                        MerchantNoteCorrectionTargetSummary(customer: customer, noteID: note, snapshot: snapshot)
                        Text("merchant.noteCorrection.append").font(.footnote).foregroundStyle(.secondary)
                        Button("merchant.noteCorrection.cancel") { confirmCancelCorrection = true }
                            .accessibilityIdentifier("merchant.noteCorrection.cancel")
                    }
                    TextField("merchant.business.noteContent", text: $content, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("merchant.business.editor.content")
                case .tag:
                    TextField("merchant.business.tagName", text: $name).accessibilityIdentifier("merchant.business.editor.tagName")
                    TextField("merchant.business.tagColor", text: $color).textInputAutocapitalization(.characters).autocorrectionDisabled()
                case .aftercare(let row):
                    Picker("merchant.business.decision", selection: $decision) {
                        ForEach(MerchantAftercareDecision.allCases, id: \.self) { choice in
                            if (try? row.fields.mbStrings("allowedDecisions").contains(choice.rawValue)) == true {
                                Text(LocalizedStringKey("merchant.business.state." + String(choice.rawValue))).tag(choice)
                            }
                        }
                    }
                    TextField("merchant.business.responseContent", text: $content, axis: .vertical).lineLimit(3...8)
                    TextField("merchant.business.evidenceKey", text: $evidence).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("merchant.business.evidenceHint").font(.footnote).foregroundStyle(.secondary)
                    Text("merchant.business.opinionOnly").font(.footnote)
                case .review(_, let action):
                    if action == .delete { Text("merchant.business.deleteReplyWarning") }
                    else { TextField(action == .report ? "merchant.business.reportReason" : "merchant.business.replyContent", text: $content, axis: .vertical).lineLimit(3...8) }
                case .invite, .role:
                    Picker("merchant.business.role", selection: $role) {
                        Text("merchant.business.chooseRole").tag("")
                        ForEach(snapshot?.roles?.rows ?? []) { item in Text(item.fields.mbText("name") ?? item.id).tag(item.id) }
                    }
                    if let selected = snapshot?.roles?.rows.first(where: { $0.id == role }) {
                        MerchantOperatorRolePermissionSection(role: selected)
                    }
                    Text("merchant.business.rolesBoundary").font(.footnote).foregroundStyle(.secondary)
                case .removeOperator, .revokeInvite:
                    TextField("merchant.business.reason", text: $content, axis: .vertical).lineLimit(3...8)
                }
                if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.red) }
                Button("merchant.business.reviewDraft") {
                    do { let mutation = try makeMutation(); _ = try mutation.request(requestID: "validation-only"); onReview(mutation) }
                    catch { issue = "merchant.business.invalid" }
                }.accessibilityIdentifier("merchant.business.editor.review")
            }
            .navigationTitle("merchant.business.localActions")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } } }
            .confirmationDialog("merchant.noteCorrection.cancelTitle", isPresented: $confirmCancelCorrection, titleVisibility: .visible) {
                Button("merchant.noteCorrection.confirmCancel", role: .destructive) {
                    noteCorrectionCancelled = true; content = ""; issue = nil
                }.accessibilityIdentifier("merchant.noteCorrection.confirmCancel")
                Button("merchant.noteCorrection.keep", role: .cancel) { }
            } message: { Text("merchant.noteCorrection.cancelBody") }
            .onAppear {
                if case .aftercare(let row) = context.kind, let first = try? row.fields.mbStrings("allowedDecisions").first, let value = MerchantAftercareDecision(rawValue: first) { decision = value }
                if case .role(let row) = context.kind { role = row.fields.mbText("roleCode") ?? "" }
                if case .review(let row, .update) = context.kind { content = row.fields.mbText("merchantReply") ?? "" }
            }
        }
    }
    private func makeMutation() throws -> MerchantBusinessMutation {
        func id(_ row: MerchantBusinessRecord) throws -> Int { guard let id = Int(row.id), id > 0 else { throw MerchantBusinessFailure.invalid }; return id }
        switch context.kind {
        case .note(let customer, let corrects): return .addNote(customer: customer, content: content, correctsNoteID: noteCorrectionCancelled ? nil : corrects)
        case .tag(let ids):
            if ids.count == 1 { return .assignTag(customer: ids[0], name: name, color: color) }
            return .batchTag(customers: ids, name: name, color: color)
        case .aftercare(let row): return .aftercare(refund: try .init(id(row)), decision: decision, content: content, evidenceKey: evidence.isEmpty ? nil : evidence)
        case .review(let row, let action): return .review(id: try .init(id(row)), version: try row.fields.mbInt("version"), action: action, content: content)
        case .invite: return .inviteOperator(role: role)
        case .role(let row): return .operatorRole(id: try .init(id(row)), version: try row.fields.mbInt("version"), role: role)
        case .removeOperator(let row): return .removeOperator(id: try .init(id(row)), version: try row.fields.mbInt("version"), reason: content)
        case .revokeInvite(let row): return .revokeInvite(id: try .init(id(row)), version: try row.fields.mbInt("version"), reason: content)
        }
    }
}
@MainActor struct MerchantBusinessReviewSheet: View {
    let review: MerchantBusinessConfirmation
    let canExecute: Bool
    let isSynthetic: Bool
    let busy: Bool
    let issue: String?
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section("merchant.business.frozenReview") {
                    Text(LocalizedStringKey(review.mutation.titleKey)).font(.headline)
                    if case .addNote(let customer, _, let correction) = review.mutation, let note = correction {
                        MerchantNoteCorrectionTargetSummary(customer: customer, noteID: note, snapshot: review.baseline)
                        Text("merchant.noteCorrection.append").font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("merchant.business.storeID", value: String(review.baseline.access.merchantID))
                    LabeledContent("merchant.business.target", value: review.mutation.targetKey)
                    if case .json(let fields) = review.request.body {
                        ForEach(fields.keys.sorted().filter { $0 != "requestId" }, id: \.self) { key in
                            if let value = fields[key], value.array == nil, value.object == nil { MerchantBusinessField(key: key, value: value) }
                            if let values = fields[key]?.array { LabeledContent(LocalizedStringKey("merchant.business.field." + String(key)), value: values.compactMap(\.numberText).joined(separator: ", ")) }
                        }
                    }
                    Text("merchant.business.refreshBeforeSend").font(.footnote).foregroundStyle(.secondary)
                }
                if let issue { Text(LocalizedStringKey(issue)) }
                if canExecute {
                    if isSynthetic { Text("merchant.business.synthetic") }
                    Button(isSynthetic ? "merchant.business.confirmSynthetic" : "merchant.business.confirmProduction", action: confirm).disabled(busy).accessibilityIdentifier("merchant.business.confirm")
                } else { Text("merchant.business.disabled").accessibilityIdentifier("merchant.business.dispatchDisabled") }
                Button("action.cancel", action: cancel).disabled(busy).accessibilityIdentifier("merchant.business.cancelReview")
            }.navigationTitle("merchant.business.reviewDraft").interactiveDismissDisabled(busy)
        }
    }
}

private struct MerchantNoteCorrectionTargetSummary: View {
    let customer: MerchantCustomerID
    let noteID: Int
    let snapshot: MerchantBusinessSnapshot?
    private var summary: String? {
        guard let snapshot, snapshot.document.query == .customer(customer) else { return nil }
        return snapshot.document.rows.first {
            $0.kind == .timeline && ["NOTE", "NOTE_CORRECTION"].contains($0.fields.mbText("type") ?? "") && $0.fields["noteId"]?.integer == noteID
        }?.fields.mbText("description")
    }
    var body: some View {
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LabeledContent("merchant.noteCorrection.originalSummary", value: summary)
                .font(.subheadline).accessibilityIdentifier("merchant.noteCorrection.targetSummary")
        }
    }
}
