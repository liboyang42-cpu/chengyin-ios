import SwiftUI

@MainActor struct MerchantEngagementHomeView: View {
    let reader: any MerchantEngagementReading
    let businessReader: (any MerchantBusinessReading)?
    let contactDelivery: (any MerchantContactDelivering)?
    let journal: any MerchantBusinessIntentStore
    @StateObject private var model: MerchantEngagementViewModel
    @State private var filter: MerchantCRMFilter
    @State private var editor: MerchantEngagementEditorContext?
    @State private var pending: MerchantEngagementCommand?
    @State private var customerIDText = ""
    @State private var refundIDText = ""
    @State private var appliedCustomers: MerchantCustomerQuery?
    init(reader: any MerchantEngagementReading, journal: any MerchantBusinessIntentStore, exportRecovery: any MerchantExportRecoveryStoring,
         businessReader: (any MerchantBusinessReading)? = nil, contactDelivery: (any MerchantContactDelivering)? = nil, filter: MerchantCRMFilter = .init()) {
        self.reader = reader; self.journal = journal; self.businessReader = businessReader; self.contactDelivery = contactDelivery
        _filter = State(initialValue: filter); _model = StateObject(wrappedValue: .init(reader: reader, journal: journal, exports: exportRecovery))
    }
    private var state: MerchantEngagementCoordinator { model.coordinator }
    private func allowed(_ permission: String) -> Bool { model.access?.identity?.allows(permission) == true }
    var body: some View {
        List {
            Section {
                Text(LocalizedStringKey(reader.isSyntheticEnabled ? "merchant.engagement.synthetic" : "merchant.engagement.scopedBoundary")).font(.footnote).foregroundStyle(.secondary)
                if let name = model.access?.identity?.name { Text(name).font(.headline) }
                if let issue = model.issue { Text(LocalizedStringKey(issue)); Text("merchant.engagement.staleHistory").font(.footnote) }
                if let failure = state.failure { Text(LocalizedStringKey(failure.key)).accessibilityIdentifier("merchant.engagement.error") }
                if state.locked { Text("merchant.business.unknownResult").accessibilityIdentifier("merchant.engagement.locked") }
                if model.loading || state.busy { ProgressView("merchant.loading") }
            }
            if allowed("merchant:crm:read") {
                Section("merchant.engagement.currentFilter") {
                    MerchantCRMFilterFields(filter: $filter, dateContext: !model.loading && model.issue == nil
                        ? .init(scope: reader.scope, authorization: reader.authorizationGeneration, merchantID: model.access?.merchantID) : nil)
                    if allowed("merchant:crm:segment") {
                        Button("merchant.engagement.saveSegment") { editor = .init(kind: .segment) }.accessibilityIdentifier("merchant.engagement.saveSegment")
                    }
                }
                Section("merchant.engagement.segments") {
                    if model.segments.isEmpty { Text("merchant.engagement.noSegments").foregroundStyle(.secondary) }
                    ForEach(model.segments) { segment in
                        Button {
                            if let saved = segment.filter { var updated = saved; updated.keyword = filter.keyword; filter = updated; appliedCustomers = updated.customerQuery }
                        } label: {
                            VStack(alignment: .leading) { Text(segment.name ?? "#\(segment.id)"); Text("#\(segment.id)").font(.caption).foregroundStyle(.secondary) }
                        }.disabled(segment.filter == nil).accessibilityIdentifier("merchant.engagement.segment.\(segment.id)")
                    }
                    if let appliedCustomers, let businessReader {
                        NavigationLink { MerchantBusinessPage(reader: businessReader, journal: journal, query: .customers(appliedCustomers)) } label: { Label("merchant.engagement.openFilteredCustomers", systemImage: "person.2") }
                    }
                }
            }
            if allowed("merchant:marketing:write") {
                Section("merchant.engagement.outreach") {
                    Button("merchant.engagement.createCampaign") { editor = .init(kind: .campaign) }.accessibilityIdentifier("merchant.engagement.createCampaign")
                    Button("merchant.engagement.broadcast") { editor = .init(kind: .broadcast) }.accessibilityIdentifier("merchant.engagement.broadcast")
                    Text("merchant.engagement.audienceBoundary").font(.footnote).foregroundStyle(.secondary)
                }
                Section("merchant.engagement.history") {
                    ForEach(model.campaigns) { task in
                        Button { Task { await model.loadTask(task.id) } } label: { VStack(alignment: .leading) { Text(task.title ?? "#\(task.id)"); MerchantEngagementStatus(value: task.status) } }
                            .accessibilityIdentifier("merchant.engagement.campaign.\(task.id)")
                    }
                    if model.campaigns.isEmpty { Text("merchant.engagement.noCampaigns") }
                }
                if let task = model.detail {
                    Section("merchant.engagement.taskDetails") {
                        MerchantCampaignTaskFields(task: task)
                        if task.canDispatch { Button("merchant.engagement.reviewDispatch") { Task { await model.prepare(.dispatchCampaign(task.id)) } }.accessibilityIdentifier("merchant.engagement.reviewDispatch") }
                        if task.canRetry { Button("merchant.engagement.reviewRetry") { Task { await model.prepare(.retryCampaign(task.id)) } } }
                    }
                }
            }
            if allowed("merchant:crm:export") {
                Section("merchant.engagement.exports") {
                    Text("merchant.engagement.exportPrivacy").font(.footnote)
                    Button("merchant.engagement.createExport") { Task { await model.prepare(.createExport(filter)) } }.disabled(state.exportTicket?.task.isRunning == true)
                        .accessibilityIdentifier("merchant.engagement.createExport")
                    if let ticket = state.exportTicket {
                        LabeledContent("merchant.engagement.taskID", value: String(ticket.task.id))
                        MerchantEngagementStatus(value: ticket.task.status)
                        if let count = ticket.task.rowCount { LabeledContent("merchant.engagement.rowCount", value: String(count)) }
                        if let message = ticket.task.errorMessage { Text(message) }
                        if ticket.canDownload, let selectedScope = state.exportScope, let merchantID = state.exportMerchantID { Button("merchant.engagement.reviewDownload") { Task { await model.prepare(.downloadExport(ticket, scope: selectedScope, merchantID: merchantID)) } } }
                        else if ticket.task.isDownloadable { Text("merchant.engagement.tokenLost").foregroundStyle(.secondary) }
                        Button("merchant.engagement.refreshExport") { Task { await state.refreshExport(); model.objectWillChange.send() } }
                    }
                }
            }
            if allowed("merchant:crm:sensitive:read") {
                Section("merchant.engagement.contact") {
                    TextField("merchant.engagement.customerID", text: $customerIDText).keyboardType(.numberPad)
                    ForEach(MerchantContactPurpose.allCases, id: \.self) { purpose in
                        Button(LocalizedStringKey("merchant.engagement.contact." + (purpose.rawValue))) {
                            if let raw = Int(customerIDText), let id = try? MerchantCustomerID(raw) { Task { await model.prepare(.contact(id, purpose)) } }
                        }.disabled((Int(customerIDText) ?? 0) <= 0)
                    }
                    Text("merchant.engagement.contactPrivacy").font(.footnote)
                }
            }
            if allowed("merchant:aftercare:evidence") {
                Section("merchant.engagement.evidence") {
                    TextField("merchant.engagement.refundID", text: $refundIDText).keyboardType(.numberPad)
                    if let raw = Int(refundIDText), let id = try? MerchantRefundID(raw), let selectedScope = reader.scope, let merchantID = model.access?.merchantID {
                        NavigationLink {
                            MerchantEvidenceSelectionView(refundID: id, selectedScope: selectedScope, currentScope: { reader.permitsDevice(.selectEvidence(id), merchantID: merchantID) ? reader.scope : nil }, nativeSelectionEnabled: reader.permitsDevice(.selectEvidence(id), merchantID: merchantID)) { selection in
                                pending = .uploadEvidence(id, selection, scope: selectedScope, merchantID: merchantID)
                            }
                        } label: { Label("merchant.engagement.selectEvidence", systemImage: "photo.badge.plus") }
                    }
                }
            }
            Section("merchant.engagement.invitation") {
                Button("merchant.engagement.acceptInvitation") { editor = .init(kind: .invitation) }.accessibilityIdentifier("merchant.engagement.acceptInvitation")
                Text("merchant.engagement.invitationUnknownTarget").font(.footnote).foregroundStyle(.secondary)
            }
            receiptSection
            Button("merchant.business.refresh") { Task { await model.load() } }.accessibilityIdentifier("merchant.engagement.refresh")
        }
        .appNavigationTitle("merchant.engagement.title")
        .task(id: reader.scope) {
            model.invalidate(); await model.load()
            if let command = pending, !Task.isCancelled { pending = nil; await model.prepare(command) }
        }
        .task(id: state.exportTicket?.task.isRunning == true ? state.exportTicket?.task.id : nil) { await model.pollExportsWhileVisible() }
        .onChange(of: reader.scope) { _, _ in pending = nil; editor = nil; model.invalidate() }
        .onDisappear { model.cancel(); model.clearReceipt() }
        .sheet(item: $editor, onDismiss: { if let command = pending { pending = nil; Task { await model.prepare(command) } } }) { context in
            MerchantEngagementComposer(context: context, filter: filter, segments: model.segments, coupons: model.coupons, canCoupon: allowed("merchant:coupon:manage")) { command in pending = command; editor = nil }
        }
        .sheet(item: Binding(get: { state.review }, set: { if $0 == nil && !state.busy { model.cancel() } })) { review in
            MerchantEngagementReviewView(review: review, enabled: reader.canExecute(review.command, merchantID: review.proof.access.merchantID ?? 0), synthetic: reader.isSyntheticEnabled, busy: state.busy, cancel: model.cancel) { Task { await model.confirm(review) } }
        }
    }
    @ViewBuilder private var receiptSection: some View {
        if let receipt = state.receipt, state.receiptScope == reader.scope {
            Section("merchant.engagement.receipt") {
                switch receipt {
                case .savedSegment: Text("merchant.engagement.segmentSaved")
                case .campaignCreated(let task): Text("merchant.engagement.createdNotSent"); LabeledContent("merchant.engagement.taskID", value: String(task.id))
                case .campaignDispatched(let task), .campaignRetried(let task): MerchantCampaignTaskFields(task: task)
                case .broadcast(let result): MerchantEngagementStatus(value: result.status); MerchantEngagementCounts(counts: result.counts)
                case .exportCreated: Text("merchant.engagement.exportCreated")
                case .exportDownloaded(let id, let bytes):
                    Text("merchant.engagement.downloadReady"); LabeledContent("merchant.engagement.taskID", value: String(id)); LabeledContent("merchant.engagement.byteCount", value: String(bytes.count))
                    Text("merchant.engagement.noAutomaticSharing").font(.footnote)
                    MerchantExportSaveView(taskID: id, bytes: bytes,
                        deviceExportAllowed: state.receiptMerchantID.map { reader.permitsDevice(.saveExport(id), merchantID: $0) } == true,
                        authorize: { await state.authorizeExportSave(taskID: id) })
                case .contact:
                    Text("merchant.engagement.contactReady"); Text("merchant.engagement.contactNotDisplayed").font(.footnote)
                    if let contactDelivery {
                        Button("merchant.engagement.consumeContact") { Task { try? await state.consumeContact(using: contactDelivery); model.objectWillChange.send() } }
                    } else if case .contact(let contact) = receipt, let merchant = state.receiptMerchantID,
                              reader.permitsDevice(.contact(contact.customerID, contact.purpose), merchantID: merchant) {
                        Button("merchant.engagement.consumeContact") {
                            Task { try? await state.consumeContact(using: MerchantContactDeviceAdapter(deviceEffectsAllowed: true)); model.objectWillChange.send() }
                        }
                    }
                case .invitationAccepted(let member): Text("merchant.engagement.membershipReceipt"); Text(LocalizedStringKey("merchant.business.role." + (member.fields.mbText("roleCode") ?? ""))); Text("merchant.engagement.refreshIdentity").font(.footnote)
                case .evidenceUploaded(_, _, let result): Text("merchant.engagement.evidenceReady"); Text(result.objectKey).font(.caption).textSelection(.enabled); Text("merchant.engagement.evidenceNotSubmitted").font(.footnote)
                }
                Button("merchant.engagement.clearReceipt") { model.clearReceipt() }
            }
        }
    }
}

