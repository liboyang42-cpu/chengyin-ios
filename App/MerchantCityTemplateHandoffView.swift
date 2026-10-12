import SwiftUI

private struct MerchantCityTemplateHandoffFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> MerchantCityTemplateHandoffLaunch?)? = nil
}
extension EnvironmentValues {
    var merchantCityTemplateHandoffFactory: (@MainActor () -> MerchantCityTemplateHandoffLaunch?)? {
        get { self[MerchantCityTemplateHandoffFactoryKey.self] }
        set { self[MerchantCityTemplateHandoffFactoryKey.self] = newValue }
    }
}

/// Optional trailing action in the existing full merchant template editor. No save dispatch here.
@MainActor struct MerchantCityTemplateReturnAction {
    let register: (MerchantOperationsCoordinator) -> Void
    let canReturn: (MerchantOperationsCoordinator) -> Bool
    let returnSaved: (MerchantOperationsCoordinator) async -> Void
}
@MainActor struct MerchantCityTemplateReturnFooter: View {
    let coordinator: MerchantOperationsCoordinator
    let action: MerchantCityTemplateReturnAction
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("merchant.cityTemplate.savedOnly").font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("merchant.cityTemplate.useSaved") { Task { await action.returnSaved(coordinator) } }
                .buttonStyle(.borderedProminent).disabled(!action.canReturn(coordinator))
                .accessibilityIdentifier("merchant.cityTemplate.useSaved")
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            .task { action.register(coordinator) }
    }
}

@MainActor struct MerchantCityTemplateHandoffField: View {
    let binding: MerchantCityTemplateHandoffBinding
    @Environment(\.merchantCityTemplateHandoffFactory) private var factory
    @ObservedObject var model: MerchantCityTemplateHandoffModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("merchant.cityTemplate.configure") {
                let permit = model.generation
                Task {
                    guard model.accepts(permit) else { return }
                    await model.open(factory?(), binding: binding, permit: permit)
                }
            }
                .disabled(!model.active || factory == nil || !binding.canOpen() || model.busy || model.opening != nil)
                .accessibilityIdentifier("merchant.cityTemplate.configure")
            Text("merchant.cityTemplate.scope").font(.caption).fixedSize(horizontal: false, vertical: true)
            if model.busy && model.opening == nil { ProgressView("merchant.loading") }
            if factory == nil { Text("merchant.cityTemplate.unavailable").font(.caption) }
            if model.recoveryNeeded, model.opening == nil, binding.snapshot() == nil {
                Button("merchant.cityTemplate.retryPlacementRead") {
                    let permit = model.generation
                    Task { await model.recoverParent(binding: binding, permit: permit) }
                }
                    .disabled(!model.active || model.busy || !binding.canReload()).accessibilityIdentifier("merchant.cityTemplate.retryPlacementRead")
            }
            if model.applied { Text("merchant.cityTemplate.applied").font(.caption).accessibilityIdentifier("merchant.cityTemplate.applied") }
            if let issue = model.issue, model.opening == nil { Text(LocalizedStringKey(issue.key)).font(.caption) }
        }

    }
}

/// The placement editor owns the presentation; recycling the entry row must not retire it.
@MainActor struct MerchantCityTemplateHandoffPresentation: ViewModifier {
    @ObservedObject var model: MerchantCityTemplateHandoffModel
    let binding: MerchantCityTemplateHandoffBinding
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    func body(content: Content) -> some View {
        content.background {
            Color.clear.frame(width: 0, height: 0)
                .sheet(item: model.presentationBinding()) { original in
                    MerchantCityTemplateHandoffHost(model: model, original: original, binding: binding)
                        .id(original.id)
                }
                .id(model.opening?.id)
        }
        .onChange(of: binding.scope()) { _, _ in model.close() }
        .onAppear {
            isVisible = true
            if scenePhase == .active { model.activate() } else { model.deactivate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isVisible { model.activate() } else { model.deactivate() }
        }
        .onDisappear { isVisible = false; model.deactivate() }
    }
}

@MainActor private struct MerchantCityTemplateHandoffHost: View {
    @ObservedObject var model: MerchantCityTemplateHandoffModel
    let original: MerchantCityTemplateHandoffModel.Opening
    let binding: MerchantCityTemplateHandoffBinding
    var body: some View {
        NavigationStack {
            if model.returning {
                Form {
                    Text("merchant.cityTemplate.readbackScope")
                    if model.busy { ProgressView("merchant.loading") }
                    if let issue = model.issue {
                        Text(LocalizedStringKey(issue.key)).accessibilityIdentifier("merchant.cityTemplate.issue")
                        Button("merchant.cityTemplate.retryRead") { Task { await model.retryRead(original, binding: binding) } }
                            .disabled(model.busy || !binding.canReload() || !model.isCurrent(original, binding: binding))
                            .accessibilityIdentifier("merchant.cityTemplate.retryRead")
                    }
                }
                .appNavigationTitle("merchant.cityTemplate.returnTitle")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { model.close(id: original.id) }.accessibilityIdentifier("merchant.cityTemplate.cancelReturn") } }
            } else {
                MerchantOperationsDocumentView(reader: original.launch.reader, destination: .template(nil),
                    imageHost: original.launch.imageHost, templateAssistFactory: original.launch.templateAssistFactory,
                    templateReturn: .init(
                        register: { model.registerEditor($0, original: original, binding: binding) },
                        canReturn: { model.canReturn($0, original: original, binding: binding) },
                        returnSaved: { await model.accept($0, original: original, binding: binding) }))
            }
        }
        .interactiveDismissDisabled(model.busy)
        .onChange(of: binding.snapshot()?.observedAt) { _, _ in
            if !model.isCurrent(original, binding: binding) { model.close(id: original.id) }
        }
        .onChange(of: binding.draft()) { _, _ in
            if !model.isCurrent(original, binding: binding) { model.close(id: original.id) }
        }
        .onChange(of: original.launch.reader.scope) { _, _ in model.close(id: original.id) }
        .onDisappear { model.close(id: original.id) }
    }
}
