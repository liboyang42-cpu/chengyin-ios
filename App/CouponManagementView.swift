import SwiftUI

@MainActor final class CouponManagementScreenModel: ObservableObject {
    let core: CouponManagementCoordinator
    @Published var revision = 0
    @Published var working = false
    private var operationID: UUID?
    init(_ core: CouponManagementCoordinator) { self.core = core }
    func update(_ value: CouponManagementDraft) { core.change(value); revision += 1 }
    func run(_ work: @escaping () async -> Void) {
        guard !working else { return }
        let id = UUID(); operationID = id; working = true
        Task { await work(); guard operationID == id else { return }; working = false; revision += 1 }
    }
    func cancelReview() { operationID = nil; core.cancelReview(); working = false; revision += 1 }
    func synchronize() { operationID = nil; core.synchronize(); working = false; revision += 1 }
}
/// Add only at the existing merchant published-coupon entry. The host owns feature visibility.
@MainActor struct CouponManagementView: View {
    @Environment(\.locale) private var locale
    @StateObject private var model: CouponManagementScreenModel
    let sessionKey: CouponManagementSession?
    let isSourceVisible: Bool
    @State private var creating = false
    init(coordinator: CouponManagementCoordinator, sessionKey: CouponManagementSession?, isSourceVisible: Bool = false) {
        _model = StateObject(wrappedValue: CouponManagementScreenModel(coordinator)); self.sessionKey = sessionKey; self.isSourceVisible = isSourceVisible
    }
    var body: some View {
        Group {
            if !isSourceVisible { ContentUnavailableView("couponManagement.unavailable", systemImage: "ticket") }
            else if sessionKey == nil { ContentUnavailableView("couponManagement.signIn", systemImage: "person.crop.circle") }
            else {
                List {
                    CouponManagementNotice(model: model)
                    Text("couponManagement.chinaTime").font(.footnote).foregroundStyle(.secondary)
                    if model.working || model.core.loading { ProgressView("couponManagement.loading") }
                    else if model.core.rows.isEmpty { Text("couponManagement.empty").foregroundStyle(.secondary) }
                    ForEach(model.core.rows) { row in
                        NavigationLink {
                            CouponManagementDetailView(model: model, id: row.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.name ?? appLocalized("couponManagement.coupon", locale: locale)).font(.headline)
                                Text(LocalizedStringKey(row.typeKey)).font(.subheadline)
                                if row.state != .active { Text(LocalizedStringKey(row.state.key)).font(.caption) }
                                Text("\(CouponValidityTime.display(row.startTime) ?? "—") – \(CouponValidityTime.display(row.endTime) ?? "—")").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.accessibilityIdentifier("couponManagement.definition.\(row.id.value)")
                    }
                }
                .refreshable { await model.core.load(); model.revision += 1 }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { creating = true } label: { Label("couponManagement.create", systemImage: "plus") }
                            .disabled(model.working || !model.core.canReviewPublish).accessibilityIdentifier("couponManagement.create")
                    }
                }
            }
        }
        .navigationTitle("couponManagement.title")
        .task(id: sessionKey) {
            model.synchronize(); creating = false
            if isSourceVisible, sessionKey != nil { await model.core.load(); model.revision += 1 }
        }
        .sheet(isPresented: $creating) { NavigationStack { CouponManagementEditor(model: model) } }
        .onChange(of: sessionKey) { _, _ in creating = false; model.synchronize() }
        .onChange(of: isSourceVisible) { _, visible in if !visible { creating = false; model.core.leave(); model.revision += 1 } }
    }
}
@MainActor private struct CouponManagementNotice: View {
    @ObservedObject var model: CouponManagementScreenModel
    var body: some View {
        Section {
            if !model.core.canSubmit { Text("couponManagement.dormant").font(.footnote) }
            if model.core.canSimulate { Text("couponManagement.synthetic").font(.footnote).foregroundStyle(.secondary) }
            if model.core.canSubmit && (!model.core.canReviewPublish || !model.core.canReviewStop) {
                Text("couponManagement.unavailable").font(.footnote)
            }
            if let issue = model.core.issue { Text(LocalizedStringKey(issue.messageKey)).accessibilityIdentifier("couponManagement.issue") }
            if let issue = model.core.issue, case .server(let message) = issue { Text(message) }
            if let message = model.core.serverMessage { Text(message).accessibilityIdentifier("couponManagement.serverMessage") }
            if model.core.simulated { Text("couponManagement.simulated") }
            if model.core.acknowledged {
                Text(LocalizedStringKey(model.core.verifiedRecord == nil ? "couponManagement.readbackPending" : "couponManagement.readbackVerified"))
                    .accessibilityIdentifier("couponManagement.readback")
            }
        }
    }
}
@MainActor private struct CouponManagementDetailView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: CouponManagementScreenModel
    let id: CouponDefinitionID
    var body: some View {
        List {
            CouponManagementNotice(model: model)
            if let row = model.core.rows.first(where: { $0.id == id }) {
                Section {
                    Text(row.name ?? appLocalized("couponManagement.coupon", locale: locale)).font(.title2)
                    Text(row.description?.isEmpty == false ? row.description! : appLocalized("couponManagement.noDescription", locale: locale))
                    LabeledContent("couponManagement.status") { Text(LocalizedStringKey(row.state.key)) }
                    LabeledContent("couponManagement.type") { Text(LocalizedStringKey(row.typeKey)) }
                    LabeledContent("couponManagement.start", value: CouponValidityTime.display(row.startTime) ?? "—")
                    LabeledContent("couponManagement.end", value: CouponValidityTime.display(row.endTime) ?? "—")
                    Text("couponManagement.dateNotice").font(.footnote)
                    Text("couponManagement.chinaTime").font(.footnote)
                }
                Section("couponManagement.counts") {
                    count("couponManagement.published", row.publishCount)
                    count("couponManagement.received", row.receiveCount)
                    count("couponManagement.used", row.useCount)
                    count("couponManagement.remaining", row.remaining)
                    count("couponManagement.perLimit", row.perLimit)
                    LabeledContent("couponManagement.amount", value: row.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—")
                    LabeledContent("couponManagement.currency", value: row.currency ?? "—")
                }
                Section {
                    Text("couponManagement.stopPolicy").font(.footnote)
                    if row.state.canStop {
                        Button("couponManagement.reviewStop", role: .destructive) { model.run { await model.core.prepareStop(id) } }
                            .disabled(model.working || !model.core.canReviewStop).accessibilityIdentifier("couponManagement.stop.review")
                    }
                    Text("couponManagement.claimUnavailable").font(.footnote)
                }
                if let review = model.core.review { CouponManagementReviewSection(model: model, review: review) }
            } else if model.working { ProgressView("couponManagement.loading") }
            else { Text("couponManagement.unavailable") }
        }
        .navigationTitle("couponManagement.detail")
        .toolbar { Button("couponManagement.refresh") { model.run { await model.core.load() } }.disabled(model.working) }
        .task { await model.core.load(); model.revision += 1 }
        .onDisappear { model.cancelReview() }
    }
    private func count(_ key: LocalizedStringKey, _ value: Int?) -> some View { LabeledContent(key, value: value.map(String.init) ?? "—") }
}
@MainActor private struct CouponManagementEditor: View {
    @ObservedObject var model: CouponManagementScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var discard = false
    private func binding<T>(_ keyPath: WritableKeyPath<CouponManagementDraft, T>) -> Binding<T> {
        Binding(get: { model.core.draft[keyPath: keyPath] }, set: { value in var draft = model.core.draft; draft[keyPath: keyPath] = value; model.update(draft) })
    }
    private func date(_ start: Bool) -> Binding<Date> {
        Binding(get: { (start ? model.core.draft.startTime : model.core.draft.endTime) ?? Date() }, set: { value in
            var draft = model.core.draft; if start { draft.startTime = value } else { draft.endTime = value }; model.update(draft)
        })
    }
    var body: some View {
        Form {
            CouponManagementNotice(model: model)
            Section("couponManagement.details") {
                TextField("couponManagement.name", text: binding(\.name)).accessibilityIdentifier("couponManagement.name")
                TextField("couponManagement.description", text: binding(\.description), axis: .vertical).lineLimit(2...6)
                Picker("couponManagement.type", selection: binding(\.couponType)) {
                    Text("couponManagement.chooseType").tag(Int?.none)
                    ForEach(0..<4) { type in Text(LocalizedStringKey(CouponManagementDraft.typeKey(type))).tag(Optional(type)) }
                }.accessibilityIdentifier("couponManagement.type")
                TextField("couponManagement.quantity", text: binding(\.quantity)).keyboardType(.numberPad).accessibilityIdentifier("couponManagement.quantity")
            }.disabled(model.working)
            Section("couponManagement.dates") {
                Text("couponManagement.chinaTime").font(.footnote)
                Toggle("couponManagement.setStart", isOn: Binding(get: { model.core.draft.startTime != nil }, set: { value in var draft = model.core.draft; draft.startTime = value ? Date() : nil; model.update(draft) })).accessibilityIdentifier("couponManagement.setStart")
                if model.core.draft.startTime != nil { DatePicker("couponManagement.start", selection: date(true), displayedComponents: [.date, .hourAndMinute]) }
                Toggle("couponManagement.setEnd", isOn: Binding(get: { model.core.draft.endTime != nil }, set: { value in var draft = model.core.draft; draft.endTime = value ? Date() : nil; model.update(draft) })).accessibilityIdentifier("couponManagement.setEnd")
                if model.core.draft.endTime != nil { DatePicker("couponManagement.end", selection: date(false), displayedComponents: [.date, .hourAndMinute]) }
            }.disabled(model.working)
            if let blocker = model.core.draft.blocker { Text(LocalizedStringKey(blocker)).foregroundStyle(.secondary) }
            Button("couponManagement.reviewPublish") { model.run { await model.core.preparePublish() } }
                .disabled(model.working || model.core.draft.blocker != nil || !model.core.canReviewPublish).accessibilityIdentifier("couponManagement.publish.review")
            if let review = model.core.review { CouponManagementReviewSection(model: model, review: review) }
        }
        .environment(\.timeZone, CouponValidityTime.timeZone)
        .environment(\.calendar, CouponValidityTime.calendar)
        .navigationTitle("couponManagement.create")
        .interactiveDismissDisabled(model.core.draft.dirty || model.working)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("couponManagement.cancel") { if model.core.draft.dirty { discard = true } else { dismiss() } }.disabled(model.working) } }
        .confirmationDialog("couponManagement.discardTitle", isPresented: $discard, titleVisibility: .visible) {
            Button("couponManagement.discard", role: .destructive) { model.core.discardDraft(); model.revision += 1; dismiss() }
            Button("couponManagement.keepEditing", role: .cancel) {}
        }
        .onDisappear { model.cancelReview() }
    }
}
@MainActor private struct CouponManagementReviewSection: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: CouponManagementScreenModel
    let review: CouponManagementReview
    var body: some View {
        Section {
            switch review.intent {
            case .publish(let draft):
                Text("couponManagement.chinaTime").font(.footnote)
                Text(draft.name).font(.headline)
                Text(draft.description)
                LabeledContent("couponManagement.quantity", value: draft.quantity)
                Text(LocalizedStringKey(CouponManagementDraft.typeKey(draft.couponType)))
                if let start = draft.startTime { LabeledContent("couponManagement.start") { Text(CouponValidityTime.display(start)) } }
                if let end = draft.endTime { LabeledContent("couponManagement.end") { Text(CouponValidityTime.display(end)) } }
            case .stop(let row):
                Text(row.name ?? appLocalized("couponManagement.coupon", locale: locale)).font(.headline)
                Text("couponManagement.stopPolicy")
            }
            Text("couponManagement.reviewNotice").font(.footnote)
            Button(LocalizedStringKey(model.core.canSimulate ? "couponManagement.simulate" : "couponManagement.confirmSubmission")) { model.run { await model.core.confirm(review) } }
                .disabled(model.working || !model.core.canConfirm(review)).accessibilityIdentifier("couponManagement.confirm")
            Button("couponManagement.cancel") { model.cancelReview() }.disabled(model.working)
        } header: {
            Text("couponManagement.review").accessibilityIdentifier("couponManagement.review")
        }
    }
}
