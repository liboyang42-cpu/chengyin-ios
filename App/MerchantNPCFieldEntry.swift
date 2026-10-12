import SwiftUI

@MainActor struct MerchantNPCFieldEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @ObservedObject var presentation: MerchantNPCFieldPresentation
    let field: MerchantNPCTextField
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool { MerchantNPCFieldSession.canOpen(document, field: field) }
    var body: some View {
        let permit = presentation.generation
        Button {
            guard scenePhase == .active else { return }
            presentation.open(permit: permit, document: document, field: field)
        } label: {
            HStack(alignment: .top) {
                Text(LocalizedStringKey(field.titleKey)); Spacer()
                if editable, let draft = document.coordinator.draft, let value = field.value(in: draft) {
                    if value.isEmpty { Text("merchant.npcField.empty").foregroundStyle(.secondary) }
                    else { Text(verbatim: value).lineLimit(2).foregroundStyle(.secondary) }
                }
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!editable || !presentation.active)
            .accessibilityIdentifier("merchant.npcField.open." + field.rawValue)
    }
}

/// Owned by the stable editor, never by a virtualized Form row.
@MainActor struct MerchantNPCFieldStablePresentation: ViewModifier {
    @ObservedObject var document: MerchantOperationsViewModel
    @ObservedObject var presentation: MerchantNPCFieldPresentation
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool {
        guard let session = presentation.session else { return true }
        return MerchantNPCFieldSession.canOpen(document, field: session.buffer.field)
    }
    func body(content: Content) -> some View {
        content.background {
            Color.clear.frame(width: 0, height: 0)
                .sheet(item: presentation.presentationBinding()) { selected in
                    MerchantNPCFieldSheet(session: selected) { presentation.close(selected.id) }
                }
                // A newly selected session gets a fresh sheet binding owner, including first open.
                .id(presentation.session?.id)
        }
        .onAppear { if scenePhase == .active { presentation.activate() } }
        .onChange(of: document.revision) { _, _ in if presentation.session?.isCurrent == false { presentation.invalidate() } }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in presentation.invalidate() }
        .onChange(of: document.coordinator.reader.scope) { _, _ in presentation.invalidate() }
        .onChange(of: editable) { _, value in if !value { presentation.invalidate() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { presentation.activate() } else { presentation.deactivate() } }
        .onDisappear { presentation.deactivate() }
    }
}

@MainActor private struct MerchantNPCFieldSheet: View {
    @ObservedObject var session: MerchantNPCFieldSession
    let close: () -> Void
    private var text: Binding<String> { .init(get: { session.buffer.value }, set: { _ = session.update($0) }) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchant.npcField.boundary").font(.footnote).foregroundStyle(.secondary)
                    if session.buffer.field.multiline {
                        TextEditor(text: text).frame(minHeight: 160)
                            .accessibilityLabel(Text(LocalizedStringKey(session.buffer.field.titleKey)))
                            .accessibilityIdentifier("merchant.npcField.input")
                    } else {
                        TextField(LocalizedStringKey(session.buffer.field.titleKey), text: text)
                            .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                            .accessibilityIdentifier("merchant.npcField.input")
                    }
                    Text("\(session.buffer.value.utf16.count) / \(session.buffer.field.limit)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if let key = session.buffer.issueKey { Text(LocalizedStringKey(key)).foregroundStyle(.secondary).accessibilityIdentifier("merchant.npcField.issue") }
                }
                Section {
                    Button("merchant.npcField.apply") { if session.apply() { close() } }
                        .disabled(!session.canApply).accessibilityIdentifier("merchant.npcField.apply")
                }
            }.disabled(!session.isCurrent || session.asksDiscard)
                .appNavigationTitle(key: session.buffer.field.titleKey)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { if session.requestClose() { close() } }.accessibilityIdentifier("merchant.npcField.cancel")
                } }
        }
        .privacySensitive()
        .interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)
        .alert("merchant.npcField.discardTitle", isPresented: Binding(get: { session.asksDiscard }, set: { _ in })) {
            Button("merchant.npcField.discard", role: .destructive) { if session.discard() { close() } }.accessibilityIdentifier("merchant.npcField.discard")
            Button("merchant.npcField.keepEditing", role: .cancel) { session.keepEditing() }.accessibilityIdentifier("merchant.npcField.keepEditing")
        } message: { Text("merchant.npcField.discardBody") }
        .onDisappear { session.cancel() }
    }
}
