import Foundation
import Combine
import SwiftUI

func nativeWebhookLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: "NativeWebhook", bundle: .main, value: key, comment: "")
}

func nativeWebhookLocalizedError(_ error: NativeWebhookClientError) -> String {
    let key: String
    switch error {
    case .sourceUnavailable: key = "d7.webhook.error.unavailable"
    case .scopeChanged: key = "d7.webhook.error.changed"
    case .invalidWire: key = "d7.webhook.error.response"
    case .invalidInput: key = "d7.webhook.error.input"
    case .originalInputRequired: key = "d7.webhook.error.reenterURL"
    case .denied: key = "d7.webhook.error.denied"
    case .conflict: key = "d7.webhook.error.conflict"
    case .rejected: key = "d7.webhook.error.rejected"
    case .resultUnknown: key = "d7.webhook.error.unknown"
    case .cancelled: key = "d7.webhook.error.cancelled"
    }
    return nativeWebhookLocalized(key)
}

func nativeWebhookDeliveryText(_ state: NativeWebhookDeliveryState) -> String {
    switch state {
    case .pending: return nativeWebhookLocalized("d7.webhook.delivery.pending")
    case .inflight: return nativeWebhookLocalized("d7.webhook.delivery.sending")
    case .sent: return nativeWebhookLocalized("d7.webhook.delivery.sent")
    case .failed: return nativeWebhookLocalized("d7.webhook.delivery.failed")
    case .dead: return nativeWebhookLocalized("d7.webhook.delivery.stopped")
    case .unknown: return nativeWebhookLocalized("d7.webhook.status.unconfirmed")
    case .cancelled: return nativeWebhookLocalized("d7.webhook.delivery.cancelled")
    }
}

func nativeWebhookInboundText(_ state: NativeWebhookInboundState) -> String {
    switch state {
    case .received: return nativeWebhookLocalized("d7.webhook.inbound.received")
    case .pendingReview: return nativeWebhookLocalized("d7.webhook.inbound.inReview")
    case .accepted: return nativeWebhookLocalized("d7.webhook.inbound.posted")
    case .rejected: return nativeWebhookLocalized("d7.webhook.inbound.rejected")
    case .blocked: return nativeWebhookLocalized("d7.webhook.inbound.blocked")
    case .rateLimited: return nativeWebhookLocalized("d7.webhook.inbound.rateLimited")
    case .unknown: return nativeWebhookLocalized("d7.webhook.status.unconfirmed")
    }
}

/// Server times shown as local dates; the raw value is never displayed.
struct NativeWebhookTimeRow: View {
    let label: String
    let time: NativeWebhookServerTime
    var body: some View {
        LabeledContent(label) { Text(time.date, format: .dateTime.year().month().day().hour().minute()) }
    }
}

/// Maps the coordinator's fixed confirmation wording to plain copy. Unknown wording falls back to the table.
private func nativeWebhookConfirmationCopy(_ confirmation: NativeWebhookConfirmation) -> (title: String, message: String?) {
    switch confirmation.title {
    case "确认新建": return (nativeWebhookLocalized("d7.webhook.confirm.create"), nil)
    case "确认保存修改": return (nativeWebhookLocalized("d7.webhook.confirm.save"), nil)
    case "确认删除": return (nativeWebhookLocalized("d7.webhook.confirm.delete"), nativeWebhookLocalized("d7.webhook.confirm.delete.message"))
    case "确认轮换密钥": return (nativeWebhookLocalized("d7.webhook.confirm.reset"), nativeWebhookLocalized("d7.webhook.confirm.reset.message"))
    case "确认测试事件入队": return (nativeWebhookLocalized("d7.webhook.confirm.test"), nil)
    case "确认重试原投递": return (nativeWebhookLocalized("d7.webhook.confirm.retry"), nil)
    case "恢复原请求": return (nativeWebhookLocalized("d7.webhook.confirm.resume"), nativeWebhookLocalized("d7.webhook.confirm.resume.message"))
    default: return (nativeWebhookLocalized(confirmation.title), nativeWebhookLocalized(confirmation.message))
    }
}

