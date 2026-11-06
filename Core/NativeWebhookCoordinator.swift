import Foundation

/// Ordinary entry -> current authority -> real service -> original-operation recovery.
/// No timer, automatic mutation replay, test send or credential generation is registered.
@MainActor public final class NativeWebhookCoordinator {
    public var onChange: (() -> Void)?
    public private(set) var context: NativeWebhookContext?
    public private(set) var phase: NativeWebhookPhase = .dormant
    public private(set) var family: NativeWebhookFamily = .subscription
    public private(set) var resources: [NativeWebhookResource] = []
    public private(set) var resourceCursor: String?
    public private(set) var hasMoreResources = false
    public private(set) var selected: NativeWebhookResource?
    public private(set) var deliveries: [NativeWebhookDelivery] = []
    public private(set) var inboundLogs: [NativeWebhookInboundLog] = []
    public private(set) var logCursor: String?
    public private(set) var hasMoreLogs = false
    public private(set) var deliveryFilter: NativeWebhookDeliveryState?
    public private(set) var inboundFilter: NativeWebhookInboundState?
    public private(set) var includePayload = false
    public private(set) var busy = false
    public private(set) var issue: NativeWebhookClientError?
    public private(set) var notice: String?
    public private(set) var lastDeliveryReceiptState: NativeWebhookDeliveryState?
    public private(set) var confirmation: NativeWebhookConfirmation?
    public private(set) var credential: NativeWebhookOneTimeCredential?
    public private(set) var pending: NativeWebhookPendingMetadata?
    private let service: NativeWebhookHTTPService
    private let provider: any NativeWebhookScopeProvider
    private let journal: NativeWebhookPendingJournal
    private var prepared: NativeWebhookMutationRequest?
    private var generation: UInt64 = 0
    private var credentialGeneration: UInt64 = 0
    private var runtimeRetirement: (() -> Void)?
    /// Host-owned current channel/parent-route predicate. It never grants authority.
    /// Unbound standalone fixtures retain their original lifecycle semantics.
    public private(set) var presentationIsCurrent: () -> Bool = { true }
    /// Install the host's irreversible visit retirement once. A later caller cannot
    /// replace the original retirement action or widen its presentation fence.
    @discardableResult public func bindRuntimeRetirement(_ retire: @escaping () -> Void,
        presentationIsCurrent: @escaping () -> Bool = { true }) -> Bool {
        guard runtimeRetirement == nil else { return false }
        runtimeRetirement = retire
        let existing = self.presentationIsCurrent
        self.presentationIsCurrent = { existing() && presentationIsCurrent() }
        if !self.presentationIsCurrent() { invalidate() }
        return true
    }
    /// A child UI can add its real channel/parent-route fence after factory creation.
    /// Restrictions compose monotonically; no later caller can reopen a closed parent.
    public func restrictPresentation(to restriction: @escaping () -> Bool) {
        let existing = presentationIsCurrent
        presentationIsCurrent = { existing() && restriction() }
        if !presentationIsCurrent() { invalidate() }
    }
    private func visitIsCurrent(_ stamp: UInt64) -> Bool {
        stamp == generation && presentationIsCurrent() && !Task.isCancelled
    }
    public init(service: NativeWebhookHTTPService, provider: any NativeWebhookScopeProvider, journal: NativeWebhookPendingJournal) {
        self.service = service; self.provider = provider; self.journal = journal
    }
    public func load(family: NativeWebhookFamily? = nil, nextPage: Bool = false) async {
        guard presentationIsCurrent(), !Task.isCancelled, !busy else { return }
        if let family, family != self.family { clearSecret(); cancelConfirmation(); resetContents(); self.family = family; generation &+= 1 }
        let stamp = generation
        busy = true; issue = nil; phase = .loading; changed()
        defer { if stamp == generation { busy = false; changed() } }
        do {
            guard visitIsCurrent(stamp) else { return }
            let live = try await provider.currentContext()
            guard visitIsCurrent(stamp) else { return }
            if let old = context, old.binding != live.binding { invalidate(); return }
            context = live; pending = try journal.pending(live.binding)
            let cursor = nextPage ? resourceCursor : nil
            guard !nextPage || hasMoreResources else { phase = resources.isEmpty ? .empty : .ready; return }
            let page = try await service.resources(self.family, context: live, cursor: cursor)
            guard visitIsCurrent(stamp), context?.binding == live.binding else { return }
            resources = nextPage ? merge(resources, page.list) : page.list
            resourceCursor = page.nextCursor; hasMoreResources = page.hasMore
            phase = resources.isEmpty ? .empty : .ready
        } catch { if visitIsCurrent(stamp) { fail(error) } }
    }
    public func select(_ id: NativeWebhookID) async {
        guard presentationIsCurrent(), !Task.isCancelled, !busy, let context else { return }
        generation &+= 1; let stamp = generation; clearSecret(); resetLogs(); selected = nil
        busy = true; issue = nil; changed()
        defer { if stamp == generation { busy = false; changed() } }
        do {
            guard visitIsCurrent(stamp) else { return }
            let value = try await service.resource(family, id: id, context: context)
            guard visitIsCurrent(stamp) else { return }; selected = value
        } catch { if visitIsCurrent(stamp) { fail(error) } }
    }
    public func logs(nextPage: Bool = false, deliveryFilter: NativeWebhookDeliveryState? = nil,
                     inboundFilter: NativeWebhookInboundState? = nil, includePayload: Bool = false) async {
        guard presentationIsCurrent(), !Task.isCancelled, !busy, let context, let selected else { return }
        let changedFilter = self.deliveryFilter != deliveryFilter || self.inboundFilter != inboundFilter || self.includePayload != includePayload
        if changedFilter { resetLogs() }
        self.deliveryFilter = deliveryFilter; self.inboundFilter = inboundFilter; self.includePayload = includePayload
        let stamp = generation; busy = true; issue = nil; changed()
        defer { if stamp == generation { busy = false; changed() } }
        do {
            guard visitIsCurrent(stamp) else { return }
            guard !nextPage || hasMoreLogs else { return }
            let cursor = nextPage ? logCursor : nil
            if family == .subscription {
                let page = try await service.deliveries(selected.id, context: context, state: deliveryFilter, cursor: cursor, includePayload: includePayload)
                guard visitIsCurrent(stamp) else { return }; deliveries = nextPage && !changedFilter ? merge(deliveries, page.list) : page.list
                logCursor = page.nextCursor; hasMoreLogs = page.hasMore
            } else {
                let page = try await service.inboundLogs(selected.id, context: context, result: inboundFilter, cursor: cursor)
                guard visitIsCurrent(stamp) else { return }; inboundLogs = nextPage && !changedFilter ? merge(inboundLogs, page.list) : page.list
                logCursor = page.nextCursor; hasMoreLogs = page.hasMore
            }
        } catch { if visitIsCurrent(stamp) { fail(error) } }
    }
    public func prepareChange(_ draft: NativeWebhookEditorDraft, original: NativeWebhookResource?) {
        do {
            try canPrepare(); guard let context else { throw NativeWebhookClientError.scopeChanged }
            let change = try draft.change(family: family, context: context, original: original, requestID: .make())
            prepared = try service.changeRequest(family, change: change, original: original, context: context)
            confirmation = NativeWebhookConfirmation(title: original == nil ? "确认新建" : "确认保存修改",
                message: "仅操作当前频道。提交后会保存原请求用于结果核对。", requestID: change.requestID)
            issue = nil; changed()
        } catch { fail(error); changed() }
    }
    public func prepareAction(_ action: NativeWebhookManagementAction, resource: NativeWebhookResource, delivery: NativeWebhookDelivery? = nil) {
        do {
            try canPrepare(); guard let context else { throw NativeWebhookClientError.scopeChanged }
            let id = NativeWebhookRequestID.make()
            prepared = try service.actionRequest(action, family: family, resource: resource, context: context, requestID: id, delivery: delivery)
            let title: String, message: String
            switch action {
            case .delete: title = "确认删除"; message = "停用并删除当前集成，保留历史日志。"
            case .rotate: title = "确认轮换密钥"; message = "将产生新的签名密钥。入站旧 token 的失效时间以回执为准，新凭据仅显示一次。"
            case .test: title = "确认测试事件入队"; message = "这会请求服务端排队测试投递，排队不代表已送达。"
            case .retry: title = "确认重试原投递"; message = "沿用原事件和原投递记录，不能保证已送达。"
            }
            confirmation = NativeWebhookConfirmation(title: title, message: message, requestID: id); issue = nil; changed()
        } catch { fail(error); changed() }
    }
    public func prepareRecovery(url: String? = nil, avatarURL: String? = nil) {
        do {
            guard presentationIsCurrent(), !Task.isCancelled, !busy, let context, let pending else { throw NativeWebhookClientError.scopeChanged }
            // The loaded context came from the current original authority. Rebind only the
            // same durable scope; perform() checks it again before any original replay.
            prepared = try pending.rebound(to: context.binding).originalRequest(url: url, avatarURL: avatarURL)
            confirmation = NativeWebhookConfirmation(title: "恢复原请求", message: "仅重放原 method、路径和内容，不创建新请求；已脱敏的首次密钥不能取回。", requestID: pending.requestID)
            issue = nil; changed()
        } catch { fail(error); changed() }
    }
    public func cancelConfirmation() { confirmation = nil; prepared = nil; changed() }
    public func confirm(_ confirmationID: UUID) async {
        guard presentationIsCurrent(), !Task.isCancelled, !busy, confirmation?.id == confirmationID, let operation = prepared,
              operation.binding == context?.binding else { return }
        let stamp = generation, secretStamp = credentialGeneration
        confirmation = nil; prepared = nil; credential = nil; notice = nil; lastDeliveryReceiptState = nil; issue = nil; busy = true; changed()
        defer { if stamp == generation { busy = false; changed() } }
        do {
            guard visitIsCurrent(stamp), context?.binding == operation.binding else { return }
            try journal.reserve(operation); pending = try journal.pending(operation.binding)
            guard visitIsCurrent(stamp), context?.binding == operation.binding else { return }
            let receipt = try await service.perform(operation)
            guard visitIsCurrent(stamp), context?.binding == operation.binding else { return }
            try journal.settle(operation); pending = nil
            switch receipt {
            case .resource(let value):
                selected = value.resource.deleted ? nil : value.resource
                if secretStamp == credentialGeneration { credential = value.credential }
                let credentialLost = value.credentialWasNotRecovered || (value.credential != nil && secretStamp != credentialGeneration)
                notice = credentialLost ? "结果已确认，密钥首次返回未取得。若需要新凭据，请另外确认轮换。" : "操作结果已确认。"
            case .delivery(let value):
                lastDeliveryReceiptState = value.state
                deliveries = merge(deliveries, [value]); notice = "投递请求回执：\(NativeWebhookPresentation.delivery(value.state))。请回读原日志核对最终状态。"
            }
            // Keep one busy owner across the receipt and all authoritative readback awaits.
            // No public load/select call may reopen a second mutation in this interval.
            let live = try await provider.revalidate(operation.binding)
            guard visitIsCurrent(stamp), live.binding == operation.binding else { return }
            let page = try await service.resources(family, context: live)
            guard visitIsCurrent(stamp) else { return }
            resources = page.list; resourceCursor = page.nextCursor; hasMoreResources = page.hasMore
            phase = resources.isEmpty ? .empty : .ready
            if let id = selected?.id {
                let value = try await service.resource(family, id: id, context: live)
                guard visitIsCurrent(stamp) else { return }; selected = value
            }
            if operation.returnsDelivery, let id = operation.resourceID {
                let page = try await service.deliveries(id, context: live, state: deliveryFilter, includePayload: includePayload)
                guard visitIsCurrent(stamp) else { return }
                deliveries = page.list; logCursor = page.nextCursor; hasMoreLogs = page.hasMore
            }
        } catch {
            if visitIsCurrent(stamp) {
                // Even 409/denial is never permission to mint a new key over an unresolved original.
                fail(error)
                if context != nil { pending = try? journal.pending(operation.binding) }
            }
        }
    }
    public func clearSecret() { credential = nil; credentialGeneration &+= 1; changed() }
    /// Host calls synchronously on every session/scope/grant/config change, including ABA.
    /// Unresolved durable original requests are retained; private presentation is not.
    public func invalidate() {
        runtimeRetirement?()
        generation &+= 1; credentialGeneration &+= 1; busy = false; context = nil; resetContents()
        prepared = nil; confirmation = nil; credential = nil; pending = nil; notice = nil; lastDeliveryReceiptState = nil; issue = .scopeChanged; phase = .revoked; changed()
    }
    public func leave() { invalidate() }
    public func background() {
        runtimeRetirement?()
        clearSecret(); prepared = nil; confirmation = nil; changed()
    }
    public func revalidate() async {
        guard presentationIsCurrent(), !Task.isCancelled, let context else { return }; let stamp = generation
        do { let live = try await provider.revalidate(context.binding); if visitIsCurrent(stamp), live.binding != context.binding { invalidate() } }
        catch { if visitIsCurrent(stamp) { invalidate() } }
    }
    private func canPrepare() throws {
        guard presentationIsCurrent(), !Task.isCancelled, !busy, let context else { throw NativeWebhookClientError.scopeChanged }
        if try journal.pending(context.binding) != nil { throw NativeWebhookClientError.conflict(code: "ORIGINAL_REQUEST_PENDING", traceID: nil) }
    }
    private func fail(_ error: Error) {
        let value = error as? NativeWebhookClientError ?? .sourceUnavailable("WEBHOOK_STORAGE_OR_SOURCE_UNAVAILABLE")
        if case .denied = value { invalidate(); issue = value; phase = .denied }
        else if value == .scopeChanged { invalidate() }
        else if case .sourceUnavailable = value { invalidate(); issue = value; phase = .unavailable }
        else { issue = value; if case .resultUnknown = value { phase = .unknown } else { phase = .unavailable } }
    }
    private func changed() { onChange?() }
    private func resetContents() { resources = []; resourceCursor = nil; hasMoreResources = false; selected = nil; resetLogs() }
    private func resetLogs() { deliveries = []; inboundLogs = []; logCursor = nil; hasMoreLogs = false }
    private func merge<T: Identifiable>(_ old: [T], _ new: [T]) -> [T] where T.ID: Hashable {
        var result = old; for value in new { if let index = result.firstIndex(where: { $0.id == value.id }) { result[index] = value } else { result.append(value) } }; return result
    }
}
