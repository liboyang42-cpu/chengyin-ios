import Foundation
import Combine
import SwiftUI

func nativeWebhookLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: "NativeWebhook", bundle: .main, value: key, comment: "")
}

func nativeWebhookLocalizedError(_ error: NativeWebhookClientError) -> String {
    let key: String, code: String
    switch error {
    case .sourceUnavailable(let value): key = "当前来源尚不可用（%@）"; code = value
    case .invalidInput(let value): key = "请检查输入（%@）"; code = value
    case .denied(let value, _): key = "当前没有管理权限（%@）"; code = value
    case .conflict(let value, _): key = "原请求或版本冲突（%@），请回读核对，不会覆盖。"; code = value
    case .rejected(_, let value, _): key = "请求被拒绝（%@）"; code = value
    default: return nativeWebhookLocalized(NativeWebhookPresentation.error(error))
    }
    return String(format: nativeWebhookLocalized(key), code)
}

enum NativeWebhookDestination: Hashable {
    case resource(NativeWebhookID), deliveryLog, inboundLog
}

enum NativeWebhookSheet: String, Identifiable {
    case subscriptionEditor, endpointEditor, confirmation, recovery, credential
    var id: String { rawValue }
}

/// Owns presentation only. The coordinator and the original session remain the authorities.
@MainActor final class NativeWebhookViewModel: ObservableObject {
    private(set) var coordinator: NativeWebhookCoordinator?
    @Published private(set) var version: UInt64 = 0
    @Published var path: [NativeWebhookDestination] = []
    @Published var sheet: NativeWebhookSheet? {
        didSet { if sheet != oldValue { presentationGeneration &+= 1 } }
    }
    private(set) var editing: NativeWebhookResource?
    private var started = false
    private var preparedDeletionID: UUID?
    private var presentationGeneration: UInt64 = 0
    private var constructionError: NativeWebhookClientError?
    private let makeCoordinator: (@MainActor () throws -> NativeWebhookCoordinator)?
    private var needsFreshVisit = false
    private var suspendedFamily: NativeWebhookFamily = .subscription
    private var suspendedSelection: NativeWebhookID?
    private var suspendedPath: [NativeWebhookDestination] = []

