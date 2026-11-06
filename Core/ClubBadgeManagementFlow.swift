import Foundation

/// Current interaction results never inherit a previous successful request's receipt.
public enum ClubBadgeResultPresentation: Equatable {
    case none, storageUnavailable, unknown, needsReview, notSent
    case confirmed(ClubBadgeOriginalReceipt)
    case historical(ClubBadgeOriginalReceipt)
}

public struct ClubBadgeGrantReview: Equatable, Identifiable {
    public let id: UUID
    public let badge: ClubBadgeRecord
    public let member: ClubMember
    fileprivate let generation: UInt64
    public var memberName: String { member.trimmedNickname ?? "成员\(member.memberId)" }
}

/// One normal list → owner create → member selection → second confirmation → original receipt.
/// Server ownership is refreshed before each mutation; admin/paid-member status never substitutes.
@MainActor public final class ClubBadgeManagementFlow {
    public let clubID: Int
    private let service: ClubBadgeManagementService
    private let journal: ClubBadgeManagementJournal
    private var generation: UInt64 = 0
    private var active = false
    private var selectedBadge: ClubBadgeRecord?
    private var entries: [ClubBadgeManagementEntry] = []
    public private(set) var club: ClubRecord?
    public private(set) var badges: [ClubBadgeRecord] = []
    public private(set) var members: [ClubMember] = []
    public private(set) var review: ClubBadgeGrantReview?
    public private(set) var loaded = false
    public private(set) var busy = false
    public private(set) var pickerOpen = false
    public private(set) var error: String?
    public private(set) var refreshError: String?
    public private(set) var memberError: String?
    public private(set) var operationMessage: String?
    public private(set) var receipt: ClubBadgeOriginalReceipt?
    private var currentOperationResult: ClubBadgeResultPresentation?
    public var resultPresentation: ClubBadgeResultPresentation {
        guard active && service.isCurrent else { return .none }
        guard journalAvailable else { return .storageUnavailable }
        guard unresolved.isEmpty else { return .unknown }
        if let currentOperationResult { return currentOperationResult }
        if let receipt { return .historical(receipt) }
        return .none
    }
    public private(set) var journalAvailable = false
    public var isOwner: Bool { active && service.isCurrent && club?.isOwner == true }
    public var isConfigured: Bool { service.canRead }
    public var isCurrent: Bool { service.isCurrent }
    public var unresolved: [ClubBadgeManagementEntry] { active && service.isCurrent ? entries.filter { $0.outcome == "UNKNOWN" } : [] }
    public var canCreate: Bool { isOwner && service.canWrite && journalAvailable && unresolved.isEmpty && !busy }
    public var canGrant: Bool { canCreate && loaded }
    public var selectedBadgeName: String? { selectedBadge?.displayName }
    public init(service: ClubBadgeManagementService, journal: ClubBadgeManagementJournal) {
        self.service = service; self.journal = journal; clubID = service.clubID
    }
    public func invalidate() {
        generation &+= 1; active = false; busy = false; club = nil; badges = []; members = []
        selectedBadge = nil; review = nil; pickerOpen = false; entries = []; receipt = nil; currentOperationResult = nil
        loaded = false; error = nil; refreshError = nil; memberError = nil; operationMessage = nil; journalAvailable = false
        // A dispatched UNKNOWN is deliberately not erased on page exit/logout/account switch.
    }
    private func current(_ ticket: UInt64) -> Bool { active && service.isCurrent && generation == ticket && !Task.isCancelled }
    private func message(_ error: Error) -> String { (error as? ClubBadgeManagementFailure)?.message ?? "读取失败，请检查网络后重试。" }
    private func clearManagement() { selectedBadge = nil; members = []; review = nil; pickerOpen = false; memberError = nil }
    private func readJournal() {
        do {
            entries = try journal.read(service.context, clubID: clubID); journalAvailable = true
            receipt = entries.last(where: { $0.outcome == "CONFIRMED" })?.receipt
        } catch { journalAvailable = false; operationMessage = ClubBadgeManagementFailure.persistence.message }
    }
    public func refresh() async {
        guard !busy else { return }
        active = true; generation &+= 1; let ticket = generation
        busy = true; error = nil; refreshError = nil; operationMessage = nil; currentOperationResult = nil; clearManagement(); club = nil
        defer { if current(ticket) { busy = false } }
        guard service.canRead else { error = ClubBadgeManagementFailure.unavailable.message; return }
        readJournal()
        do {
            let detail = try await service.detail()
            guard current(ticket) else { return }; club = detail
        } catch {
            guard current(ticket) else { return }; club = nil; clearManagement(); refreshError = message(error)
        }
        do {
            let values = try await service.badges()
            guard current(ticket) else { return }; badges = values; loaded = true
        } catch {
            guard current(ticket) else { return }
            if loaded { refreshError = message(error) } else { self.error = message(error) }
        }
        guard current(ticket) else { return }
        // Read only the current account's exact immutable original-request facts. List contents,
        // same-name new badges or an absent row can NEVER settle an UNKNOWN.
        if journalAvailable {
            for entry in entries where entry.outcome == "UNKNOWN" {
                do {
                    let value = try await service.receipt(entry)
                    guard current(ticket) else { return }
                    if value.isTerminal {
                        try journal.settle(entry, outcome: "CONFIRMED", receipt: value, context: service.context)
                        receipt = value; operationMessage = value.message; currentOperationResult = .confirmed(value)
                    } else { operationMessage = ClubBadgeManagementFailure.unknown.message }
                } catch {
                    guard current(ticket) else { return }; operationMessage = message(error); currentOperationResult = .needsReview
                }
            }
            readJournal()
        }
        showCreationVisibility()
    }
    private func showCreationVisibility() {
        if let receipt, receipt.state == "CREATED", let code = receipt.badgeCode,
           loaded, !badges.contains(where: { $0.badgeCode == code }) {
            let note = "原操作已确认创建，但上次读取的列表暂未包含这枚勋章；可刷新列表。"
            refreshError = refreshError.map { $0 + "\n" + note } ?? note
        }
    }
    public func create(_ draft: ClubBadgeCreateDraft) async {
        guard canCreate else { return }
        currentOperationResult = nil
        if let validation = draft.validation { operationMessage = validation; currentOperationResult = .needsReview; return }
        let ticket = generation; busy = true; operationMessage = nil; currentOperationResult = nil
        defer { if current(ticket) { busy = false } }
        do {
            let fields = try draft.fields(clubID: clubID)
            let detail = try await service.detail()
            guard current(ticket) else { return }; club = detail
            guard detail.isOwner else { clearManagement(); throw ClubBadgeManagementFailure.forbidden }
            let entry = try ClubBadgeManagementEntry(context: service.context, clubID: clubID, operation: "CREATE", fields: fields)
            try await dispatch(entry, fields: fields, ticket: ticket)
            guard current(ticket) else { return }
            if receipt?.requestId == entry.requestID {
                do { let values = try await service.badges(); guard current(ticket) else { return }; badges = values; loaded = true }
                catch { guard current(ticket) else { return }; refreshError = message(error) }
                showCreationVisibility()
            }
        } catch { if current(ticket) { operationMessage = message(error); currentOperationResult = .needsReview } }
    }
    public func openGrant(_ badge: ClubBadgeRecord) async {
        guard canGrant, badges.contains(badge) else { return }
        let ticket = generation; busy = true; memberError = nil; review = nil; members = []
        selectedBadge = badge; pickerOpen = true
        defer { if current(ticket) { busy = false } }
        do {
            let detail = try await service.detail()
            guard current(ticket) else { return }; club = detail
            guard detail.isOwner else { clearManagement(); throw ClubBadgeManagementFailure.forbidden }
            let values = try await service.badges()
            guard current(ticket) else { return }; badges = values
            guard let actual = values.first(where: { $0.badgeCode == badge.badgeCode }) else { throw ClubBadgeManagementFailure.invalid }
            selectedBadge = actual
            let roster = try await service.members()
            guard current(ticket) else { return }; members = roster
        } catch {
            if current(ticket) { memberError = message(error); if !isOwner { clearManagement(); operationMessage = message(error) } }
        }
    }
    public func retryMembers() async {
        guard let badge = selectedBadge, pickerOpen else { return }
        await openGrant(badge)
    }
    public func closePicker() { guard !busy else { return }; clearManagement() }
    public func selectMember(_ member: ClubMember) {
        guard canGrant, pickerOpen, let badge = selectedBadge, members.contains(member) else { return }
        review = ClubBadgeGrantReview(id: UUID(), badge: badge, member: member, generation: generation)
    }
    public func cancelReview() { guard !busy else { return }; review = nil }
    public func confirmGrant(_ confirmation: ClubBadgeGrantReview) async {
        guard canGrant, review == confirmation, confirmation.generation == generation else { return }
        let ticket = generation; busy = true; operationMessage = nil; currentOperationResult = nil
        defer { if current(ticket) { busy = false } }
        do {
            let detail = try await service.detail()
            guard current(ticket), review == confirmation else { return }; club = detail
            guard detail.isOwner else { clearManagement(); throw ClubBadgeManagementFailure.forbidden }
            let values = try await service.badges()
            guard current(ticket), review == confirmation else { return }
            let roster = try await service.members()
            guard current(ticket), review == confirmation else { return }
            // The second confirmation binds exact current names and IDs. Changed targets require
            // a new user selection/confirmation; do not silently substitute another member/badge.
            guard values.contains(confirmation.badge), roster.contains(confirmation.member) else {
                clearManagement(); throw ClubBadgeManagementFailure.server("成员或勋章状态已变化，请重新选择并确认。")
            }
            badges = values; members = roster
            let fields: [String: Any] = ["clubId": clubID, "memberId": confirmation.member.memberId, "badgeCode": confirmation.badge.badgeCode]
            let entry = try ClubBadgeManagementEntry(context: service.context, clubID: clubID, operation: "GRANT", fields: fields)
            try await dispatch(entry, fields: fields, ticket: ticket)
            guard current(ticket) else { return }; clearManagement()
        } catch { if current(ticket) { review = nil; operationMessage = message(error); currentOperationResult = .needsReview } }
    }
    private func dispatch(_ entry: ClubBadgeManagementEntry, fields: [String: Any], ticket: UInt64) async throws {
        var reserved = false
        let outcome = try await service.mutate(entry, fields: fields, isCurrentView: { self.current(ticket) }, reserve: {
            do {
                try self.journal.reserve(entry, context: self.service.context); reserved = true
                self.entries = try self.journal.read(self.service.context, clubID: self.clubID)
            } catch {
                self.readJournal()
                if !self.unresolved.isEmpty { throw ClubBadgeManagementFailure.pending }
                self.journalAvailable = false; throw ClubBadgeManagementFailure.persistence
            }
        })
        // Stale/hidden callers never repaint private state. UNKNOWN already survives in storage.
        guard current(ticket) else { return }
        do {
            switch outcome {
            case .confirmed(let value):
                try journal.settle(entry, outcome: "CONFIRMED", receipt: value, context: service.context)
                receipt = value; operationMessage = value.message; currentOperationResult = .confirmed(value)
            case .rejected(let text):
                if reserved { try journal.settle(entry, outcome: "REJECTED", context: service.context) }
                operationMessage = text; currentOperationResult = .needsReview
                // A rejection may be an ownership/capability change. Revoke local management
                // until the user refreshes, preserving the exact server explanation.
                club = nil; clearManagement()
            case .notSent:
                if reserved { try journal.settle(entry, outcome: "NOT_SENT", context: service.context) }
                operationMessage = "操作未发送，请刷新当前身份后重新确认。"; currentOperationResult = .notSent
            case .unknown: operationMessage = ClubBadgeManagementFailure.unknown.message
            }
            readJournal()
        } catch { journalAvailable = false; throw ClubBadgeManagementFailure.persistence }
    }
}
