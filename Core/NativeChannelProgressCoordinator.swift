import Foundation
import Observation

@MainActor @Observable public final class NativeChannelProgressCoordinator {
    @ObservationIgnored private let access: any NativeChannelProgressAccess
    @ObservationIgnored private let journal: NativeChannelProgressPrivacyJournal
    private let captured: NativeChannelProgressAuthoritySnapshot
    private var generation: UInt64 = 0
    private var active = false
    private var authorityRetired = false
    private var working = false
    private var rawDefinitions: [NativeChannelProgressBoard] = []
    private var rawOverview: NativeChannelProgressOverview?
    private var rawMeter: NativeChannelProgressMeter?
    private var rawTop = NativeChannelProgressPageBuffer()
    private var rawDetail = NativeChannelProgressPageBuffer()
    private var rawRecent = NativeChannelProgressPageBuffer()
    private var rawBest: NativeChannelProgressRow?
    private var rawPrivacy: NativeChannelProgressPrivacy?
    private var rawReceipt: NativeChannelProgressPrivacy?
    private var pending: NativeChannelProgressPrivacyCommand?
    private var privacyState: NativeChannelProgressPrivacyPhase = .idle
    private var issues: [String: String] = [:]
    private var selectedBoard: NativeChannelProgressBoard?
    private var selectedQuery: NativeChannelProgressQuery?
    public var isCurrent: Bool {
        guard active, !authorityRetired else { return false }
        guard access.authority == captured else { authorityRetired = true; invalidate(); return false }
        return true
    }
    public var channelID: Int64? { captured.channelID }
    public var identity: NativeChannelProgressIdentity { captured.identity }
    public var busy: Bool { isCurrent && working }
    public var definitions: [NativeChannelProgressBoard] { isCurrent ? rawDefinitions : [] }
    public var overview: NativeChannelProgressOverview? { isCurrent ? rawOverview : nil }
    public var meter: NativeChannelProgressMeter? { isCurrent ? rawMeter : nil }
    public var top: NativeChannelProgressPageBuffer { isCurrent ? rawTop : .init() }
    public var detail: NativeChannelProgressPageBuffer { isCurrent ? rawDetail : .init() }
    public var recent: NativeChannelProgressPageBuffer { isCurrent ? rawRecent : .init() }
    public var best: NativeChannelProgressRow? { isCurrent ? rawBest : nil }
    public var privacy: NativeChannelProgressPrivacy? { isCurrent ? rawPrivacy : nil }
    public var receipt: NativeChannelProgressPrivacy? { isCurrent ? rawReceipt : nil }
    public var pendingCommand: NativeChannelProgressPrivacyCommand? { isCurrent ? pending : nil }
    public var privacyPhase: NativeChannelProgressPrivacyPhase { isCurrent ? privacyState : .accessClosed }
    public var canSavePrivacy: Bool { isCurrent && !working && pending == nil && privacyState != .persistenceFailed && rawPrivacy != nil && captured.operations.contains(.savePrivacy) }
    public func issue(_ part: String) -> String? { isCurrent ? issues[part] : "closed" }
    public init(access: any NativeChannelProgressAccess, journal: NativeChannelProgressPrivacyJournal) throws {
        guard let authority = access.authority, journal.owner == NativeChannelProgressJournalOwner(authority.identity) else { throw NativeChannelProgressError.closed }
        self.access = access; self.journal = journal; captured = authority
    }
    public func activate() async {
        guard !working else { return }
        active = true
        guard isCurrent else { invalidate(); return }
        await loadDirectory()
    }
    public func activatePrivacy() async {
        guard !working else { return }; active = true
        guard isCurrent else { invalidate(); return }; await loadPrivacy()
    }
    public func invalidate() {
        generation &+= 1; active = false; working = false; access.retireOperations()
        rawDefinitions = []; rawOverview = nil; clearBoard(); rawPrivacy = nil; rawReceipt = nil; pending = nil; issues = [:]
        // Persistent original command intentionally survives logout/revocation/scene retirement.
    }
    private func clearHistory() { rawRecent = .init(); rawBest = nil }
    private func clearBoardProjections() { rawTop = .init(); rawDetail = .init(); clearHistory(); rawMeter = nil }
    private func clearBoard() { clearBoardProjections(); selectedBoard = nil; selectedQuery = nil }
    private func valid(_ stamp: UInt64) -> Bool { isCurrent && generation == stamp && !Task.isCancelled }
    private func begin() -> UInt64? { guard isCurrent, !working else { return nil }; working = true; return generation }
    private func end(_ stamp: UInt64) { if generation == stamp { working = false }; if access.authority != captured { authorityRetired = true; invalidate() } }
    private func note(_ error: Error, part: String) {
        if case NativeChannelProgressError.closed = error { invalidate(); return }
        if case NativeChannelProgressError.server(let status, let code) = error {
            if status == 401 || status == 403 { invalidate(); return }
            issues[part] = code ?? "unconfirmed"
        } else if !(error is CancellationError) { issues[part] = "unconfirmed" }
    }
    public func loadDirectory() async {
        guard let stamp = begin() else { return }; defer { end(stamp) }
        rawDefinitions = []; rawOverview = nil; clearBoard(); issues = [:]
        do { let result = try await access.definitions(); guard valid(stamp) else { return }; rawDefinitions = result.list ?? [] }
        catch { guard valid(stamp) else { return }; note(error, part: "definitions") }
        guard valid(stamp) else { return }
        do { let result = try await access.overview(); guard valid(stamp) else { return }; rawOverview = result }
        catch { guard valid(stamp) else { return }; note(error, part: "overview") }
    }
    public func select(_ board: NativeChannelProgressBoard, query: NativeChannelProgressQuery) async {
        guard rawDefinitions.contains(board), board.boardKey == query.boardKey, let stamp = begin() else { return }; defer { end(stamp) }
        clearBoard(); selectedBoard = board; selectedQuery = query
        await readBoard(board, query: query, stamp: stamp)
    }
    private func readBoard(_ board: NativeChannelProgressBoard, query: NativeChannelProgressQuery, stamp: UInt64) async {
        issues = issues.filter { !["top","detail","best","recent","meter"].contains($0.key) }
        do { let value = try await access.page(query, detail: false, cursor: nil); guard valid(stamp) else { return }; try rawTop.replace(value, query: query, detail: false) }
        catch { guard valid(stamp) else { return }; note(error, part: "top") }
        guard valid(stamp) else { return }
        do { let value = try await access.page(query, detail: true, cursor: nil); guard valid(stamp) else { return }; try rawDetail.replace(value, query: query, detail: true) }
        catch { guard valid(stamp) else { return }; note(error, part: "detail") }
        guard valid(stamp) else { return }
        await readOwnHistory(query, stamp: stamp)
        guard valid(stamp) else { return }
        do { let value = try await access.meter(board); guard valid(stamp) else { return }; rawMeter = value }
        catch { guard valid(stamp) else { return }; note(error, part: "meter") }
    }
    /// History revisions have their own current board/privacy/authority/limit binding.
    /// Equal top versions or equal metric values never establish that history is current.
    private func readOwnHistory(_ query: NativeChannelProgressQuery, stamp: UInt64) async {
        clearHistory(); issues["best"] = nil; issues["recent"] = nil
        do { let value = try await access.best(query); guard valid(stamp) else { return }; rawBest = value }
        catch { guard valid(stamp) else { return }; note(error, part: "best") }
        guard valid(stamp) else { return }
        do { let value = try await access.recent(query, cursor: nil); guard valid(stamp) else { return }; try rawRecent.replace(value, query: query, detail: false) }
        catch { guard valid(stamp) else { return }; note(error, part: "recent") }
    }
    public func refreshOwnHistory() async {
        guard let query = selectedQuery, let stamp = begin() else { return }; defer { end(stamp) }
        await readOwnHistory(query, stamp: stamp)
    }
    public func loadMore(detail: Bool = false, history: Bool = false) async {
        guard let board = selectedBoard, let query = selectedQuery, let cursor = (history ? rawRecent : (detail ? rawDetail : rawTop)).page?.nextCursor,
              let stamp = begin() else { return }; defer { end(stamp) }
        let part = history ? "recent" : (detail ? "detail" : "top")
        do {
            let page = try await (history ? access.recent(query, cursor: cursor) : access.page(query, detail: detail, cursor: cursor))
            guard valid(stamp), selectedQuery == query else { return }
            if history { try rawRecent.append(page, query: query, detail: false, requestedCursor: cursor) }
            else if detail { try rawDetail.append(page, query: query, detail: true, requestedCursor: cursor) }
            else { try rawTop.append(page, query: query, detail: false, requestedCursor: cursor) }
            issues[part] = nil
        } catch {
            guard valid(stamp) else { return }
            if let failure = error as? NativeChannelProgressError, failure.staleCursor {
                clearBoard(); selectedBoard = board; selectedQuery = query
                await readBoard(board, query: query, stamp: stamp)
            } else {
                if history { clearHistory() }
                note(error, part: part)
            }
        }
    }
    public func checkVersion() async {
        guard let board = selectedBoard, let query = selectedQuery, let stamp = begin() else { return }; defer { end(stamp) }
        // The top probe is not a history probe. Withhold old history while checking.
        clearHistory()
        do {
            let version = try await access.version(board.boardKey); guard valid(stamp) else { return }
            // /version probes the definition's default period, not an overridden query period.
            let sameRevision = rawTop.page.map { version.revision.utf8.elementsEqual($0.revision.utf8) } == true
            if query.period != board.period || !sameRevision || version.visible != rawTop.page?.visible {
                clearBoard(); selectedBoard = board; selectedQuery = query; await readBoard(board, query: query, stamp: stamp)
            } else { await readOwnHistory(query, stamp: stamp) }
        } catch { guard valid(stamp) else { return }; clearBoardProjections(); note(error, part: "top") }
    }
    public func loadPrivacy() async {
        guard let stamp = begin() else { return }; defer { end(stamp) }
        rawPrivacy = nil; issues["privacy"] = nil
        do { pending = try journal.restore() }
        catch { privacyState = .persistenceFailed; return }
        do {
            if pending != nil { await recover(stamp: stamp, retryOriginal: false, knownConflict: false) }
            else { privacyState = .idle }
            guard valid(stamp) else { return }
            let value = try await access.privacy(); guard valid(stamp) else { return }; rawPrivacy = value
        } catch { guard valid(stamp) else { return }; note(error, part: "privacy") }
    }
    public func savePrivacy(_ values: NativeChannelProgressPrivacyValues) async {
        guard canSavePrivacy, let current = rawPrivacy, let stamp = begin() else { return }; defer { end(stamp) }
        do {
            let command = try NativeChannelProgressPrivacyCommand(values: values, revision: current.revision, updatedAt: nil, requestID: UUID().uuidString)
            try journal.saveBeforeDispatch(command); pending = command; rawReceipt = nil; privacyState = .saving; clearBoard()
            await dispatch(command, stamp: stamp)
        } catch { guard valid(stamp) else { return }; privacyState = .persistenceFailed; note(error, part: "privacy") }
    }
    private func dispatch(_ command: NativeChannelProgressPrivacyCommand, stamp: UInt64) async {
        let value: NativeChannelProgressPrivacy
        do { value = try await access.save(command); guard valid(stamp) else { return } }
        catch {
            guard valid(stamp) else { return }
            if case NativeChannelProgressError.closed = error { invalidate(); return }
            if case NativeChannelProgressError.server(let status, _) = error, status == 401 || status == 403 { invalidate(); return }
            let conflict: Bool
            if case NativeChannelProgressError.server(409, "PRIVACY_CONFLICT") = error { conflict = true } else { conflict = false }
            await recover(stamp: stamp, retryOriginal: false, knownConflict: conflict)
            return
        }
        do { try await applied(value, command: command, stamp: stamp) }
        catch {
            guard valid(stamp) else { return }
            privacyState = pending == nil ? .applied : .persistenceFailed
            note(error, part: "privacy")
        }
    }
    public func recoverOriginal(retryOriginal: Bool = false) async {
        guard let stamp = begin() else { return }; defer { end(stamp) }
        do { pending = try journal.restore(); guard pending != nil else { return }; await recover(stamp: stamp, retryOriginal: retryOriginal, knownConflict: false) }
        catch { guard valid(stamp) else { return }; privacyState = .persistenceFailed }
    }
    private func recover(stamp: UInt64, retryOriginal: Bool, knownConflict: Bool) async {
        guard let command = pending else { return }; privacyState = .checkingReceipt
        do {
            let value = try await access.receipt(command); guard valid(stamp) else { return }
            if let value { try await applied(value, command: command, stamp: stamp) }
            else if knownConflict {
                try journal.settle(command); pending = nil; privacyState = .conflict; rawPrivacy = nil
                let current = try await access.privacy(); guard valid(stamp) else { return }; rawPrivacy = current
            } else if retryOriginal {
                privacyState = .saving; await dispatch(command, stamp: stamp)
            } else { privacyState = .unresolved }
        } catch {
            guard valid(stamp) else { return }
            if rawReceipt?.requestId == command.requestId { privacyState = pending == nil ? .applied : .persistenceFailed }
            else { privacyState = .unresolved }
            note(error, part: "privacy")
        }
    }
    private func applied(_ value: NativeChannelProgressPrivacy, command: NativeChannelProgressPrivacyCommand, stamp: UInt64) async throws {
        guard command.matches(value) else { throw NativeChannelProgressError.malformed }
        rawReceipt = value; rawPrivacy = nil
        do { try journal.settle(command) } catch { privacyState = .persistenceFailed; throw error }
        pending = nil; privacyState = .applied; rawPrivacy = nil
        let current = try await access.privacy(); guard valid(stamp) else { return }; rawPrivacy = current
    }
}