    init(makeCoordinator: (@MainActor () throws -> NativeWebhookCoordinator)? = nil) {
        self.makeCoordinator = makeCoordinator
        construct()
    }
    private func construct() {
        coordinator?.onChange = nil
        coordinator?.leave()
        if let makeCoordinator {
            do { coordinator = try makeCoordinator(); constructionError = nil }
            catch { coordinator = nil; constructionError = error as? NativeWebhookClientError ?? .sourceUnavailable("WEBHOOK_RUNTIME_FACTORY_UNAVAILABLE") }
        } else { coordinator = nil; constructionError = .sourceUnavailable("WEBHOOK_RUNTIME_FACTORY_UNAVAILABLE") }
        coordinator?.onChange = { [weak self] in self?.synchronize() }
        needsFreshVisit = false
    }
    var available: Bool {
        guard let coordinator else { return false }
        return coordinator.context != nil && coordinator.phase != .revoked && coordinator.phase != .denied
    }
    var canMutate: Bool { available && coordinator?.busy == false && coordinator?.pending == nil }
    var issueText: String? { (coordinator?.issue ?? constructionError).map(nativeWebhookLocalizedError) }
    var sheetBinding: Binding<NativeWebhookSheet?> {
        let generation = presentationGeneration
        let confirmationID = coordinator?.confirmation?.id, credentialID = coordinator?.credential?.requestID
        return Binding(get: { self.sheet }, set: { value in
            guard generation == self.presentationGeneration, confirmationID == self.coordinator?.confirmation?.id,
                  credentialID == self.coordinator?.credential?.requestID else { return }
            if value == nil { self.dismissSheet() } else { self.sheet = value }
        })
    }
    func start() async {
        guard !started else { return }; started = true
        if needsFreshVisit { construct() }
        await coordinator?.load()
    }
    func switchFamily(_ family: NativeWebhookFamily) async {
        guard let coordinator, !coordinator.busy, family != coordinator.family else { return }
        sheet = nil; editing = nil; path = []
        coordinator.clearSecret(); coordinator.cancelConfirmation()
        await coordinator.load(family: family)
    }
    func edit(_ resource: NativeWebhookResource? = nil) {
        guard canMutate, let coordinator else { return }
        editing = resource
        sheet = coordinator.family == .subscription ? .subscriptionEditor : .endpointEditor
    }
    func save(_ draft: NativeWebhookEditorDraft, original: NativeWebhookResource?) {
        guard canMutate else { return }
        preparedDeletionID = nil
        coordinator?.prepareChange(draft, original: original)
    }
    func action(_ action: NativeWebhookManagementAction, resource: NativeWebhookResource, delivery: NativeWebhookDelivery? = nil) {
        guard canMutate else { return }
        coordinator?.prepareAction(action, resource: resource, delivery: delivery)
        if case .delete = action { preparedDeletionID = coordinator?.confirmation?.id } else { preparedDeletionID = nil }
    }
    func setActive(_ active: Bool, resource: NativeWebhookResource) {
        var draft = NativeWebhookEditorDraft(resource: resource); draft.active = active
        save(draft, original: resource)
    }
    func openRecovery() async {
        guard available, let coordinator, !coordinator.busy, let pending = coordinator.pending else { return }
        if coordinator.family != pending.family { await switchFamily(pending.family) }
        guard available, coordinator.pending?.requestID == pending.requestID else { return }
        sheet = .recovery
    }
    func dismissSheet() {
        if sheet == .confirmation { coordinator?.cancelConfirmation() }
        if sheet == .credential { coordinator?.clearSecret() }
        sheet = nil; editing = nil; preparedDeletionID = nil
    }
    func confirm(_ id: UUID) async {
        let isDeletion = preparedDeletionID == id
        await coordinator?.confirm(id)
        if isDeletion, preparedDeletionID == id {
            if coordinator?.pending == nil, coordinator?.selected == nil { path = [] }
            preparedDeletionID = nil
        }
    }
    func background() {
        sheet = nil; editing = nil; preparedDeletionID = nil
        if !needsFreshVisit {
            suspendedFamily = coordinator?.family ?? .subscription
            suspendedSelection = coordinator?.selected?.id
            suspendedPath = path
        }
        needsFreshVisit = true
        coordinator?.background()
        coordinator?.leave()
    }
    func foreground() async {
        guard needsFreshVisit else { await coordinator?.revalidate(); return }
        construct()
        guard let coordinator else { return }
        await coordinator.load(family: suspendedFamily)
        // Reopen only authoritative reads. Never replay the durable pending mutation.
        guard self.coordinator === coordinator, coordinator.presentationIsCurrent(), coordinator.context != nil else { return }
        if let id = suspendedSelection {
            await coordinator.select(id)
            guard self.coordinator === coordinator, coordinator.presentationIsCurrent(), coordinator.selected?.id == id else { return }
            path = suspendedPath
            if path.last == .deliveryLog || path.last == .inboundLog { await coordinator.logs() }
        }
        version &+= 1
    }
    func leave() {
        started = false; needsFreshVisit = true; sheet = nil; editing = nil; path = []; preparedDeletionID = nil
        suspendedPath = []; suspendedSelection = nil
        coordinator?.leave()
    }
    private func synchronize() {
        guard let coordinator else { return }
        if coordinator.phase == .revoked || coordinator.phase == .denied {
            sheet = nil; editing = nil; path = []; preparedDeletionID = nil
        } else if coordinator.confirmation != nil {
            sheet = .confirmation; editing = nil
        } else if coordinator.credential != nil {
            sheet = .credential; editing = nil
        } else if sheet == .confirmation || sheet == .credential {
            sheet = nil
        }
        version &+= 1
    }
}

/// A nil factory is the ordinary default. Composition must supply the reviewed real sources.
@MainActor struct NativeWebhookManagementEntry: View {
    @StateObject private var model: NativeWebhookViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    init(makeCoordinator: (@MainActor () throws -> NativeWebhookCoordinator)? = nil) {
        _model = StateObject(wrappedValue: NativeWebhookViewModel(makeCoordinator: makeCoordinator))
    }
    var body: some View {
        NavigationStack(path: $model.path) {
            NativeWebhookManagementView(model: model)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(nativeWebhookLocalized("返回频道")) { model.leave(); dismiss() }
                            .accessibilityIdentifier("webhook.channel.return")
                    }
                }
                .navigationDestination(for: NativeWebhookDestination.self) { destination in
                    switch destination {
                    case .resource(let id): NativeWebhookResourceDetail(model: model, resourceID: id)
                    case .deliveryLog: NativeWebhookDeliveryLogView(model: model)
                    case .inboundLog: NativeWebhookInboundLogView(model: model)
                    }
                }
        }
        .task { await model.start() }
        .sheet(item: model.sheetBinding) { sheet in
            NavigationStack {
                switch sheet {
                case .subscriptionEditor: NativeWebhookSubscriptionEditor(model: model, resource: model.editing)
                case .endpointEditor: NativeWebhookEndpointEditor(model: model, resource: model.editing)
                case .confirmation: NativeWebhookConfirmationView(model: model)
                case .recovery: NativeWebhookRecoveryView(model: model)
                case .credential: NativeWebhookOneTimeCredentialView(model: model)
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.foreground() } }
            else { model.background() }
        }
        // This modifier belongs to the entry's NavigationStack, never to pushed list/detail views.
        .onDisappear { model.leave() }
        .accessibilityIdentifier("webhook.management.entry")
    }
}

