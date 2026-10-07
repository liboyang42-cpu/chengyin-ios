import Foundation
import Observation

/// All mutable offer choices start empty. Required fixed restrictions are displayed separately.
public struct WorkshopCreatorPendingForm: Equatable {
    public var termsDocument = "", commercialUse = "", adaptation = "", translation = ""
    public var allowedRegions = "", buyerKinds = "", themeLimit = "", merchantLimit = "", runLimit = ""
    public var priceMinor = "", currency = "", expiresAt = ""
    public init() {}
    func command(preview: WorkshopCreatorPreview, now: Date) throws -> WorkshopCreatorPendingCommand {
        guard let theme = Int64(themeLimit), let merchant = Int64(merchantLimit), let run = Int64(runLimit), let price = Int64(priceMinor),
              [themeLimit, merchantLimit, runLimit, priceMinor].allSatisfy({ !$0.isEmpty && !$0.contains(where: { $0.isWhitespace }) }) else { throw WorkshopCreatorConsentIssue.invalid }
        return try WorkshopCreatorPendingCommand(preview: preview, termsDocument: termsDocument, commercialUse: commercialUse,
            adaptation: adaptation, translation: translation, allowedRegions: allowedRegions, buyerKinds: buyerKinds,
            themeLimit: theme, merchantLimit: merchant, runLimit: run, priceMinor: price, currency: currency, expiresAt: expiresAt, now: now)
    }
}
@MainActor public final class WorkshopCreatorPendingAppearance {
    fileprivate var started = false, closed = false
    fileprivate var action: UUID?
    public init() {}
}
/// Complete command, including exact full terms, saved device-only by the injected secure store.
/// This is recovery data, never consent or evidence that the source is still eligible.
@MainActor public final class WorkshopCreatorPendingStore {
    private let storage: any TemplateAuthoringStorage, ownerKey: String, source: Int64
    public init(storage: any TemplateAuthoringStorage, context: RuntimeDependencyContext, sourceTemplateId: Int64) throws {
        guard sourceTemplateId > 0, context.session.accountID > 0 else { throw WorkshopCreatorConsentIssue.invalid }
        self.storage = storage; source = sourceTemplateId
        ownerKey = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), String(sourceTemplateId)]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: ":")
    }
    private var key: String { "workshop-creator-author.pending.v1." + WorkshopCreatorWire.sha(Data(ownerKey.utf8)) }
    private struct Record: Codable {
        let schema: String, ownerKey: String, command: WorkshopCreatorPendingCommand
        enum CodingKeys: String, CodingKey { case schema, ownerKey, command }
        init(ownerKey: String, command: WorkshopCreatorPendingCommand) { schema = "w18-creator-author-local-v1"; self.ownerKey = ownerKey; self.command = command }
        init(from decoder: Decoder) throws {
            try WorkshopCreatorWire.keys(decoder, ["schema", "ownerKey", "command"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(String.self, forKey: .schema); ownerKey = try c.decode(String.self, forKey: .ownerKey)
            command = try c.decode(WorkshopCreatorPendingCommand.self, forKey: .command)
            guard schema == "w18-creator-author-local-v1" else { throw WorkshopCreatorConsentIssue.storage }
        }
    }
    public func load() throws -> WorkshopCreatorPendingCommand? {
        do {
            guard let data = try storage.read(key) else { return nil }
            let record = try WorkshopCreatorPendingWire.decode(Record.self, data: data, maximum: 262_144)
            guard WorkshopCreatorWire.same(record.ownerKey, ownerKey), record.command.sourceTemplateId == source, try WorkshopCreatorWire.encode(record) == data else { throw WorkshopCreatorConsentIssue.storage }
            return record.command
        } catch { throw WorkshopCreatorConsentIssue.storage }
    }
    func retain(_ command: WorkshopCreatorPendingCommand) throws {
        guard command.sourceTemplateId == source else { throw WorkshopCreatorConsentIssue.invalid }
        if let old = try load() {
            guard try old.data() == command.data() else { throw WorkshopCreatorConsentIssue.pending }; return
        }
        do {
            try storage.write(WorkshopCreatorWire.encode(Record(ownerKey: ownerKey, command: command)), key: key)
            guard let saved = try load(), try saved.data() == command.data() else { throw WorkshopCreatorConsentIssue.storage }
        } catch { throw WorkshopCreatorConsentIssue.storage }
    }
    func acknowledge(_ receipt: WorkshopCreatorPendingMetadata) throws {
        guard let command = try load(), receipt.matches(command: command) else { throw WorkshopCreatorConsentIssue.pending }
        do { try storage.remove(key); guard try storage.read(key) == nil else { throw WorkshopCreatorConsentIssue.storage } }
        catch { throw WorkshopCreatorConsentIssue.storage }
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopCreatorPendingController {
    public enum Phase: Equatable { case idle, loading, editing, submitting, failed, reviewing, invalidated }
    public typealias Action = @MainActor () async -> Void
    public typealias MakeConsent = (WorkshopCreatorDeclarationTarget, @escaping (WorkshopCreatorPreview) -> Bool) -> WorkshopCreatorConsentController?
    public let identity = UUID(), sourceTemplateId: Int64
    public var form = WorkshopCreatorPendingForm()
    public private(set) var phase: Phase = .idle
    public private(set) var preview: WorkshopCreatorPreview?
    public private(set) var items: [WorkshopCreatorPendingMetadata] = []
    public private(set) var nextCursor: String?
    public private(set) var hasMore = false
    public private(set) var pending: WorkshopCreatorPendingCommand?
    public private(set) var receipt: WorkshopCreatorPendingMetadata?
    public private(set) var declarationReceipt: WorkshopCreatorDeclarationReceipt?
    public private(set) var declarationRequestId: String?
    public private(set) var selectedDetail: WorkshopCreatorPendingDetail?
    public private(set) var declaration: WorkshopCreatorConsentController?
    public private(set) var issue: WorkshopCreatorConsentIssue?
    private let service: any WorkshopCreatorPendingServing, previewService: any WorkshopCreatorConsentServing
    private let lease: ContentDraftSessionLease, store: WorkshopCreatorPendingStore, now: () -> Date, canAuthor: () -> Bool
    private let declarationStore: WorkshopCreatorConsentPendingStore?
    private let canReadProposals: () -> Bool
    private let makeConsent: MakeConsent
    private var appearance: WorkshopCreatorPendingAppearance?
    private var lifetime: WorkshopCreatorConsentLifetime?
    public init(sourceTemplateId: Int64, service: any WorkshopCreatorPendingServing, previewService: any WorkshopCreatorConsentServing,
                lease: ContentDraftSessionLease, store: WorkshopCreatorPendingStore, declarationStore: WorkshopCreatorConsentPendingStore? = nil,
                canReadProposals: @escaping () -> Bool = { true }, canAuthor: @escaping () -> Bool = { false },
                now: @escaping () -> Date = Date.init, makeConsent: @escaping MakeConsent) {
        self.sourceTemplateId = sourceTemplateId; self.service = service; self.previewService = previewService
        self.lease = lease; self.store = store; self.declarationStore = declarationStore; self.canReadProposals = canReadProposals; self.canAuthor = canAuthor; self.now = now; self.makeConsent = makeConsent
    }
    public var canSubmit: Bool { phase == .editing && pending == nil && preview != nil && canAuthor() && lease.isCurrent }
    public var canRetry: Bool { pending != nil && receipt == nil && ![.loading, .submitting, .reviewing, .invalidated].contains(phase) && canAuthor() && lease.isCurrent }
    public func invalidate() {
        closeCurrent(); lease.revoke(); form = .init(); pending = nil; receipt = nil; phase = .invalidated; issue = .stale
    }
    private func closeCurrent() {
        appearance?.closed = true; appearance?.action = nil; appearance = nil; lifetime?.revoke(); lifetime = nil
        declaration?.invalidate(); declaration = nil; declarationReceipt = nil; declarationRequestId = nil; selectedDetail = nil; preview = nil; items = []; nextCursor = nil; hasMore = false
    }
    private func current(_ a: WorkshopCreatorPendingAppearance) -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated && appearance === a && !a.closed
    }
    public func appear(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard lease.isCurrent, phase != .invalidated, !a.started, !a.closed else { return nil }
        closeCurrent(); a.started = true; appearance = a
        return offerLoad(a)
    }
    public func close(_ a: WorkshopCreatorPendingAppearance) {
        a.closed = true; a.action = nil; guard appearance === a else { return }
        closeCurrent(); form = .init(); receipt = nil; if phase != .invalidated { phase = .idle }; issue = nil
        // The full persisted command survives Back, cancellation, session changes and unknown results.
    }
    private func offer(_ a: WorkshopCreatorPendingAppearance) -> (UUID, WorkshopCreatorConsentLifetime)? {
        guard current(a), phase != .submitting else { return nil }
        lifetime?.revoke(); let ticket = UUID(); a.action = ticket
        let life = WorkshopCreatorConsentLifetime { [weak self, weak a] in
            guard let self, let a else { return false }; return self.current(a) && a.action == ticket
        }
        lifetime = life; return (ticket, life)
    }
    public func offerLoad(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard let (ticket, life) = offer(a) else { return nil }
        declaration?.invalidate(); declaration = nil; selectedDetail = nil; preview = nil; items = []; nextCursor = nil; hasMore = false
        phase = .loading; issue = nil; pending = nil; declarationReceipt = nil; declarationRequestId = nil
        var entered = false
        return { [weak self] in
            guard let self, !entered, self.current(a), a.action == ticket else { return }; entered = true
            do {
                // Preserve native16 history recovery before any current-source or proposal gate.
                // A recorded receipt is metadata only; it never supplies a current target.
                if let command = try self.declarationStore?.load() {
                    self.declarationRequestId = command.requestId
                    let status = try await self.previewService.status(command: command, lifetime: life); try life.check()
                    switch status {
                    case .recorded(let receipt):
                        guard receipt.matches(command, owner: Int64(self.lease.context.session.accountID)) else { throw WorkshopCreatorConsentIssue.malformed }
                        self.declarationReceipt = receipt
                    case .notFound(let requestId):
                        guard requestId == command.requestId else { throw WorkshopCreatorConsentIssue.malformed }
                        self.issue = .unknown
                    }
                }
                self.pending = try self.store.load()
                guard self.canReadProposals() else { self.issue = .disabled; self.phase = .editing; return }
                try await self.refresh(life)
                self.phase = .editing
            } catch { self.fail(error, a, ticket) }
        }
    }
    private func refresh(_ life: WorkshopCreatorConsentLifetime) async throws {
        guard canReadProposals() else { throw WorkshopCreatorConsentIssue.disabled }; try life.check()
        let p = try await previewService.preview(sourceTemplateId: sourceTemplateId, lifetime: life); try life.check()
        let page = try await service.list(sourceTemplateId: sourceTemplateId, afterTargetId: nil, lifetime: life); try life.check()
        guard p.sourceTemplateId == sourceTemplateId, page.sourceTemplateId == sourceTemplateId,
              page.items.allSatisfy({ $0.sourceTemplateId == sourceTemplateId && $0.templateHash == p.templateHash && $0.packageContentHash == p.packageContentHash }) else { throw WorkshopCreatorConsentIssue.malformed }
        preview = p; items = page.items; nextCursor = page.nextCursor; hasMore = page.hasMore
    }
    public func offerMore(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard phase == .editing, hasMore, let cursor = nextCursor, let preview, let (ticket, life) = offer(a) else { return nil }
        phase = .loading; var entered = false
        return { [weak self] in
            guard let self, !entered, self.current(a), a.action == ticket else { return }; entered = true
            do {
                let page = try await self.service.list(sourceTemplateId: self.sourceTemplateId, afterTargetId: cursor, lifetime: life); try life.check()
                guard page.items.allSatisfy({ $0.sourceTemplateId == self.sourceTemplateId && $0.templateHash == preview.templateHash && $0.packageContentHash == preview.packageContentHash }),
                      Set((self.items + page.items).map(\.targetId)).count == self.items.count + page.items.count,
                      !page.hasMore || page.nextCursor != cursor else { throw WorkshopCreatorConsentIssue.malformed }
                self.items += page.items; self.nextCursor = page.nextCursor; self.hasMore = page.hasMore; self.phase = .editing
            } catch { self.fail(error, a, ticket) }
        }
    }
    public func offerAuthor(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard current(a), canSubmit, let preview else { return nil }
        do { return offerDispatch(try form.command(preview: preview, now: now()), a) }
        catch { issue = (error as? WorkshopCreatorConsentIssue) ?? .invalid; return nil }
    }
    public func offerRetry(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard current(a), canRetry, let pending else { return nil }
        // No author-status route exists. Retry the same 21 fields and request UUID byte-for-byte.
        return offerDispatch(pending, a)
    }
    private func offerDispatch(_ command: WorkshopCreatorPendingCommand, _ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard let (ticket, life) = offer(a), canAuthor() else { return nil }
        do { try store.retain(command); pending = command }
        catch { issue = (error as? WorkshopCreatorConsentIssue) ?? .storage; return nil }
        let confirmation = WorkshopCreatorPendingConfirmation(command: command, lifetime: life)
        phase = .submitting; issue = nil; receipt = nil; var entered = false
        return { [weak self] in
            guard let self, !entered, self.current(a), a.action == ticket else { return }; entered = true
            do {
                try life.check(); guard self.canAuthor() else { throw WorkshopCreatorConsentIssue.disabled }
                let receipt = try await self.service.author(confirmation); try life.check()
                guard receipt.matches(command: command) else { throw WorkshopCreatorConsentIssue.malformed }
                self.receipt = receipt
                // Historic metadata success never becomes a selectable current target.
                self.preview = nil; self.items = []; self.selectedDetail = nil; self.nextCursor = nil; self.hasMore = false
                try await self.refresh(life); self.phase = .editing
            } catch { self.fail(error, a, ticket) }
        }
    }
    public func offerAnotherProposal(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard current(a), phase != .submitting, let receipt else { return nil }
        do { try store.acknowledge(receipt); pending = nil; self.receipt = nil; form = .init() }
        catch { issue = .storage; return nil }
        return offerLoad(a)
    }
    public func offerReview(_ item: WorkshopCreatorPendingMetadata, _ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard phase == .editing, canReadProposals(), items.contains(item), let (ticket, life) = offer(a) else { return nil }
        phase = .loading; selectedDetail = nil; declaration?.invalidate(); declaration = nil; var entered = false
        return { [weak self] in
            guard let self, !entered, self.current(a), a.action == ticket else { return }; entered = true
            do {
                let preview = try await self.previewService.preview(sourceTemplateId: self.sourceTemplateId, lifetime: life); try life.check()
                let detail = try await self.service.detail(sourceTemplateId: self.sourceTemplateId, targetId: item.targetId, expectedRevision: item.revision, lifetime: life); try life.check()
                guard detail.metadata == item, detail.matches(preview: preview, now: self.now()) else { throw WorkshopCreatorConsentIssue.stale }
                let target = try detail.declarationTarget(preview: preview, now: self.now())
                self.preview = preview; self.selectedDetail = detail
                guard let consent = self.makeConsent(target, { [weak self] currentPreview in
                    guard let self, self.lease.isCurrent, self.phase == .reviewing, self.selectedDetail?.metadata == item else { return false }
                    return detail.matches(preview: currentPreview, now: self.now())
                }) else { throw WorkshopCreatorConsentIssue.disabled }
                self.declaration = consent; self.phase = .reviewing
            } catch { self.fail(error, a, ticket) }
        }
    }
    public func offerBackToProposals(_ a: WorkshopCreatorPendingAppearance) -> Action? {
        guard current(a), phase == .reviewing else { return nil }
        declaration?.invalidate(); declaration = nil; selectedDetail = nil
        return offerLoad(a)
    }
    private func fail(_ error: Error, _ a: WorkshopCreatorPendingAppearance, _ ticket: UUID) {
        guard current(a), a.action == ticket else { return }
        issue = (error as? WorkshopCreatorConsentIssue) ?? .unavailable; phase = .failed
        preview = nil; items = []; nextCursor = nil; hasMore = false; selectedDetail = nil; declaration?.invalidate(); declaration = nil
    }
}