struct MerchantCRMFilterFields: View {
    @Binding var filter: MerchantCRMFilter
    var dateContext: MerchantCRMDateRangePicker.Context? = nil
    var body: some View {
        TextField("merchant.business.search", text: $filter.keyword)
        Picker("merchant.business.segment", selection: $filter.segment) {
            ForEach(["all", "repeat", "new", "noted"], id: \.self) { Text(LocalizedStringKey("merchant.business.segment." + ($0))).tag($0) }
        }
        Picker("merchant.business.sourceType", selection: Binding(get: { filter.sourceType ?? 0 }, set: { filter.sourceType = $0 == 0 ? nil : $0 })) {
            Text("merchant.business.segment.all").tag(0); Text("merchant.business.state.TOPIC").tag(1); Text("merchant.business.state.ACTIVITY").tag(2)
        }
        TextField("merchant.engagement.tagID", text: Binding(get: { filter.tagID.map(String.init) ?? "" }, set: { filter.tagID = Int($0) })).keyboardType(.numberPad)
        TextField("merchant.business.sourceStart", text: Binding(get: { filter.sourceStart ?? "" }, set: { filter.sourceStart = $0.isEmpty ? nil : $0 }))
        TextField("merchant.business.sourceEnd", text: Binding(get: { filter.sourceEnd ?? "" }, set: { filter.sourceEnd = $0.isEmpty ? nil : $0 }))
        MerchantCRMDateRangePicker(context: dateContext, start: filter.sourceStart ?? "", end: filter.sourceEnd ?? "") { value in
            if value.start != (filter.sourceStart ?? "") { filter.sourceStart = value.start.isEmpty ? nil : value.start }
            if value.end != (filter.sourceEnd ?? "") { filter.sourceEnd = value.end.isEmpty ? nil : value.end }
        }
    }
}
struct MerchantEngagementStatus: View {
    let value: String?
    private let known = ["READY", "SENDING", "SUCCESS", "PARTIAL_FAILED", "NO_ELIGIBLE", "FAILED", "PENDING", "RUNNING", "EXPIRED", "DELIVERED"]
    var body: some View {
        if let value, known.contains(value) { Text(LocalizedStringKey("merchant.engagement.status." + (value))) }
        else { Text(value ?? "—").foregroundStyle(.secondary) }
    }
}
struct MerchantEngagementCounts: View {
    let counts: [String: Int]
    var body: some View { ForEach(counts.keys.sorted(), id: \.self) { key in LabeledContent(LocalizedStringKey("merchant.engagement.count." + (key)), value: String(counts[key]!)) } }
}
struct MerchantCampaignTaskFields: View {
    let task: MerchantCampaignTask
    var body: some View {
        LabeledContent("merchant.engagement.taskID", value: String(task.id)); if let title = task.title { Text(title).font(.headline) }
        if let content = task.source["content"]?.string { Text(content) }
        MerchantEngagementStatus(value: task.status); MerchantEngagementCounts(counts: task.counts)
        if !task.recipients.isEmpty {
            ForEach(task.recipients) { recipient in
                VStack(alignment: .leading) {
                    Text(recipient.source.mbText("customerName") ?? "—")
                    MerchantEngagementStatus(value: recipient.source.mbText("status"))
                    if let reason = recipient.source.mbText("failureMessage") { Text(reason).font(.footnote) }
                    if let code = recipient.source.mbText("failureCode"), !code.isEmpty { Text(code).font(.caption) }
                }
            }
        }
    }
}