@MainActor struct NativeWebhookStatusSection: View {
    @ObservedObject var model: NativeWebhookViewModel
    var body: some View {
        if let text = model.issueText {
            Section { NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized(text)),symbol:"exclamationmark.circle").accessibilityIdentifier("webhook.issue") }
        }
        if let notice = model.coordinator?.notice {
            Section {
                if let state = model.coordinator?.lastDeliveryReceiptState {
                    Text(String(format: nativeWebhookLocalized("投递请求回执：%@。请回读原日志核对最终状态。"), nativeWebhookLocalized(NativeWebhookPresentation.delivery(state))))
                        .accessibilityIdentifier("webhook.notice")
                } else { Text(nativeWebhookLocalized(notice)).accessibilityIdentifier("webhook.notice") }
            }
        }
        if model.coordinator?.busy == true {
            Section { ProgressView(nativeWebhookLocalized("正在核对当前频道…")).accessibilityIdentifier("webhook.loading") }
        }
    }
}

@MainActor private struct NativeWebhookConfirmationView: View {
    @ObservedObject var model: NativeWebhookViewModel
    var body: some View {
        Form {
            if let confirmation = model.coordinator?.confirmation {
                Section {
                    NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized(confirmation.title)),message:Text(verbatim:nativeWebhookLocalized(confirmation.message)),symbol:"doc.text.magnifyingglass")
                    NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("原请求编号")),value:confirmation.requestID.rawValue)
                }
                Section {
                    Button(nativeWebhookLocalized("确认提交")) { Task { await model.confirm(confirmation.id) } }.nativeChannelFlowAction()
                        .disabled(!model.available || model.coordinator?.busy == true)
                        .accessibilityIdentifier("webhook.confirm.submit")
                    Button(nativeWebhookLocalized("取消"), role: .cancel) { model.dismissSheet() }
                        .accessibilityIdentifier("webhook.confirm.cancel")
                }
                NativeWebhookStatusSection(model: model)
            } else { Text(nativeWebhookLocalized("确认已失效，请返回当前频道核对。")) }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized(model.coordinator?.confirmation?.title ?? "确认操作"))
        .interactiveDismissDisabled(model.coordinator?.busy == true)
        .accessibilityIdentifier("webhook.confirmation")
    }
}

@MainActor private struct NativeWebhookRecoveryView: View {
    @ObservedObject var model: NativeWebhookViewModel
    @State private var originalURL = ""
    @State private var originalAvatarURL = ""
    var body: some View {
        Form {
            if let pending = model.coordinator?.pending {
                Section(nativeWebhookLocalized("待核对原请求")) {
                    NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("原请求编号")),value:pending.requestID.rawValue)
                    Text(nativeWebhookLocalized("恢复会沿用原请求，不会取回已脱敏的首次密钥。"))
                }
                if pending.redactedFields.contains("url") {
                    Section(nativeWebhookLocalized("重新输入原 URL")) {
                        SecureField(nativeWebhookLocalized("原操作的完整 URL"), text: $originalURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("webhook.recovery.url")
                    }
                }
                if pending.redactedFields.contains("avatar_url") {
                    Section(nativeWebhookLocalized("重新输入原头像 URL")) {
                        SecureField(nativeWebhookLocalized("原操作的完整头像 URL"), text: $originalAvatarURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("webhook.recovery.avatarURL")
                    }
                }
                if pending.binding != model.coordinator?.context?.binding {
                    Section { Text(nativeWebhookLocalized("当前授权上下文与原请求不同，暂不能恢复。原记录继续保留。")) }
                }
                NativeWebhookStatusSection(model: model)
                Button(nativeWebhookLocalized("核对并恢复原请求")) {
                    model.coordinator?.prepareRecovery(url: pending.redactedFields.contains("url") ? originalURL : nil,
                        avatarURL: pending.redactedFields.contains("avatar_url") ? originalAvatarURL : nil)
                }
                .disabled(!model.available || model.coordinator?.busy == true || pending.binding != model.coordinator?.context?.binding
                    || (pending.redactedFields.contains("url") && originalURL.isEmpty)
                    || (pending.redactedFields.contains("avatar_url") && originalAvatarURL.isEmpty))
                .accessibilityIdentifier("webhook.recovery.prepare")
            } else { NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized("当前没有待恢复的原请求。")),symbol:"tray") }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("恢复原请求"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nativeWebhookLocalized("取消")) { model.dismissSheet() } } }
        .onDisappear { originalURL = ""; originalAvatarURL = "" }
        .accessibilityIdentifier("webhook.recovery")
    }
}

@MainActor extension AppCompositionRoot {
    /// Install only the original caller's approved transport/context source. An absent
    /// source removes availability; this helper creates no grant or runtime fallback.
    mutating func bindNativeWebhookManagementSource(_ source: NativeWebhookManagementContextSource?,
        transport: any HTTPTransport, approval: @escaping NativeWebhookConfiguredRuntimeFactory.Approval) {
        guard let source else { nativeWebhookRuntimeFactory = nil; return }
        nativeWebhookRuntimeFactory = NativeWebhookConfiguredRuntimeFactory(transport: transport,
            lookup: { captured, scope in try await source.context(captured, scope: scope) }, approval: approval)
    }
}
