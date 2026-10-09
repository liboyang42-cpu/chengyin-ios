import SwiftUI

@MainActor final class MerchantNPCKnowledgeDraftModel: ObservableObject {
    let coordinator: MerchantNPCKnowledgeDraftCoordinator
    @Published private(set) var revision = 0
    init(document: MerchantOperationsViewModel) {
        let identity = document.coordinator.draftIdentity
        coordinator = .init(reader: document.coordinator.reader, isContextCurrent: { [weak document] in
            guard let value = document?.coordinator else { return false }
            guard value.destination == .character, case .character = value.draft else { return false }
            return value.draftIdentity == identity && value.isCurrent && !value.isBusy && !value.isLocked && value.confirmation == nil
        })
    }
    func open() async { revision += 1; await coordinator.open(); revision += 1 }
    func save() async { revision += 1; await coordinator.saveLocally(); revision += 1 }
    func edit(_ value: MerchantNPCKnowledgeDraft) { coordinator.edit(value); revision += 1 }
    func cancel() { coordinator.cancel(); revision += 1 }
    func invalidate() { coordinator.invalidate(); revision += 1 }
}

@MainActor struct MerchantNPCKnowledgeDraftEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @StateObject private var model: MerchantNPCKnowledgeDraftModel
    @State private var isPresented = false
    @Environment(\.scenePhase) private var scenePhase
    init(document: MerchantOperationsViewModel) {
        self.document = document
        _model = StateObject(wrappedValue: .init(document: document))
    }
    var body: some View {
        Section {
            Button { isPresented = true } label: {
                Label("merchantKnowledge.title", systemImage: "list.bullet.rectangle")
            }
            .disabled(!document.coordinator.isCurrent || document.coordinator.isBusy || document.coordinator.isLocked || document.coordinator.confirmation != nil)
            .accessibilityIdentifier("merchantKnowledge.open")
            Text("merchantKnowledge.boundary").font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isPresented, onDismiss: { model.cancel() }) {
            NavigationStack { MerchantNPCKnowledgeDraftView(model: model) }
        }
        .onChange(of: document.coordinator.reader.scope) { _, _ in reset() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in reset() }
        .onChange(of: document.coordinator.isCurrent) { _, current in if !current { reset() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { reset() } }
        .onDisappear { reset() }
    }
    private func reset() { model.invalidate(); isPresented = false }
}

