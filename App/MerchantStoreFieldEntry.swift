import SwiftUI

@MainActor struct MerchantStoreFieldEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @ObservedObject var presentation: MerchantStoreFieldPresentation
    let field: MerchantStoreTextField
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool { MerchantStoreFieldSession.canOpen(document, field: field) }
    var body: some View {
        let permit = presentation.generation
        Button {
            guard scenePhase == .active else { return }
            presentation.open(permit: permit, document: document, field: field)
        } label: {
            HStack(alignment: .top) {
                Text(LocalizedStringKey(field.titleKey)); Spacer()
                if editable, let draft = document.coordinator.draft, let value = field.value(in: draft) {
                    if value.isEmpty { Text("merchant.storeField.empty").foregroundStyle(.secondary) }
                    else { Text(verbatim: value).lineLimit(2).foregroundStyle(.secondary) }
                }
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!editable || !presentation.active)
            .accessibilityIdentifier("merchant.storeField.open." + field.rawValue)
    }
}

/// Owned by the stable editor, never by a virtualized Form row.
@MainActor struct MerchantStoreFieldStablePresentation: ViewModifier {
    @ObservedObject var document: MerchantOperationsViewModel
    @ObservedObject var presentation: MerchantStoreFieldPresentation
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool {
        guard let session = presentation.session else { return true }
        return MerchantStoreFieldSession.canOpen(document, field: session.buffer.field)
    }
    func body(content: Content) -> some View {
        content.background {
            Color.clear.frame(width: 0, height: 0)
                .sheet(item: presentation.presentationBinding()) { selected in
                    MerchantStoreFieldSheet(session: selected) { presentation.close(selected.id) }
                }
                // A newly selected session gets a fresh sheet binding owner, including first open.
                .id(presentation.session?.id)
        }
        .onAppear { presentation.viewAppeared(sceneIsActive: scenePhase == .active) }
        .onChange(of: document.revision) { _, _ in if presentation.session?.isCurrent == false { presentation.invalidate() } }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in presentation.invalidate() }
        .onChange(of: document.coordinator.reader.scope) { _, _ in presentation.invalidate() }
        .onChange(of: editable) { _, value in if !value { presentation.invalidate() } }
        .onChange(of: scenePhase) { _, phase in presentation.sceneChanged(isActive: phase == .active) }
        .onDisappear { presentation.viewDisappeared() }
    }
}

@MainActor private struct MerchantStoreFieldSheet: View {
    @ObservedObject var session: MerchantStoreFieldSession
    let close: () -> Void
    private var text: Binding<String> { .init(get: { session.buffer.value }, set: { _ = session.update($0) }) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchant.storeField.boundary").font(.footnote).foregroundStyle(.secondary)
                    if session.buffer.field == .description {
                        TextEditor(text: text).frame(minHeight: 160)
                            .accessibilityLabel(Text(LocalizedStringKey(session.buffer.field.titleKey)))
                            .accessibilityIdentifier("merchant.storeField.input")
                    } else {
                        TextField(LocalizedStringKey(session.buffer.field.titleKey), text: text)
                            .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                            .accessibilityIdentifier("merchant.storeField.input")
                    }
                    Text("\(session.buffer.value.utf16.count) / \(session.buffer.field.limit)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if let key = session.buffer.issueKey { Text(LocalizedStringKey(key)).foregroundStyle(.secondary).accessibilityIdentifier("merchant.storeField.issue") }
                }
                Section {
                    Button("merchant.storeField.apply") { if session.apply() { close() } }
                        .disabled(!session.canApply).accessibilityIdentifier("merchant.storeField.apply")
                }
            }.disabled(!session.isCurrent || session.asksDiscard)
                .appNavigationTitle(key: session.buffer.field.titleKey)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { if session.requestClose() { close() } }.accessibilityIdentifier("merchant.storeField.cancel")
                } }
        }
        .privacySensitive()
        .interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)
        .alert("merchant.storeField.discardTitle", isPresented: Binding(get: { session.asksDiscard }, set: { _ in })) {
            Button("merchant.storeField.discard", role: .destructive) { if session.discard() { close() } }.accessibilityIdentifier("merchant.storeField.discard")
            Button("merchant.storeField.keepEditing", role: .cancel) { session.keepEditing() }.accessibilityIdentifier("merchant.storeField.keepEditing")
        } message: { Text("merchant.storeField.discardBody") }
        .onDisappear { session.cancel() }
    }
}