/// Maps the coordinator's fixed result notices to plain copy.
private func nativeWebhookNoticeText(_ notice: String) -> String {
    switch notice {
    case "操作结果已确认。": return nativeWebhookLocalized("d7.webhook.notice.saved")
    case "结果已确认，密钥首次返回未取得。若需要新凭据，请另外确认轮换。": return nativeWebhookLocalized("d7.webhook.notice.savedNoSecret")
    default: return nativeWebhookLocalized(notice)
    }
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
                        Button(nativeWebhookLocalized("d7.webhook.done")) { model.leave(); dismiss() }
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
            .presentationDetents(sheet == .confirmation ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
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
            Section { NativeChannelFlowNotice(title:Text(verbatim:text),symbol:"exclamationmark.circle").accessibilityIdentifier("webhook.issue") }
        }
        if let notice = model.coordinator?.notice {
            Section {
                if let state = model.coordinator?.lastDeliveryReceiptState {
                    Text(String(format: nativeWebhookLocalized("d7.webhook.notice.delivery %@"), nativeWebhookDeliveryText(state)))
                        .accessibilityIdentifier("webhook.notice")
                } else { Text(nativeWebhookNoticeText(notice)).accessibilityIdentifier("webhook.notice") }
            }
        }
        if model.coordinator?.busy == true {
            Section { ProgressView(nativeWebhookLocalized("d7.webhook.loading")).accessibilityIdentifier("webhook.loading") }
        }
    }
}

@MainActor private struct NativeWebhookConfirmationView: View {
    @ObservedObject var model: NativeWebhookViewModel
    var body: some View {
        Form {
            if let confirmation = model.coordinator?.confirmation {
                if let message = nativeWebhookConfirmationCopy(confirmation).message {
                    Section { Text(message).fixedSize(horizontal: false, vertical: true) }
                }
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.confirm.submit")) { Task { await model.confirm(confirmation.id) } }.nativeChannelFlowAction()
                        .disabled(!model.available || model.coordinator?.busy == true)
                        .accessibilityIdentifier("webhook.confirm.submit")
                    Button(nativeWebhookLocalized("d7.webhook.cancel"), role: .cancel) { model.dismissSheet() }
                        .accessibilityIdentifier("webhook.confirm.cancel")
                }
                NativeWebhookStatusSection(model: model)
            } else {
                ContentUnavailableView(nativeWebhookLocalized("d7.webhook.confirm.expired"), systemImage: "clock.arrow.circlepath")
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle((model.coordinator?.confirmation).map { nativeWebhookConfirmationCopy($0).title } ?? nativeWebhookLocalized("d7.webhook.confirm.title"))
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
                if pending.redactedFields.contains("url") {
                    Section(nativeWebhookLocalized("d7.webhook.field.url")) {
                        SecureField(nativeWebhookLocalized("d7.webhook.field.url.prompt"), text: $originalURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("webhook.recovery.url")
                    }
                }
                if pending.redactedFields.contains("avatar_url") {
                    Section(nativeWebhookLocalized("d7.webhook.field.avatar")) {
                        SecureField(nativeWebhookLocalized("d7.webhook.field.avatar.prompt"), text: $originalAvatarURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("webhook.recovery.avatarURL")
                    }
                }
                if pending.binding != model.coordinator?.context?.binding {
                    Section { NativeChannelFlowNotice(title: Text(verbatim: nativeWebhookLocalized("d7.webhook.resume.accessChanged")), symbol: "lock") }
                }
                NativeWebhookStatusSection(model: model)
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.resume.continue")) {
                        model.coordinator?.prepareRecovery(url: pending.redactedFields.contains("url") ? originalURL : nil,
                            avatarURL: pending.redactedFields.contains("avatar_url") ? originalAvatarURL : nil)
                    }
                    .nativeChannelFlowAction()
                    .disabled(!model.available || model.coordinator?.busy == true || pending.binding != model.coordinator?.context?.binding
                        || (pending.redactedFields.contains("url") && originalURL.isEmpty)
                        || (pending.redactedFields.contains("avatar_url") && originalAvatarURL.isEmpty))
                    .accessibilityIdentifier("webhook.recovery.prepare")
                }
            } else { ContentUnavailableView(nativeWebhookLocalized("d7.webhook.resume.none"), systemImage: "tray") }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("d7.webhook.resume.title"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nativeWebhookLocalized("d7.webhook.cancel")) { model.dismissSheet() } } }
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