@MainActor struct MerchantNPCKnowledgeDraftView: View {
    @ObservedObject var model: MerchantNPCKnowledgeDraftModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var dismissal = MerchantNPCKnowledgeDismissal()
    @State private var showsDiscardReview = false
    private var coordinator: MerchantNPCKnowledgeDraftCoordinator { model.coordinator }
    var body: some View {
        Form {
            Section {
                Text("merchantKnowledge.boundary").accessibilityIdentifier("merchantKnowledge.boundary")
                Text("merchantKnowledge.memoryOnly").font(.footnote).foregroundStyle(.secondary)
                Text("merchantKnowledge.untrusted").font(.footnote).foregroundStyle(.secondary)
            }
            if coordinator.phase == .loading { ProgressView("merchant.loading") }
            if coordinator.isCurrent && (coordinator.phase == .editing || coordinator.phase == .saving) {
                Group { products; hours; promotions; faqs; neverSay }
                    .disabled(!coordinator.canEdit)
                validation
                Section {
                    if coordinator.savedThisEdit {
                        Label("merchantKnowledge.saved", systemImage: "checkmark.circle")
                            .accessibilityIdentifier("merchantKnowledge.saved")
                    }
                    Button("merchantKnowledge.save") { Task { await model.save() } }
                        .disabled(!coordinator.canEdit || !coordinator.isDirty)
                        .accessibilityIdentifier("merchantKnowledge.save")
                    if coordinator.phase == .saving { ProgressView("merchant.loading") }
                }
            }
            if let failure = coordinator.failure {
                Section {
                    Text(LocalizedStringKey("merchantKnowledge.failure." + failure.rawValue))
                        .accessibilityIdentifier("merchantKnowledge.failure")
                    if failure != .contextChanged {
                        Button("merchantKnowledge.retry") { Task { await model.open() } }
                            .accessibilityIdentifier("merchantKnowledge.retry")
                    }
                }
            }
        }
        .navigationTitle("merchantKnowledge.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { requestClose() }
                    .disabled(coordinator.isCurrent && coordinator.phase == .saving)
                    .accessibilityIdentifier("merchantKnowledge.cancel")
            }
        }
        .accessibilityIdentifier("merchantKnowledge.editor")
        .interactiveDismissDisabled(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(model))
        .alert("merchantKnowledgeDismiss.title", isPresented: $showsDiscardReview, presenting: dismissal.review) { review in
            Button("merchantKnowledgeDismiss.discard", role: .destructive) {
                if dismissal.discard(review, model: model, isActive: scenePhase == .active) { dismiss() }
                showsDiscardReview = false
            }
            Button("merchantKnowledgeDismiss.keepEditing", role: .cancel) { clearDiscardReview() }
        } message: { _ in Text("merchantKnowledgeDismiss.warning") }
        .task { await model.open() }
        .onChange(of: model.revision) { _, _ in clearDiscardReview() }
        .onChange(of: coordinator.scope) { _, _ in clearDiscardReview() }
        .onChange(of: coordinator.isCurrent) { _, current in if !current { clearDiscardReview() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clearDiscardReview() } }
        .onDisappear { clearDiscardReview(); model.cancel() }
    }
    private func requestClose() {
        switch dismissal.prepare(model, isActive: scenePhase == .active) {
        case .close: model.cancel(); dismiss()
        case .confirm: showsDiscardReview = true
        case .blocked: break
        }
    }
    private func clearDiscardReview() { dismissal.keepEditing(); showsDiscardReview = false }

    private var products: some View {
        Section("merchantKnowledge.products") {
            ForEach(coordinator.draft.products) { row in
                VStack(alignment: .leading) {
                    field("name", collection: \.products, row: row, path: \.name)
                    field("priceMinor", collection: \.products, row: row, path: \.priceMinor).keyboardType(.numberPad)
                    field("currency", collection: \.products, row: row, path: \.currency).textInputAutocapitalization(.characters)
                    remove(row, from: \.products)
                }
            }
            add("products", disabled: coordinator.draft.products.count >= 40) { $0.products.append(.init()) }
            Text("merchantKnowledge.productsHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var hours: some View {
        Section("merchantKnowledge.hours") {
            ForEach(coordinator.draft.hours) { row in
                VStack(alignment: .leading) {
                    Picker("merchantKnowledge.day", selection: Binding(get: {
                        coordinator.draft.hours.first(where: { $0.id == row.id })?.day ?? row.day
                    }, set: { day in
                        mutate { value in if let index = value.hours.firstIndex(where: { $0.id == row.id }) { value.hours[index].day = day } }
                    })) {
                        ForEach(1...7, id: \.self) { day in Text(LocalizedStringKey("merchantKnowledge.day." + String(day))).tag(day) }
                    }
                    field("opens", collection: \.hours, row: row, path: \.opens)
                    field("closes", collection: \.hours, row: row, path: \.closes)
                    field("timeZone", collection: \.hours, row: row, path: \.timeZone)
                    remove(row, from: \.hours)
                }
            }
            add("hours", disabled: coordinator.draft.hours.count >= 7) { value in
                let day = (1...7).first(where: { next in !value.hours.contains(where: { $0.day == next }) }) ?? 1
                value.hours.append(.init(day: day))
            }
            Text("merchantKnowledge.hoursHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var promotions: some View {
        Section("merchantKnowledge.promotions") {
            ForEach(coordinator.draft.promotions) { row in
                VStack(alignment: .leading) {
                    field("promotionTitle", collection: \.promotions, row: row, path: \.title)
                    field("startsAt", collection: \.promotions, row: row, path: \.startsAt)
                    field("endsAt", collection: \.promotions, row: row, path: \.endsAt)
                    remove(row, from: \.promotions)
                }
            }
            add("promotions", disabled: coordinator.draft.promotions.count >= 20) { $0.promotions.append(.init()) }
            Text("merchantKnowledge.promotionsHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var faqs: some View {
        Section("merchantKnowledge.faq") {
            ForEach(coordinator.draft.faq) { row in
                VStack(alignment: .leading) {
                    field("question", collection: \.faq, row: row, path: \.question)
                    field("answer", collection: \.faq, row: row, path: \.answer)
                    remove(row, from: \.faq)
                }
            }
            add("faq", disabled: coordinator.draft.faq.count >= 30) { $0.faq.append(.init()) }
            Text("merchantKnowledge.faqHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var neverSay: some View {
        Section("merchantKnowledge.neverSay") {
            ForEach(coordinator.draft.neverSay) { row in
                VStack(alignment: .leading) {
                    field("text", collection: \.neverSay, row: row, path: \.text)
                    remove(row, from: \.neverSay)
                }
            }
            add("neverSay", disabled: coordinator.draft.neverSay.count >= 30) { $0.neverSay.append(.init()) }
            Text("merchantKnowledge.neverSayHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var validation: some View {
        if !coordinator.issues.isEmpty {
            Section("merchantKnowledge.errors") {
                ForEach(Array(coordinator.issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(LocalizedStringKey("merchantKnowledge." + issue.section.rawValue))
                            if let row = issue.row { Text(verbatim: String(row + 1)) }
                            if let field = issue.field { Text(LocalizedStringKey("merchantKnowledge." + (field == "title" ? "promotionTitle" : field))) }
                        }.font(.caption)
                        Text(LocalizedStringKey(issue.messageKey))
                    }.accessibilityElement(children: .combine)
                }
            }.accessibilityIdentifier("merchantKnowledge.errors")
        }
    }
    private func field<Row: Identifiable>(_ name: String, collection: WritableKeyPath<MerchantNPCKnowledgeDraft, [Row]>, row: Row, path: WritableKeyPath<Row, String>) -> some View where Row.ID == UUID {
        TextField(LocalizedStringKey("merchantKnowledge." + name), text: Binding(get: {
            coordinator.draft[keyPath: collection].first(where: { $0.id == row.id })?[keyPath: path] ?? ""
        }, set: { text in
            mutate { value in
                if let index = value[keyPath: collection].firstIndex(where: { $0.id == row.id }) {
                    value[keyPath: collection][index][keyPath: path] = text
                }
            }
        }), axis: .vertical)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .accessibilityIdentifier("merchantKnowledge.field." + name + "." + row.id.uuidString)
    }
    private func remove<Row: Identifiable>(_ row: Row, from collection: WritableKeyPath<MerchantNPCKnowledgeDraft, [Row]>) -> some View where Row.ID == UUID {
        Button("merchantKnowledge.remove", role: .destructive) {
            mutate { $0[keyPath: collection].removeAll(where: { $0.id == row.id }) }
        }.accessibilityIdentifier("merchantKnowledge.remove." + row.id.uuidString)
    }
    private func add(_ section: String, disabled: Bool, edit: @escaping (inout MerchantNPCKnowledgeDraft) -> Void) -> some View {
        Button(LocalizedStringKey("merchantKnowledge.add." + section)) { mutate(edit) }
            .disabled(disabled).accessibilityIdentifier("merchantKnowledge.add." + section)
    }
    private func mutate(_ edit: (inout MerchantNPCKnowledgeDraft) -> Void) {
        guard coordinator.canEdit else { return }
        var value = coordinator.draft; edit(&value); model.edit(value)
    }
}
