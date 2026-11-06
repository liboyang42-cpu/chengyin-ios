import SwiftUI

@MainActor final class MerchantTemplateCategoryPickerModel: ObservableObject, Identifiable {
    let id = UUID()
    let document: MerchantOperationsViewModel
    let selection: MerchantTemplateCategorySelection
    @Published private(set) var busy = false
    @Published private var revision = 0
    init?(document: MerchantOperationsViewModel) {
        guard let selection = MerchantTemplateCategorySelection(owner: document.coordinator) else { return nil }
        self.document = document; self.selection = selection
    }
    func reload() async {
        guard !busy else { return }
        busy = true; await selection.reload(); busy = false
    }
    func toggle(_ id: Int) { selection.toggle(id); revision += 1 }
    func removeUnavailable(_ id: Int) { selection.removeUnavailable(id); revision += 1 }
    func replaceUnsupported() { selection.beginReplacement(); revision += 1 }
    func apply() -> Bool {
        guard !busy, let value = selection.apply() else { return false }
        document.edit(.template(value)); revision += 1
        return document.coordinator.draft == .template(value)
    }
    func cancel() { selection.cancel(); busy = false; revision += 1 }
}

@MainActor struct MerchantTemplateCategoryPicker: View {
    @ObservedObject var document: MerchantOperationsViewModel
    let open: () -> Void
    private var editable: Bool {
        let owner = document.coordinator
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
    }
    var body: some View {
        if case .template(let value) = document.coordinator.draft {
            Section("merchant.categories.title") {
                MerchantTemplateCategorySummary(categories: value.categories)
                Button("merchant.categories.choose", action: open)
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(!editable).accessibilityIdentifier("merchant.categories.open")
                Text("merchant.categories.scope").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// The stable editor owns presentation, independent of a lazy Form section's lifetime.
@MainActor struct MerchantTemplateCategoryPresentation: ViewModifier {
    @ObservedObject var document: MerchantOperationsViewModel
    @Binding var picker: MerchantTemplateCategoryPickerModel?
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool {
        let owner = document.coordinator
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
    }
    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { picker }, set: { value in
                if value == nil { picker?.cancel() }; picker = value
            }), onDismiss: close) { value in
                MerchantTemplateCategorySheet(model: value) { value.cancel(); picker = nil }
            }
            .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
            .onChange(of: document.coordinator.draft) { _, _ in close() }
            .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
            .onChange(of: editable) { _, value in if !value { close() } }
            .onChange(of: scenePhase) { _, value in if value != .active { close() } }
            .onDisappear { close() }
    }
    private func close() { picker?.cancel(); picker = nil }
}

@MainActor private struct MerchantTemplateCategorySheet: View {
    @ObservedObject var model: MerchantTemplateCategoryPickerModel
    let dismiss: () -> Void
    @State private var search = ""
    private var filtered: [MerchantTemplateCategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.selection.rows.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id).contains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if !model.selection.isCurrent { merchantCreationNotice(Text("merchant.categories.stale"), systemImage: "lock") }
                else if model.busy { ProgressView("merchant.categories.loading") }
                else if let issue = model.selection.issue {
                    MerchantOperationsIssueView(issue: issue)
                    Button("merchant.categories.retry") { Task { await model.reload() } }.accessibilityIdentifier("merchant.categories.retry")
                } else if !model.selection.loaded { ProgressView("merchant.categories.loading") }
                else {
                    if model.selection.needsReplacement {
                        Section {
                            merchantCreationNotice(Text("merchant.categories.unsupported"), systemImage: "exclamationmark.triangle")
                            Button("merchant.categories.replace") { model.replaceUnsupported() }
                                .accessibilityIdentifier("merchant.categories.replace")
                        }
                    }
                    if !model.selection.unavailableIDs.isEmpty {
                        Section("merchant.categories.unavailable") {
                            Text("merchant.categories.unavailableHint").font(.footnote)
                            ForEach(model.selection.unavailableIDs, id: \.self) { id in
                                Button { model.removeUnavailable(id) } label: { Text("merchant.categories.removeID \(id)") }
                                    .accessibilityIdentifier("merchant.categories.removeUnavailable.\(id)")
                            }
                        }
                    }
                    Section {
                        Text("merchant.categories.selectionCount \(model.selection.selectedIDs.count)")
                            .font(Theme.Font.cardTitle).fixedSize(horizontal: false, vertical: true)
                        Text("merchant.categories.minimum").font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.selection.rows.isEmpty { Text("merchant.categories.empty").accessibilityIdentifier("merchant.categories.empty") }
                    else if filtered.isEmpty { Text("merchant.categories.noMatches") }
                    else {
                        Section("merchant.categories.catalog") {
                            ForEach(filtered) { row in
                                Button { model.toggle(row.id) } label: {
                                    HStack(alignment: .center, spacing: Theme.Space.s3) {
                                        Text(verbatim: row.name).foregroundStyle(Theme.Color.textPrimary(in: .merchant))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: Theme.Space.s2)
                                        Image(systemName: model.selection.selectedIDs.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Theme.Color.accent(in: .merchant)).accessibilityHidden(true)
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.disabled(model.selection.needsReplacement)
                                    .accessibilityAddTraits(model.selection.selectedIDs.contains(row.id) ? .isSelected : [])
                                    .accessibilityIdentifier("merchant.categories.option.\(row.id)")
                            }
                        }
                    }
                    Button("merchant.categories.reload") { Task { await model.reload() } }.accessibilityIdentifier("merchant.categories.reload")
                }
            }
            .merchantCreationSurface()
            .searchable(text: $search, prompt: "merchant.categories.search")
            .appNavigationTitle("merchant.categories.choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: dismiss).accessibilityIdentifier("merchant.categories.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchant.categories.apply") { if model.apply() { dismiss() } }
                        .disabled(model.busy || !model.selection.canApply).accessibilityIdentifier("merchant.categories.apply")
                }
            }
            .task { await model.reload() }
        }
    }
}

private struct MerchantTemplateCategorySummary: View {
    let categories: MerchantTemplateCategories
    var body: some View {
        if !categories.isSupported {
            merchantCreationNotice(Text("merchant.categories.unsupported"), systemImage: "exclamationmark.triangle")
            if let raw = categories.rawIDs { Text(verbatim: raw).fixedSize(horizontal: false, vertical: true) }
        } else if categories.selectedIDs.isEmpty { Text("merchant.categories.none") }
        else {
            ForEach(categories.selectedIDs, id: \.self) { id in
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    if let name = categories.name(id), !name.isEmpty { Text(verbatim: name).font(Theme.Font.cardTitle).fixedSize(horizontal: false, vertical: true) }
                    Text("merchant.categories.id \(id)").font(Theme.Font.label).foregroundStyle(.secondary)
                }.padding(.vertical, Theme.Space.s1).accessibilityElement(children: .combine).accessibilityIdentifier("merchant.categories.selected.\(id)")
            }
        }
        if let id = categories.primaryID {
            Text("merchant.categories.primary \(id)").font(.footnote).accessibilityIdentifier("merchant.categories.primary")
        }
    }
}

struct MerchantTemplateCategoryReview: View {
    let categories: MerchantTemplateCategories
    var body: some View {
        Section("merchant.categories.title") {
            MerchantTemplateCategorySummary(categories: categories)
            if categories.replacedUnsupportedSource {
                Text("merchant.categories.replacementReview").accessibilityIdentifier("merchant.categories.review.replacement")
            }
            Text("merchant.categories.reviewHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
