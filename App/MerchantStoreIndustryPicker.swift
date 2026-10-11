import SwiftUI

@MainActor private final class MerchantStoreIndustryPickerModel: ObservableObject, Identifiable {
    let id = UUID()
    let document: MerchantOperationsViewModel
    let selection: MerchantStoreIndustrySelection
    @Published private(set) var busy = false
    @Published private var revision = 0
    init?(document: MerchantOperationsViewModel) {
        guard let selection = MerchantStoreIndustrySelection(owner: document.coordinator) else { return nil }
        self.document = document; self.selection = selection
    }
    func reload() async { guard !busy else { return }; busy = true; await selection.reload(); busy = false }
    func select(_ id: Int) { selection.select(id); revision += 1 }
    func apply() -> Bool {
        guard !busy, let value = selection.apply() else { return false }
        document.edit(.decor(value)); revision += 1
        return document.coordinator.draft == .decor(value)
    }
    func cancel() { selection.cancel(); busy = false; revision += 1 }
}

@MainActor struct MerchantStoreIndustryPicker: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @State private var picker: MerchantStoreIndustryPickerModel?
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool {
        let owner = document.coordinator
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
    }
    var body: some View {
        if case .decor(let value) = document.coordinator.draft {
            VStack(alignment: .leading, spacing: 10) {
                if let id = value.categoryID {
                    Text("merchant.industry.currentID \(id)").accessibilityIdentifier("merchant.industry.currentID")
                } else { Text("merchant.industry.none") }
                Button("merchant.industry.choose") { picker = .init(document: document) }
                    .disabled(!editable).accessibilityIdentifier("merchant.industry.open")
                Text("merchant.industry.scope").font(.footnote).foregroundStyle(.secondary)
            }
            .sheet(item: Binding(get: { picker }, set: { value in
                if value == nil { picker?.cancel() }; picker = value
            }), onDismiss: close) { value in
                MerchantStoreIndustrySheet(model: value) { value.cancel(); picker = nil }
            }
            .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
            .onChange(of: document.coordinator.draft) { _, _ in close() }
            .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
            .onChange(of: editable) { _, value in if !value { close() } }
            .onChange(of: scenePhase) { _, value in if value != .active { close() } }
            .onDisappear { close() }
        }
    }
    private func close() { picker?.cancel(); picker = nil }
}

@MainActor private struct MerchantStoreIndustrySheet: View {
    @ObservedObject var model: MerchantStoreIndustryPickerModel
    let dismiss: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if !model.selection.isCurrent { Text("merchant.industry.stale") }
                else if model.busy { ProgressView("merchant.industry.loading") }
                else if let issue = model.selection.issue {
                    MerchantOperationsIssueView(issue: issue)
                    Button("merchant.industry.retry") { Task { await model.reload() } }.accessibilityIdentifier("merchant.industry.retry")
                } else if !model.selection.loaded { ProgressView("merchant.industry.loading") }
                else {
                    Section("merchant.industry.original") {
                        if let id = model.selection.previousID { Text("merchant.industry.currentID \(id)") }
                        else { Text("merchant.industry.none") }
                        if model.selection.previousIsUnavailable {
                            Text("merchant.industry.unavailable").accessibilityIdentifier("merchant.industry.unavailable")
                        }
                    }
                    if model.selection.rows.isEmpty {
                        Text("merchant.industry.empty").accessibilityIdentifier("merchant.industry.empty")
                    } else {
                        Section("merchant.industry.catalog") {
                            ForEach(model.selection.rows) { row in
                                Button { model.select(row.id) } label: {
                                    HStack {
                                        Text(verbatim: row.name); Spacer()
                                        if row.id == model.selection.selectedID { Image(systemName: "checkmark.circle.fill") }
                                    }
                                }.accessibilityAddTraits(row.id == model.selection.selectedID ? .isSelected : [])
                                    .accessibilityIdentifier("merchant.industry.option.\(row.id)")
                            }
                        }
                    }
                    if let selected = model.selection.selected {
                        LabeledContent("merchant.industry.selected") { Text(verbatim: selected.name) }
                        Text("merchant.industry.currentID \(selected.id)")
                        if model.selection.previousID != selected.id {
                            Text("merchant.industry.replaceHint").font(.footnote).accessibilityIdentifier("merchant.industry.replaceHint")
                        }
                    }
                    Text("merchant.industry.noClear").font(.footnote)
                    Button("merchant.industry.reload") { Task { await model.reload() } }.accessibilityIdentifier("merchant.industry.reload")
                }
            }
            .appNavigationTitle("merchant.industry.choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: dismiss).accessibilityIdentifier("merchant.industry.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchant.industry.apply") { if model.apply() { dismiss() } }
                        .disabled(model.busy || !model.selection.canApply).accessibilityIdentifier("merchant.industry.apply")
                }
            }
            .task { await model.reload() }
        }
    }
}

struct MerchantStoreIndustryReview: View {
    let change: MerchantStoreIndustryChange
    var body: some View {
        Section("merchant.industry.reviewTitle") {
            LabeledContent("merchant.industry.previous", value: change.previousID.map(String.init) ?? "—")
                .accessibilityIdentifier("merchant.industry.review.previous")
            LabeledContent("merchant.industry.new", value: change.selectedID.map(String.init) ?? "—")
                .accessibilityIdentifier("merchant.industry.review.new")
            Text("merchant.industry.reviewBody").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
