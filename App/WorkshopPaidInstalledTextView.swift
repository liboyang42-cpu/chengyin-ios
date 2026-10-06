import SwiftUI

typealias WorkshopPaidInstalledTextControllerFactory = @MainActor (WorkshopPaidInstalledTextReference) -> WorkshopPaidInstalledTextController?

/// Visible on an actual installed receipt. The reference is minted synchronously by the live
/// install/history controller; a delayed callback cannot borrow a later presentation.
@MainActor struct WorkshopPaidInstalledTextEntry: View {
    let makeReference: @MainActor () -> WorkshopPaidInstalledTextReference?
    let makeController: WorkshopPaidInstalledTextControllerFactory
    @State private var presentation: WorkshopPaidInstalledTextPresentation
    init(makeReference: @escaping @MainActor () -> WorkshopPaidInstalledTextReference?, makeController: @escaping WorkshopPaidInstalledTextControllerFactory,
         presentation: WorkshopPaidInstalledTextPresentation? = nil) {
        self.makeReference = makeReference; self.makeController = makeController
        _presentation = State(initialValue: presentation ?? WorkshopPaidInstalledTextPresentation())
    }
    private var presented: Binding<WorkshopPaidInstalledTextPresentation.Selection?> {
        let expected = presentation.selection?.id
        return Binding(get: { presentation.selection?.id == expected ? presentation.selection : nil },
                       set: { presentation.replace($0, expected: expected) })
    }
    var body: some View {
        Button {
            presentation.open(makeReference: makeReference, makeController: makeController)
        } label: { Label { paidText("entry") } icon: { Image(systemName: "doc.text.magnifyingglass") } }
        .accessibilityIdentifier("workshopPaidInstalledText.entry")
        if presentation.unavailable { paidText("notConfigured").font(.footnote).fixedSize(horizontal: false, vertical: true) }
        Color.clear.frame(height: 0)
            .sheet(item: presented) { captured in
                WorkshopPaidInstalledTextView(controller: captured.controller, appearance: captured.appearance) {
                    presentation.dismiss(captured)
                }.id(captured.id)
            }
    }
}
@MainActor struct WorkshopPaidInstalledTextView: View {
    let controller: WorkshopPaidInstalledTextController
    let appearance: WorkshopPaidInstalledTextAppearance
    let onClose: () -> Void
    @State private var ownedTask: Task<Void, Never>?
    @State private var showsInstalled = false
    @Environment(\.locale) private var locale
    var body: some View {
        let displayed = appearance
        NavigationStack {
            Form {
                Section { paidText("scope").fixedSize(horizontal: false, vertical: true) }
                if controller.phase == .invalidated {
                    paidText("sessionChanged")
                } else if controller.phase == .loading {
                    ProgressView { paidText("loading") }
                } else if let content = controller.content {
                    Section {
                        paidFact("version", content.version)
                        paidFact("purchasedVersion", content.purchasedVersionID)
                        paidFact("installedCopy", String(content.ownedDraftID))
                        paidFact("sourceHash", content.contentHash)
                        paidText("unchangedCopy").fixedSize(horizontal: false, vertical: true)
                        paidText("modeUnresolved").fixedSize(horizontal: false, vertical: true)
                    } header: { paidText("provenance") }
                    Section {
                        Picker(selection: $showsInstalled) {
                            paidText("original").tag(false)
                            paidText("installed").tag(true)
                        } label: { paidText("comparison") }
                            .pickerStyle(.segmented)
                        let fields = showsInstalled ? content.installedFields : content.sourceFields
                        ForEach(WorkshopPaidInstalledTextFields.names, id: \.self) { name in
                            if let value = fields[name] {
                                DisclosureGroup {
                                    Text(verbatim: value).fixedSize(horizontal: false, vertical: true)
                                } label: { paidText("field." + name) }
                            }
                        }
                    } header: { paidText("protectedFields") }
                    Section {
                        paidFact("termsVersion", content.termsVersion)
                        paidFact("termsHash", content.termsHash)
                        paidFact("termsDocumentHash", content.termsDocumentHash)
                        paidFact("termsBytes", String(content.termsDocument.count))
                        paidText("opaqueTerms").fixedSize(horizontal: false, vertical: true)
                        paidText("perpetualVersion").fixedSize(horizontal: false, vertical: true)
                        paidText("noRedistribution").fixedSize(horizontal: false, vertical: true)
                        paidText(content.rights.adaptation == .localAdaptation ? "adaptationAllowed" : "adaptationNotGranted")
                            .fixedSize(horizontal: false, vertical: true)
                    } header: { paidText("frozenTerms") }
                    Section { paidText("materializationRequired").fixedSize(horizontal: false, vertical: true) }
                } else if controller.phase == .unavailable {
                    Section {
                        paidText(controller.issue == .disabled ? "notConfigured" : "unavailable").fixedSize(horizontal: false, vertical: true)
                        Button { schedule(controller.offerReload(displayed)) } label: { paidText("retry") }
                            .accessibilityIdentifier("workshopPaidInstalledText.retry")
                    }
                }
            }
            .privacySensitive()
            .navigationTitle(String(localized: LocalizedStringResource("workshopPaidInstalledText.title", table: "WorkshopPaidInstalledText", locale: locale)))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { controller.close(displayed); ownedTask?.cancel(); onClose() } label: { paidText("close") }
                    .accessibilityIdentifier("workshopPaidInstalledText.close")
            } }
        }
        .onAppear { schedule(controller.appear(displayed)) }
        .onDisappear { controller.close(displayed); ownedTask?.cancel() }
    }
    private func schedule(_ action: WorkshopPaidInstalledTextController.Action?) {
        guard let action else { return }; ownedTask?.cancel(); ownedTask = Task { await action() }
    }
    private func paidFact(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { paidText(key).font(.caption).foregroundStyle(.secondary); Text(verbatim: value) }
            .fixedSize(horizontal: false, vertical: true)
    }
}
private func paidText(_ key: String) -> Text { Text(LocalizedStringKey("workshopPaidInstalledText." + key), tableName: "WorkshopPaidInstalledText") }
