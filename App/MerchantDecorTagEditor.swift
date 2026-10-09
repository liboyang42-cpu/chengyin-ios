import SwiftUI

@MainActor final class MerchantDecorTagPickerModel: ObservableObject, Identifiable {
    let id = UUID()
    let document: MerchantOperationsViewModel
    private let scope: UUID
    private let identity: UUID
    private let original: MerchantStoreDecor
    @Published var draft: MerchantDecorTagDraft
    private(set) var consumed = false
    init?(document: MerchantOperationsViewModel) {
        let owner = document.coordinator
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .decor(let original) = owner.draft else { return nil }
        self.document = document; scope = owner.reader.scope; identity = owner.draftIdentity
        self.original = original; draft = .init(selected: original.tags)
    }
    var isCurrent: Bool {
        let owner = document.coordinator
        guard !consumed, owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              owner.reader.scope == scope, owner.draftIdentity == identity, owner.draft == .decor(original),
              case .decor(let current) = owner.draft else { return false }
        return MerchantDecorTagDraft.equal(current.tags, original.tags)
    }
    @discardableResult func apply() -> Bool {
        guard isCurrent, draft.canApply else { return false }
        consumed = true
        if MerchantDecorTagDraft.equal(draft.selected, original.tags) { return true }
        var edited = original; edited.tags = draft.selected
        document.edit(.decor(edited))
        return document.coordinator.draft == .decor(edited)
    }
    func cancel() { consumed = true }
}

@MainActor struct MerchantDecorTagEditor: View {
    @ObservedObject var model: MerchantOperationsViewModel
    @State private var picker: MerchantDecorTagPickerModel?
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool {
        let owner = model.coordinator
        return owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
    }
    var body: some View {
        Button("merchant.decorTags.choose") { picker = .init(document: model) }
            .disabled(!editable).accessibilityIdentifier("merchant.decorTags.open")
            .sheet(item: $picker, onDismiss: { picker?.cancel(); picker = nil }) { value in
                MerchantDecorTagSheet(picker: value) { value.cancel(); picker = nil }
            }
            .onChange(of: model.coordinator.draftIdentity) { _, _ in close() }
            .onChange(of: model.coordinator.reader.scope) { _, _ in close() }
            .onChange(of: editable) { _, value in if !value { close() } }
            .onChange(of: scenePhase) { _, value in if value != .active { close() } }
            .onDisappear { close() }
    }
    private func close() { picker?.cancel(); picker = nil }
}

@MainActor private struct MerchantDecorTagSheet: View {
    @ObservedObject var picker: MerchantDecorTagPickerModel
    let close: () -> Void
    @State private var custom = ""
    @State private var issue: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchant.decorTags.localDraft").font(.footnote)
                    LabeledContent("merchant.decorTags.selected", value: "\(picker.draft.selected.count) / 12")
                    if !picker.draft.canApply { Text("merchant.decorTags.limit").foregroundStyle(.secondary) }
                    ForEach(Array(picker.draft.selected.enumerated()), id: \.offset) { index, tag in
                        HStack {
                            Text(verbatim: tag)
                            Spacer()
                            Button(role: .destructive) { edit { $0.remove(at: index) } } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(Text("merchant.decorTags.remove") + Text(verbatim: ": " + tag))
                                .accessibilityIdentifier("merchant.decorTags.remove." + String(index))
                        }
                    }
                }
                ForEach(MerchantDecorTagDraft.groups, id: \.key) { group in
                    Section(LocalizedStringKey("merchant.decorTags.group." + group.key)) {
                        ForEach(Array(group.values.enumerated()), id: \.offset) { index, tag in
                            Toggle(LocalizedStringKey("merchant.decorTags." + group.key + "." + String(index)), isOn: Binding(
                                get: { picker.draft.contains(tag) },
                                set: { selected in if selected != picker.draft.contains(tag) { edit { try $0.toggle(tag) } } }))
                                .disabled(!picker.draft.contains(tag) && picker.draft.selected.count >= 12)
                                .accessibilityIdentifier("merchant.decorTags." + group.key + "." + String(index))
                        }
                    }
                }
                Section("merchant.decorTags.custom") {
                    TextField("merchant.decorTags.customName", text: $custom)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("merchant.decorTags.customName")
                    Text("merchant.decorTags.customLimit").font(.footnote)
                    Button("merchant.decorTags.add") {
                        if edit({ try $0.addCustom(custom) }) { custom = "" }
                    }.disabled(custom.isEmpty).accessibilityIdentifier("merchant.decorTags.add")
                }
                if let issue { Section { Text(LocalizedStringKey(issue)).foregroundStyle(.secondary) } }
                Section {
                    Button("merchant.decorTags.apply") {
                        if picker.apply() { close() } else { issue = "merchant.decorTags.stale" }
                    }.disabled(!picker.isCurrent || !picker.draft.canApply).accessibilityIdentifier("merchant.decorTags.apply")
                }
            }.disabled(!picker.isCurrent)
                .appNavigationTitle("merchant.decorTags.choose")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: close).accessibilityIdentifier("merchant.decorTags.cancel") } }
        }
    }
    @discardableResult private func edit(_ operation: (inout MerchantDecorTagDraft) throws -> Void) -> Bool {
        guard picker.isCurrent else { return false }
        do { try operation(&picker.draft); issue = nil; return true }
        catch let failure as MerchantDecorTagDraft.Failure {
            switch failure { case .empty: issue = "merchant.decorTags.empty"; case .tooLong: issue = "merchant.decorTags.customLimit"; case .limit: issue = "merchant.decorTags.limit" }
        } catch { issue = "merchant.decorTags.stale" }
        return false
    }
}
