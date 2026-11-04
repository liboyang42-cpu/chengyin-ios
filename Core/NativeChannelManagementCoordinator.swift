import Foundation
import Observation

@MainActor @Observable public final class NativeChannelManagementCoordinator {
    public let service: any NativeChannelManagementServing
    @ObservationIgnored private let journal: NativeChannelManagementJournal
    private let capturedIdentity: NativeChannelManagementIdentity?
    public private(set) var showingOwnHidden = false
    public private(set) var directory: NativeChannelManagementDirectory?
    public private(set) var detail: NativeChannelManagementChannel?
    public private(set) var managementInventory: [NativeChannelManagementChannel] = []
    public private(set) var managementInventoryEvidence: NativeChannelManagementInventory?
    public private(set) var permissions: NativeChannelManagementPermissions?
    public private(set) var roles: [NativeChannelManagementRole] = []
    public private(set) var effectivePermissions: NativeChannelManagementEffectivePermissions?
    public private(set) var prepared: NativeChannelManagementIntent?
    public private(set) var pending: NativeChannelManagementIntent?
    public private(set) var outcome: NativeChannelManagementOriginalOutcome?
    public private(set) var issue: NativeChannelManagementError?
    public private(set) var busy = false
    public private(set) var retired = false
    public var managerInventoryConfirmed: Bool {
        isCurrent && service.allows(.managementInventory) && managementInventoryEvidence?.identity == service.identity
            && managementInventoryEvidence?.scope == scope
    }
    private var confirmedAbsent = false
    public var scope: NativeChannelManagementScope { service.scope }
    public var isCurrent: Bool { !retired && service.isCurrent && capturedIdentity != nil && service.identity == capturedIdentity }
    public var canCreate: Bool { isCurrent && managerInventoryConfirmed && service.allows(.metadataCommand) && pending == nil }
    public var permissionWritesAvailable: Bool { isCurrent && service.allows(.permissionCommand) }
    private func canDispatch(_ intent: NativeChannelManagementIntent) -> Bool {
        intent.isPermissionChange ? (intent.hasPermissionCAS && permissionWritesAvailable) : service.allows(.metadataCommand)
    }
    public var canSubmitPrepared: Bool {
        isCurrent && !busy && pending == nil && prepared.map { canDispatch($0) } == true
    }
    public var canResendOriginal: Bool {
        isCurrent && !busy && confirmedAbsent && pending.map { canDispatch($0) } == true
    }
    public init(service: any NativeChannelManagementServing, journal: NativeChannelManagementJournal) throws {
        guard service.owner == journal.owner, service.scope == journal.scope else { throw NativeChannelManagementError.invalidSource }
        self.service = service; self.journal = journal; capturedIdentity = service.identity
    }
    public func synchronizeIdentity() {
        guard isCurrent else { retire(); return }
    }
    public func retire() {
        service.invalidate()
        retired = true; showingOwnHidden = false; directory = nil; detail = nil; permissions = nil; managementInventory = []; roles = []; effectivePermissions = nil
        prepared = nil; pending = nil; outcome = nil; confirmedAbsent = false; managementInventoryEvidence = nil
        issue = .changedIdentity
        // Durable original is intentionally retained in the protected, exact owner/scope journal.
    }
    private func requireCurrent() throws {
        guard isCurrent else { retire(); throw NativeChannelManagementError.changedIdentity }
    }
    public func restoreOriginal() {
        do { try requireCurrent(); pending = try journal.restore(); confirmedAbsent = false }
        catch { record(error) }
    }
    public func loadDirectory(showOwnHidden: Bool? = nil) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try requireCurrent(); issue = nil; directory = nil; managementInventory = []; managementInventoryEvidence = nil
            let includeHidden = showOwnHidden ?? showingOwnHidden
            let value: NativeChannelManagementDirectory
            if includeHidden { value = try await service.directoryIncludingOwnHidden() }
            else { value = try await service.directory() }
            try requireCurrent(); directory = value; showingOwnHidden = includeHidden
            if service.allows(.managementInventory) {
                do {
                    let inventory = try await service.inventory(); try requireCurrent()
                    guard inventory.identity == capturedIdentity, inventory.scope == scope else { throw NativeChannelManagementError.changedIdentity }
                    managementInventory = inventory.channels; managementInventoryEvidence = inventory
                } catch { try requireCurrent() /* Manager endpoint denial does not remove the member's real directory. */ }
            }
            pending = try journal.restore()
        } catch { directory = nil; managementInventory = []; managementInventoryEvidence = nil; record(error) }
    }
    public func loadDetail(_ id: NativeChannelManagementID) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        detail = nil; permissions = nil; prepared = nil
        do {
            try requireCurrent(); issue = nil
            let value = try await service.detail(id); try requireCurrent(); detail = value
        } catch { record(error) }
    }
    public func loadPermissions(_ id: NativeChannelManagementID) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        permissions = nil; prepared = nil; roles = []; effectivePermissions = nil
        do {
            try requireCurrent(); issue = nil
            let channel = try await service.detail(id); try requireCurrent()
            guard channel.canManagePermissions else { throw NativeChannelManagementError.forbidden }
            let value = try await service.permissions(id); try requireCurrent()
            guard value.version == channel.version, value.permissionVersion == channel.permissionVersion else {
                detail = nil; throw NativeChannelManagementError.versionConflict
            }
            let roleRows = try await service.roles(); try requireCurrent()
            let effective = try await service.effectivePermissions(id); try requireCurrent()
            guard effective.version == channel.version else { throw NativeChannelManagementError.versionConflict }
            detail = channel; permissions = value; roles = roleRows; effectivePermissions = effective
        } catch { permissions = nil; record(error) }
    }
    public func prepare(_ intent: NativeChannelManagementIntent) throws {
        try requireCurrent(); try intent.validate()
        guard !busy, intent.scope == scope, try journal.restore() == nil else { throw NativeChannelManagementError.pendingOriginal }
        if intent.operation == .create { guard canCreate else { throw NativeChannelManagementError.forbidden } }
        else if intent.operation == .restore {
            guard managerInventoryConfirmed, let inventory = managementInventoryEvidence, let id = intent.channelID else {
                throw NativeChannelManagementError.forbidden
            }
            let source = try inventory.restorableChannel(id)
            guard source.version == intent.expectedVersion else { throw NativeChannelManagementError.versionConflict }
        } else {
            let source = detail
            guard let source, source.id == intent.channelID, source.version == intent.expectedVersion else {
                throw NativeChannelManagementError.versionConflict
            }
            guard intent.isPermissionChange ? source.canManagePermissions : source.canManage else { throw NativeChannelManagementError.forbidden }
            if intent.isPermissionChange {
                guard permissions?.permissionVersion == intent.permissionVersion else { throw NativeChannelManagementError.versionConflict }
            }
        }
        prepared = intent; issue = nil; outcome = nil
    }
    public func cancelPreparation() { prepared = nil }
    public func submitPrepared() async {
        guard !busy, let intent = prepared else { return }
        guard canDispatch(intent) else { issue = intent.isPermissionChange && !intent.hasPermissionCAS
            ? .permissionCASUnavailable : .unavailable; return }
        await dispatch(intent, retryingOriginal: false)
    }
    private func dispatch(_ intent: NativeChannelManagementIntent, retryingOriginal: Bool) async {
        guard !busy, let operation = journal.beginOperation() else { issue = .pendingOriginal; return }
        busy = true; defer { journal.endOperation(operation); busy = false }
        do {
            try requireCurrent(); try journal.saveBeforeDispatch(intent)
            pending = intent; prepared = nil; confirmedAbsent = false; issue = nil
            let result = try await service.execute(intent); try requireCurrent()
            try result.validate(for: intent); try journal.settle(intent)
            pending = nil; outcome = .applied(result); clearCurrentProjection()
        } catch {
            guard isCurrent else { retire(); return }
            // A retry follows an earlier uncertain dispatch. Its rejection cannot settle that earlier outcome.
            if !retryingOriginal, let error = error as? NativeChannelManagementError {
                switch error {
                case .rejected, .versionConflict, .forbidden, .invalidDraft, .permissionCASUnavailable:
                    do { try journal.settle(intent); pending = nil }
                    catch { issue = .storageUnavailable; return }
                default: break
                }
            }
            record(error)
        }
    }
    public func recoverOriginal() async {
        guard !busy, let operation = journal.beginOperation() else { return }
        busy = true; defer { journal.endOperation(operation); busy = false }
        do {
            try requireCurrent(); confirmedAbsent = false; issue = nil
            guard let intent = try journal.restore() else { pending = nil; return }
            pending = intent
            let answer = try await service.originalOutcome(intent); try requireCurrent()
            outcome = answer
            switch answer {
            case .applied, .appliedRedacted:
                try journal.settle(intent); pending = nil; clearCurrentProjection()
            case .notFound: confirmedAbsent = true
            case .pending: break
            }
        } catch { record(error) }
    }
    /// Explicit user retry. Query again first, then reuse byte-identical original request and base version.
    public func resendOriginal() async {
        guard canResendOriginal else { return }
        await recoverOriginal()
        guard canResendOriginal, let intent = pending, outcome == .notFound else { return }
        await dispatch(intent, retryingOriginal: true)
    }
    private func clearCurrentProjection() {
        directory = nil; detail = nil; permissions = nil; managementInventory = []; managementInventoryEvidence = nil; roles = []; effectivePermissions = nil
    }
    private func record(_ error: Error) {
        guard isCurrent else { retire(); return }
        issue = (error as? NativeChannelManagementError) ?? .outcomeUnknown
        if issue == .forbidden || issue == .versionConflict {
            detail = nil; permissions = nil; prepared = nil
        }
        if case .some(.rejected(let code)) = issue,
           ["PERMISSION_DENIED", "CHANNEL_NOT_VISIBLE", "CHANNEL_ACCESS_DENIED", "GUILD_MEMBER_REQUIRED",
            "PERM_VERSION_CONFLICT", "PERM_VERSION_UNCONFIRMED", "CHANNEL_VERSION_CONFLICT"].contains(code) {
            clearCurrentProjection(); prepared = nil
        }
    }
}
