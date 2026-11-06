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
                if value.categorySourceUnavailable { Text("merchant.industry.sourceUnreadable").fixedSize(horizontal: false, vertical: true) }
                else if !value.selectedCategoryIDs.isEmpty {
                    Text(value.industryNames.joined(separator: " · ")).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchant.industry.currentID")
                    Text("merchant.industry.currentID \(value.selectedCategoryIDs[0])").font(.caption).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                } else { Text("merchant.industry.none") }
                Button("merchant.industry.choose") { picker = .init(document: document) }
                    .disabled(!editable).accessibilityIdentifier("merchant.industry.open")
                Text("merchant.industry.orderedHint").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                        if model.selection.previousIDs.isEmpty { Text("merchant.industry.none") }
                        else { Text(model.selection.previousIDs.map { "#\($0)" }.joined(separator: " · ")).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
                        if model.selection.previousIsUnavailable {
                            Text("merchant.industry.unavailable").fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchant.industry.unavailable")
                        }
                    }
                    if model.selection.rows.isEmpty {
                        Text("merchant.industry.empty").accessibilityIdentifier("merchant.industry.empty")
                    } else {
                        Section("merchant.industry.catalog") {
                            ForEach(model.selection.rows) { row in
                                Button { model.select(row.id) } label: {
                                    HStack {
                                        Text(verbatim: row.name).fixedSize(horizontal: false, vertical: true); Spacer()
                                        if model.selection.selectedIDs.contains(row.id) { Image(systemName: "checkmark.circle.fill") }
                                    }
                                }.accessibilityAddTraits(model.selection.selectedIDs.contains(row.id) ? .isSelected : [])
                                    .accessibilityIdentifier("merchant.industry.option.\(row.id)")
                            }
                        }
                    }
                    Section("merchant.industry.selectedOrder") {
                        ForEach(Array(model.selection.selectedIDs.enumerated()), id: \.element) { index, id in
                            let name = model.selection.rows.first(where: { $0.id == id })?.name ?? "#\(id)"
                            HStack {
                                Text("\(index + 1). \(name)").fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("merchant.industry.remove") { model.select(id) }
                            }
                        }
                        if model.selection.limitReached { Text("merchant.industry.limit").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        Text("merchant.industry.selectionInvalid").font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
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
            LabeledContent("merchant.industry.previous") {
                Text(verbatim: change.previousIDs.map(String.init).joined(separator: ", "))
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
                .accessibilityIdentifier("merchant.industry.review.previous")
            LabeledContent("merchant.industry.new") {
                Text(verbatim: change.selectedIDs.map(String.init).joined(separator: ", "))
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
                .accessibilityIdentifier("merchant.industry.review.new")
            Text("merchant.industry.reviewOrdered").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
