import SwiftUI

/// Mounted only by the existing three coopField calls. No reader or writer is installed here.
@MainActor struct MerchantCoopFieldEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @Binding var route: MerchantCoopFieldSession?
    let fieldID: String
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool { MerchantCoopFieldSession.canOpen(document) }
    var body: some View {
        Group {
            if let field = MerchantCoopField(rawValue: fieldID) {
                Button {
                    guard scenePhase == .active, route == nil else { return }
                    route = .init(document: document, field: field)
                } label: {
                    HStack(alignment: .top) {
                        Text(LocalizedStringKey(field.titleKey))
                        Spacer()
                        if editable, case .cooperation(let settings) = document.coordinator.draft {
                            let value = field.value(in: settings)
                            if value.isEmpty { Text("merchant.coopField.empty").foregroundStyle(.secondary) }
                            else { Text(verbatim: value).lineLimit(2).foregroundStyle(.secondary) }
                        }
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!editable)
                    .accessibilityIdentifier("merchant.coopField.open." + field.rawValue)
            }
        }
    }
}

/// Stable editor presentation boundary; lazy rows never retire this route.
@MainActor struct MerchantCoopFieldStablePresentation: ViewModifier {
    @ObservedObject var document: MerchantOperationsViewModel
    @Binding var route: MerchantCoopFieldSession?
    @Environment(\.scenePhase) private var scenePhase
    private var editable: Bool { MerchantCoopFieldSession.canOpen(document) }
    func body(content: Content) -> some View {
        let shownID = route?.id
        content.background {
            Color.clear.frame(width: 0, height: 0)
        .sheet(item: Binding(get: { route }, set: { value in
            if value == nil, let shownID { close(shownID) }
        })) { selected in
            MerchantCoopFieldSheet(session: selected) { close(selected.id) }
        }
                .id(route?.id)
        }
        .onChange(of: document.revision) { _, _ in if route?.isCurrent == false { retire() } }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in retire() }
        .onChange(of: document.coordinator.reader.scope) { _, _ in retire() }
        .onChange(of: editable) { _, value in if !value { retire() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire() } }
        .onDisappear { retire() }
    }
    private func close(_ id: UUID) { guard route?.id == id else { return }; retire() }
    private func retire() { route?.cancel(); route = nil }
}

@MainActor private struct MerchantCoopFieldSheet: View {
    @ObservedObject var session: MerchantCoopFieldSession
    let close: () -> Void
    private var text: Binding<String> { .init(get: { session.buffer.value }, set: { _ = session.update($0) }) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchant.coopField.boundary").font(.footnote).foregroundStyle(.secondary)
                    if session.buffer.field == .demand {
                        TextEditor(text: text).frame(minHeight: 160)
                            .accessibilityLabel(Text(LocalizedStringKey(session.buffer.field.titleKey)))
                            .accessibilityIdentifier("merchant.coopField.input")
                    } else {
                        TextField(LocalizedStringKey(session.buffer.field.titleKey), text: text)
                            .keyboardType(session.buffer.field == .capacity ? .numberPad : .default)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("merchant.coopField.input")
                    }
                    Text("\(session.buffer.value.utf16.count) / \(session.buffer.field.limit)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if let key = session.buffer.issueKey {
                        Text(LocalizedStringKey(key)).foregroundStyle(.secondary).accessibilityIdentifier("merchant.coopField.issue")
                    }
                }
                Section {
                    Button("merchant.coopField.apply") { if session.apply() { close() } }
                        .disabled(!session.canApply).accessibilityIdentifier("merchant.coopField.apply")
                }
            }.disabled(!session.isCurrent || session.asksDiscard)
                .appNavigationTitle(key: session.buffer.field.titleKey)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { if session.requestClose() { close() } }
                        .accessibilityIdentifier("merchant.coopField.cancel")
                } }
        }
        .privacySensitive()
        .interactiveDismissDisabled(session.buffer.isDirty || session.asksDiscard)
        // Explicit buttons settle the decision; framework dismissal cannot consume it before its button callback.
        .alert("merchant.coopField.discardTitle", isPresented: Binding(get: { session.asksDiscard }, set: { _ in })) {
            Button("merchant.coopField.discard", role: .destructive) { if session.discard() { close() } }
                .accessibilityIdentifier("merchant.coopField.discard")
            Button("merchant.coopField.keepEditing", role: .cancel) { session.keepEditing() }
                .accessibilityIdentifier("merchant.coopField.keepEditing")
        } message: { Text("merchant.coopField.discardBody") }
    }
}
