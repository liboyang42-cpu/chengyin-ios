import SwiftUI

@MainActor final class MerchantFeaturedActivityPickerModel: ObservableObject, Identifiable {
    let id = UUID()
    let document: MerchantOperationsViewModel
    private let scope: UUID
    private let identity: UUID
    private let original: MerchantStoreDecor
    private var generation = 0
    private var consumed = false
    private var request: Task<MerchantFeaturedActivityPage, Error>?
    private var loadedPage = 0
    @Published private(set) var rows: [MerchantFeaturedActivityOption] = []
    @Published private(set) var total: Int?
    @Published private(set) var selectedID: Int?
    @Published private(set) var busy = false
    @Published private(set) var issue: MerchantOperationsIssue?
    init?(document: MerchantOperationsViewModel) {
        let owner = document.coordinator
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .decor(let original) = owner.draft else { return nil }
        self.document = document; scope = owner.reader.scope; identity = owner.draftIdentity
        self.original = original; selectedID = original.featuredType == 1 ? original.featuredID : nil
    }
    var isCurrent: Bool {
        let owner = document.coordinator
        return !consumed && owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
            && owner.reader.scope == scope && owner.draftIdentity == identity && owner.draft == .decor(original)
    }
    var hasLoaded: Bool { loadedPage > 0 }
    var hasMore: Bool { total.map { rows.count < $0 } ?? false }
    var originalNotLoaded: Bool {
        guard let id = original.featuredID, id > 0 else { return false }
        return original.featuredType != 1 || !rows.contains { $0.id == id }
    }
    var canApply: Bool { isCurrent && !busy && issue == nil && selectedID.map { id in rows.contains { $0.id == id } } == true }
    func select(_ id: Int) { guard isCurrent, !busy, issue == nil, rows.contains(where: { $0.id == id }) else { return }; selectedID = id }
    func loadFirst() async { guard loadedPage == 0 else { return }; await load(page: 1) }
    func loadMore() async { guard hasMore, loadedPage < Int.max else { return }; await load(page: loadedPage + 1) }
    func reload() async {
        guard isCurrent else { return }
        request?.cancel(); generation += 1; busy = false; rows = []; total = nil; loadedPage = 0
        await load(page: 1)
    }
    private func load(page: Int) async {
        guard isCurrent, !busy else { return }
        generation += 1; let ticket = generation
        busy = true; issue = nil
        let reader = document.coordinator.reader
        let pending = Task { try await reader.featuredActivities(page: page) }
        request = pending
        defer { if ticket == generation { busy = false; request = nil } }
        do {
            let result = try await pending.value
            guard !Task.isCancelled, ticket == generation, isCurrent else { return }
            let combined = try result.appended(to: page == 1 ? [] : rows)
            rows = combined; total = result.total; loadedPage = page
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), ticket == generation, isCurrent else { return }
            issue = .init(error)
        }
    }
    @discardableResult func apply() -> Bool {
        guard canApply, let selectedID else { return false }
        consumed = true; generation += 1; request?.cancel(); request = nil
        if original.featuredType == 1, original.featuredID == selectedID { return true }
        var edited = original; edited.featuredType = 1; edited.featuredID = selectedID
        document.edit(.decor(edited)); return document.coordinator.draft == .decor(edited)
    }
    func cancel() { consumed = true; generation += 1; request?.cancel(); request = nil; busy = false }
}

@MainActor struct MerchantFeaturedActivityPicker: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @State private var picker: MerchantFeaturedActivityPickerModel?
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool {
        let owner = document.coordinator
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
    }
    var body: some View {
        Button("merchant.featuredPicker.choose") { picker = .init(document: document) }
            .disabled(!editable).accessibilityIdentifier("merchant.featuredPicker.open")
            .sheet(item: Binding(get: { picker }, set: { value in
                if value == nil { picker?.cancel() }
                picker = value
            }), onDismiss: close) { value in
                MerchantFeaturedActivitySheet(picker: value) { value.cancel(); picker = nil }
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

@MainActor private struct MerchantFeaturedActivitySheet: View {
    @ObservedObject var picker: MerchantFeaturedActivityPickerModel
    let close: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("merchant.featuredPicker.scope").font(.footnote)
                    Text("merchant.featuredPicker.localDraft").font(.footnote)
                    if picker.originalNotLoaded { Text("merchant.featuredPicker.originalRetained").font(.footnote) }
                    LabeledContent("merchant.featuredPicker.loaded", value: picker.total.map { "\(picker.rows.count) / \($0)" } ?? String(picker.rows.count))
                    if picker.hasLoaded, picker.total == nil { Text("merchant.featuredPicker.unknownTotal").font(.footnote) }
                }
                if let issue = picker.issue {
                    Section {
                        MerchantOperationsIssueView(issue: issue)
                        Button("action.retry") { Task { await picker.reload() } }
                            .disabled(!picker.isCurrent || picker.busy).accessibilityIdentifier("merchant.featuredPicker.retry")
                    }
                }
                if picker.busy { ProgressView("merchant.loading") }
                if picker.hasLoaded, picker.rows.isEmpty { Text("merchant.featuredPicker.empty") }
                ForEach(picker.rows) { row in
                    Button { picker.select(row.id) } label: {
                        HStack {
                            if let name = row.name { Text(verbatim: name) } else { Text("merchant.operations.untitled") }
                            Spacer()
                            if picker.selectedID == row.id { Image(systemName: "checkmark") }
                        }
                    }.disabled(!picker.isCurrent || picker.busy || picker.issue != nil)
                        .accessibilityValue(Text(picker.selectedID == row.id ? "merchant.featuredPicker.selected" : "merchant.featuredPicker.notSelected"))
                        .accessibilityIdentifier("merchant.featuredPicker.option." + String(row.id))
                }
                if picker.hasMore {
                    Button("merchant.featuredPicker.more") { Task { await picker.loadMore() } }
                        .disabled(!picker.isCurrent || picker.busy).accessibilityIdentifier("merchant.featuredPicker.more")
                }
                Section {
                    Button("merchant.featuredPicker.apply") { if picker.apply() { close() } }
                        .disabled(!picker.canApply).accessibilityIdentifier("merchant.featuredPicker.apply")
                }
            }.appNavigationTitle("merchant.featuredPicker.choose")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: close).accessibilityIdentifier("merchant.featuredPicker.cancel") } }
                .task { await picker.loadFirst() }
                .onDisappear { picker.cancel() }
        }
    }
}
