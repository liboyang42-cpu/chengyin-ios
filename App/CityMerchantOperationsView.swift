import SwiftUI

private struct CityMerchantOperationsFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> CityMerchantOperationsController)? = nil
}
extension EnvironmentValues {
    var cityMerchantOperationsFactory: (@MainActor () -> CityMerchantOperationsController)? {
        get { self[CityMerchantOperationsFactoryKey.self] }
        set { self[CityMerchantOperationsFactoryKey.self] = newValue }
    }
}

@MainActor struct CityMerchantOperationsView: View {
    @State var controller: CityMerchantOperationsController
    @State private var reason = ""
    @State private var visit = CityMerchantVisitAdmission()
    @State private var active = false
    @State private var work: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    private let table = "CityMerchantOperations"
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text(LocalizedStringKey(controller.messageKey), tableName: table)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cityMerchant.status")
                    if controller.busy {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("m07-city-merchant-progress")
                    }
                }.padding(.vertical, Theme.Space.s1)
                if let value = controller.snapshot {
                    reference("cityMerchant.merchant", value: value.merchantId)
                    reference("cityMerchant.version", value: String(value.version))
                    Text(LocalizedStringKey(value.effectiveState == "PAUSED" ? "cityMerchant.state.paused" : "cityMerchant.state.inherit"), tableName: table)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let relation = value.relation {
                        reference("cityMerchant.board", value: relation.boardId)
                        reference("cityMerchant.rules", value: relation.rulesReleaseId)
                    }
                }
                Button { perform { await controller.load() } } label: { actionLabel("cityMerchant.reload") }.disabled(controller.busy)
            } header: { Text("cityMerchant.heading", tableName: table) }
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text("cityMerchant.reason", tableName: table)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField(text: $reason, axis: .vertical) { Text("cityMerchant.reason", tableName: table) }
                        .font(.body)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("cityMerchant.reason")
                }.padding(.vertical, Theme.Space.s1)
                Button { controller.prepare(.pause, reason: reason) } label: {
                    Label { Text("cityMerchant.pause", tableName: table).fixedSize(horizontal: false, vertical: true) }
                    icon: { Image(systemName: "pause.circle").accessibilityHidden(true) }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                    .disabled(!controller.canPrepare || controller.snapshot?.effectiveState == "PAUSED")
                    .accessibilityIdentifier("cityMerchant.pause")
                Button { controller.prepare(.restore, reason: reason) } label: {
                    Label { Text("cityMerchant.restore", tableName: table).fixedSize(horizontal: false, vertical: true) }
                    icon: { Image(systemName: "arrow.uturn.backward.circle").accessibilityHidden(true) }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                    .disabled(!controller.canPrepare || controller.snapshot?.effectiveState != "PAUSED")
                Text("cityMerchant.disclaimer", tableName: table).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("cityMerchant.intent.heading", tableName: table) }
            if let request = controller.pendingRequestID {
                Section {
                    reference("cityMerchant.original", value: request.uuidString)
                    Button { perform { await controller.recover() } } label: { actionLabel("cityMerchant.recover") }.disabled(controller.busy)
                } header: { Text("cityMerchant.original", tableName: table) }
            }
            if let receipt = controller.receipt, let id = receipt.originalRequestId {
                Section {
                    reference("cityMerchant.original", value: id)
                    Text("cityMerchant.receipt.recorded", tableName: table).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: receipt.status).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                } header: { Text("cityMerchant.receipt", tableName: table) }
            }
            if let rejection = controller.originalRejection {
                Section {
                    reference("cityMerchant.original", value: rejection.requestID.uuidString)
                    Text("cityMerchant.status.notApplied", tableName: table).font(.body).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: rejection.reason).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } header: { Text("cityMerchant.receipt", tableName: table) }
            }
            Button { retireVisit(); dismiss() } label: { actionLabel("cityMerchant.back") }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.bgPage(in: .merchant))
        .font(.body)
        .tint(Theme.Color.actionPrimaryBackground(in: .merchant))
        .themeDomain(.merchant)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(Text("cityMerchant.heading", tableName: table))
        .task {
            guard !Task.isCancelled else { return }
            visit.appear(); active = scenePhase == .active
            let captured = visit.revision
            guard visit.permits(captured, active: active) else { return }
            controller.activate(); await controller.load()
        }
        .onDisappear { retireVisit() }
        .onChange(of: scenePhase) { _, phase in
            visit.invalidate(); work?.cancel(); active = phase == .active; reason = ""
            controller.invalidate()
            guard visit.visible, active else { return }
            perform { controller.activate(); await controller.load() }
        }
        .alert(Text("cityMerchant.confirm.title", tableName: table), isPresented: Binding(get: { controller.confirmation != nil }, set: { if !$0 { controller.dismissConfirmation() } })) {
            Button(role: .cancel) { controller.dismissConfirmation() } label: { Text("cityMerchant.cancel", tableName: table) }
            Button { if let captured = controller.confirmation, controller.admitConfirmation(captured) { perform { await controller.confirm(captured) } } } label: { Text("cityMerchant.confirm.submit", tableName: table) }
        } message: {
            if let value = controller.confirmation {
                Text(LocalizedStringKey(value.kind == .pause ? "cityMerchant.confirm.pause" : "cityMerchant.confirm.restore"), tableName: table)
                + Text(verbatim: "\n")
                + Text("cityMerchant.confirm.detail \(value.merchantID) \(String(value.version)) \(value.reason)", tableName: table)
                + Text(verbatim: "\n")
                + Text("cityMerchant.confirm.boundary", tableName: table)
            }
        }
    }
    private func actionLabel(_ key: String) -> some View {
        Text(LocalizedStringKey(key), tableName: table)
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
    /// The original IDs remain selectable and wrap before they can hide a recovery handle.
    private func reference(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(LocalizedStringKey(key), tableName: table)
                .font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.s1)
        .accessibilityElement(children: .combine)
    }
    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        let captured = visit.revision
        guard visit.permits(captured, active: active), !controller.busy else { return }
        work?.cancel()
        work = Task { @MainActor in
            guard visit.permits(captured, active: active) else { return }
            await operation()
        }
    }
    private func retireVisit() {
        visit.disappear(); active = false; work?.cancel(); work = nil
        reason = ""; controller.invalidate()
    }
}
