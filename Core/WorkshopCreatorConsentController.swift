import Foundation
import Observation

@MainActor public final class WorkshopCreatorConsentAppearance {
    fileprivate var started = false, closed = false
    fileprivate var action: UUID?
    public init() {}
    fileprivate func close() { closed = true; action = nil }
}
/// One recovery slot per owner/realm/actual CMS source. Stored commands are not creator authority.
@MainActor public final class WorkshopCreatorConsentPendingStore {
    private let storage: any TemplateAuthoringStorage
    private let ownerKey: String, source: Int64
    public init(storage: any TemplateAuthoringStorage, context: RuntimeDependencyContext, sourceTemplateId: Int64) throws {
        guard sourceTemplateId > 0, context.session.accountID > 0 else { throw WorkshopCreatorConsentIssue.invalid }
        self.storage = storage; source = sourceTemplateId
        ownerKey = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), String(sourceTemplateId)]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: ":")
    }
    private var key: String { "workshop-creator-consent.pending.v1." + WorkshopCreatorWire.sha(Data(ownerKey.utf8)) }
    private struct Record: Codable {
        let schema: String, ownerKey: String, command: WorkshopCreatorDeclarationCommand
        enum CodingKeys: String, CodingKey { case schema, ownerKey, command }
        init(ownerKey: String, command: WorkshopCreatorDeclarationCommand) { schema = "w18-creator-local-request-v1"; self.ownerKey = ownerKey; self.command = command }
        init(from decoder: Decoder) throws {
            try WorkshopCreatorWire.keys(decoder, ["schema", "ownerKey", "command"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(String.self, forKey: .schema); ownerKey = try c.decode(String.self, forKey: .ownerKey)
            command = try c.decode(WorkshopCreatorDeclarationCommand.self, forKey: .command)
            guard schema == "w18-creator-local-request-v1" else { throw WorkshopCreatorConsentIssue.storage }
        }
    }
    public func load() throws -> WorkshopCreatorDeclarationCommand? {
        do {
            guard let data = try storage.read(key) else { return nil }
            let record = try WorkshopCreatorWire.decode(Record.self, data: data, maximum: 8192)
            guard WorkshopCreatorWire.same(record.ownerKey, ownerKey), record.command.sourceTemplateId == source else { throw WorkshopCreatorConsentIssue.storage }
            return record.command
        } catch { throw WorkshopCreatorConsentIssue.storage }
    }
    func retain(_ command: WorkshopCreatorDeclarationCommand) throws {
        guard command.sourceTemplateId == source else { throw WorkshopCreatorConsentIssue.invalid }
        if let existing = try load() {
            guard try existing.data() == command.data() else { throw WorkshopCreatorConsentIssue.pending }; return
        }
        do {
            try storage.write(WorkshopCreatorWire.encode(Record(ownerKey: ownerKey, command: command)), key: key)
            guard let saved = try load(), try saved.data() == command.data() else { throw WorkshopCreatorConsentIssue.storage }
        } catch { throw WorkshopCreatorConsentIssue.storage }
    }
    /// Only an exact successful server receipt lets the author explicitly begin a different review.
    func acknowledge(_ receipt: WorkshopCreatorDeclarationReceipt, owner: Int64) throws {
        guard let pending = try load(), receipt.matches(pending, owner: owner) else { throw WorkshopCreatorConsentIssue.pending }
        do { try storage.remove(key); guard try storage.read(key) == nil else { throw WorkshopCreatorConsentIssue.storage } }
        catch { throw WorkshopCreatorConsentIssue.storage }
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopCreatorConsentController {
    public enum Phase: Equatable { case idle, loading, reviewing, submitting, recorded, failed, invalidated }
    public typealias Action = @MainActor () async -> Void
    public let identity = UUID(), sourceTemplateId: Int64
    public private(set) var phase: Phase = .idle
    public private(set) var preview: WorkshopCreatorPreview?
    public private(set) var targets: [WorkshopCreatorDeclarationTarget] = []
    public private(set) var selected: WorkshopCreatorDeclarationTarget?
    public private(set) var acknowledgments: Set<Int> = []
    public private(set) var pending: WorkshopCreatorDeclarationCommand?
    public private(set) var receipt: WorkshopCreatorDeclarationReceipt?
    public private(set) var issue: WorkshopCreatorConsentIssue?
    private let service: any WorkshopCreatorConsentServing, lease: ContentDraftSessionLease, store: WorkshopCreatorConsentPendingStore
    private let currentTargets: () -> [WorkshopCreatorDeclarationTarget], canWrite: () -> Bool, now: () -> Date
    private let reviewMatchesPreview: (WorkshopCreatorPreview) -> Bool
    private var appearance: WorkshopCreatorConsentAppearance?, lifetime: WorkshopCreatorConsentLifetime?
    public init(sourceTemplateId: Int64, service: any WorkshopCreatorConsentServing, lease: ContentDraftSessionLease, store: WorkshopCreatorConsentPendingStore,
                targets: @escaping () -> [WorkshopCreatorDeclarationTarget] = { [] }, canWrite: @escaping () -> Bool = { false }, now: @escaping () -> Date = Date.init,
                reviewMatchesPreview: @escaping (WorkshopCreatorPreview) -> Bool = { _ in true }) {
        self.sourceTemplateId = sourceTemplateId; self.service = service; self.lease = lease; self.store = store
        currentTargets = targets; self.canWrite = canWrite; self.now = now; self.reviewMatchesPreview = reviewMatchesPreview
    }
    public var canConfirm: Bool {
        guard phase == .reviewing, let preview, let selected, acknowledgments == Set([0, 1, 2]), canWrite(), validTarget(selected), reviewMatchesPreview(preview), receipt == nil else { return false }
        if let pending { return (try? WorkshopCreatorDeclarationCommand(preview: preview, target: selected, requestId: pending.requestId).data()) == (try? pending.data()) }
        return true
    }
    public func invalidate() {
        appearance?.close(); appearance = nil; lifetime?.revoke(); lifetime = nil; lease.revoke()
        preview = nil; targets = []; selected = nil; acknowledgments = []; pending = nil; receipt = nil; phase = .invalidated; issue = .stale
    }
    private func current(_ displayed: WorkshopCreatorConsentAppearance) -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated && appearance === displayed && !displayed.closed
    }
    public func appear(_ displayed: WorkshopCreatorConsentAppearance) -> Action? {
        guard lease.isCurrent, phase != .invalidated, !displayed.started, !displayed.closed else { return nil }
        displayed.started = true; appearance?.close(); lifetime?.revoke(); appearance = displayed
        return offerLoad(displayed)
    }
    public func close(_ displayed: WorkshopCreatorConsentAppearance) {
        displayed.close(); guard appearance === displayed else { return }
        lifetime?.revoke(); lifetime = nil; appearance = nil; preview = nil; targets = []; selected = nil; acknowledgments = []; receipt = nil
        if phase != .invalidated { phase = .idle }; issue = nil
        // Back cannot undo a possible committed declaration or erase its original request UUID.
    }
    private func offer(_ displayed: WorkshopCreatorConsentAppearance) -> (UUID, WorkshopCreatorConsentLifetime)? {
        guard current(displayed), phase != .submitting else { return nil }
        lifetime?.revoke(); let id = UUID(); displayed.action = id
        let life = WorkshopCreatorConsentLifetime { [weak self, weak displayed] in
            guard let self, let displayed else { return false }; return self.current(displayed) && displayed.action == id
        }
        lifetime = life; return (id, life)
    }
    private func validTarget(_ target: WorkshopCreatorDeclarationTarget) -> Bool {
        target.sourceTemplateId == sourceTemplateId && now() < target.expiresAt && currentTargets().contains(target)
    }
    public func offerLoad(_ displayed: WorkshopCreatorConsentAppearance) -> Action? {
        guard let (ticket, life) = offer(displayed) else { return nil }
        phase = .loading; preview = nil; selected = nil; targets = []; acknowledgments = []; issue = nil
        var entered = false
        return { [weak self] in
            guard let self, !entered, self.current(displayed), displayed.action == ticket else { return }; entered = true
            do {
                self.pending = try self.store.load()
                if let pending = self.pending {
                    let status = try await self.service.status(command: pending, lifetime: life); try life.check()
                    if case .recorded(let receipt) = status { try self.accept(receipt, pending); self.phase = .recorded; return }
                    self.issue = .unknown
                }
                let preview = try await self.service.preview(sourceTemplateId: self.sourceTemplateId, lifetime: life); try life.check()
                guard preview.sourceTemplateId == self.sourceTemplateId, self.reviewMatchesPreview(preview) else { throw WorkshopCreatorConsentIssue.malformed }
                self.preview = preview
                let choices = self.currentTargets().filter { self.validTarget($0) }
                guard choices.count <= 50, Set(choices.map(\.id)).count == choices.count else { throw WorkshopCreatorConsentIssue.invalid }
                self.targets = choices; self.phase = .reviewing
            } catch {
                guard self.current(displayed), displayed.action == ticket else { return }
                self.issue = (error as? WorkshopCreatorConsentIssue) ?? .unavailable; self.phase = .failed
            }
        }
    }
    public func select(_ target: WorkshopCreatorDeclarationTarget, appearance displayed: WorkshopCreatorConsentAppearance) {
        guard current(displayed), phase == .reviewing, targets.contains(target), validTarget(target) else { return }
        lifetime?.revoke(); displayed.action = nil; selected = target; acknowledgments = []
    }
    public func acknowledge(_ index: Int, value: Bool, appearance displayed: WorkshopCreatorConsentAppearance) {
        guard current(displayed), phase == .reviewing, (0...2).contains(index), let selected, validTarget(selected) else { return }
        if value { acknowledgments.insert(index) } else { acknowledgments.remove(index) }
    }
    /// Called synchronously by the displayed button, before creating a Task. The returned action
    /// captures the exact review and cannot obtain a replacement presentation's authority.
    public func offerConfirm(_ displayed: WorkshopCreatorConsentAppearance) -> Action? {
        guard current(displayed), canConfirm, let preview, let selected, let (ticket, life) = offer(displayed) else { return nil }
        let command: WorkshopCreatorDeclarationCommand
        do {
            command = try WorkshopCreatorDeclarationCommand(preview: preview, target: selected, requestId: pending?.requestId ?? UUID().uuidString.lowercased())
            try store.retain(command); pending = command
        } catch { issue = (error as? WorkshopCreatorConsentIssue) ?? .storage; return nil }
        acknowledgments = []; phase = .submitting; issue = nil
        let writeLife = WorkshopCreatorConsentLifetime { [weak self] in
            guard let self, (try? life.check()) != nil else { return false }
            return self.canWrite() && self.validTarget(selected)
        }
        let confirmation = WorkshopCreatorConsentConfirmation(command: command, lifetime: writeLife)
        var entered = false
        return { [weak self] in
            guard let self, !entered, self.current(displayed), displayed.action == ticket else { return }; entered = true
            do { try writeLife.check(); let receipt = try await self.service.declare(confirmation); try writeLife.check(); try self.accept(receipt, command); self.phase = .recorded }
            catch {
                guard self.current(displayed), displayed.action == ticket else { return }
                self.issue = (error as? WorkshopCreatorConsentIssue) ?? .unknown; self.phase = .reviewing
            }
        }
    }
    private func accept(_ receipt: WorkshopCreatorDeclarationReceipt, _ expected: WorkshopCreatorDeclarationCommand) throws {
        guard receipt.matches(expected, owner: Int64(lease.context.session.accountID)) else { throw WorkshopCreatorConsentIssue.malformed }
        self.receipt = receipt; preview = nil; targets = []; selected = nil; acknowledgments = []
        // Keep the recovery metadata across Back/logout until the author explicitly starts another review.
    }
    public func offerAnotherReview(_ displayed: WorkshopCreatorConsentAppearance) -> Action? {
        guard current(displayed), phase == .recorded, let receipt else { return nil }
        do { try store.acknowledge(receipt, owner: Int64(lease.context.session.accountID)); pending = nil; self.receipt = nil }
        catch { issue = .storage; return nil }
        return offerLoad(displayed)
    }
}
