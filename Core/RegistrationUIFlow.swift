import Foundation

/// Identity of an opened form read, separate from the current external session. This
/// changes only after open() has installed the new session and exact ticket scope.
public struct RegistrationWaitlistReadKey: Hashable {
    let identity: ProfileReadIdentity
    let scope: RegistrationWaitlistScope
}

public enum RegistrationUIParticipantsState: Equatable { case idle, loading, received, unavailable }
public enum RegistrationUIBlock: Equatable {
    case sessionChanged, quotingDisabled, creationDisabled, invalidForm, missingConsent
    case soldOut, quoteUnavailable, confirmationChanged, intentAlreadySubmitted, waitlistUnavailable
}

/// Immutable review snapshot. This is local UI confirmation, not legal consent evidence.
public struct RegistrationUIConfirmation: Equatable {
    public let identity: ProfileReadIdentity
    public let selection: RegistrationQuoteRequest
    public let quote: RegistrationQuote
    public let draft: RegistrationUIFormDraft
}

/// Testable presentation controller. The host owns the coordinator and synchronizes its
/// account on every session epoch change. Keep that coordinator alive across dismissals.
/// No credential, production configuration, logging, persistence or payment SDK lives here.
@MainActor
public final class RegistrationUIFlow {
    public let activity: ActivityDetail
    public let coordinator: RegistrationCoordinator
    public let quoteEnabled: Bool
    public let creationPolicy: RegistrationUICreationPolicy
    public var onChange: (() -> Void)?
    public private(set) var draft = RegistrationUIFormDraft()
    public private(set) var participants: [ProfileParticipant] = []
    public private(set) var participantsState: RegistrationUIParticipantsState = .idle
    public private(set) var selectedParticipantID: Int?
    public private(set) var selectedTicketID: Int?
    public private(set) var usePoints = false
    public private(set) var consented = false
    public private(set) var confirmation: RegistrationUIConfirmation?
    public private(set) var block: RegistrationUIBlock?
    public private(set) var isQuoting = false
    public private(set) var isSubmitting = false
    public private(set) var isReadingStatus = false
    public private(set) var waitlistStatus: RegistrationWaitlistStatus?
    public private(set) var isRecordingConsent = false
    public private(set) var isReadingWaitlist = false
    public private(set) var isMutatingWaitlist = false
    public private(set) var waitlistOutcomeUnknown = false
    public private(set) var durableCreation: RegistrationDurableCreation = .none
    public private(set) var durableStatus: RegistrationStatusSnapshot?
    public private(set) var activeWaitlistOffer: RegistrationWaitlistOffer?
    private let waitlistService: (any RegistrationWaitlistServing)?
    private let now: () -> Date
    private var quoteReceivedAt: Date?
    private var waitlistGeneration: UInt64 = 0
    private let participantReader: (any ProfileReading)?
    private let currentIdentity: () -> ProfileReadIdentity?
    private let onReadback: (RegistrationStatusSnapshot) -> Void
    private var openedIdentity: ProfileReadIdentity?
    private var generation: UInt64 = 0
    private var quoteGeneration: UInt64 = 0
    private var participantGeneration: UInt64 = 0
    private var manuallyEdited = false

    public init(activity: ActivityDetail, coordinator: RegistrationCoordinator,
                participantReader: (any ProfileReading)? = nil,
                currentIdentity: @escaping () -> ProfileReadIdentity?, quoteEnabled: Bool = false,
                creationPolicy: RegistrationUICreationPolicy = .disabled,
                waitlistService: (any RegistrationWaitlistServing)? = nil, now: @escaping () -> Date = Date.init,
                onReadback: @escaping (RegistrationStatusSnapshot) -> Void = { _ in }) {
        self.activity = activity; self.coordinator = coordinator
        self.waitlistService = waitlistService; self.now = now
        self.participantReader = participantReader; self.currentIdentity = currentIdentity
        self.quoteEnabled = quoteEnabled; self.creationPolicy = creationPolicy; self.onReadback = onReadback
    }
    public var identity: ProfileReadIdentity? { currentIdentity() }
    public var hasCurrentSession: Bool {
        guard let openedIdentity else { return false }
        return currentIdentity() == openedIdentity && coordinator.accountID == openedIdentity.accountID
    }
    public var hasRetainedIntent: Bool { hasCurrentSession && coordinator.retainedIntent != nil }
    public var retainedForAnotherActivity: Bool {
        hasRetainedIntent && coordinator.retainedIntent?.selection.ownerID != activity.summary.id
    }
    public var canEdit: Bool { hasCurrentSession && !hasRetainedIntent && !isSubmitting && !isMutatingWaitlist && !isRecordingConsent && durableCreation == .none }
    public var selectedTicket: ActivityTicket? { activity.tickets.first { $0.id == selectedTicketID } }
    public var quoteState: RegistrationQuoteState {
        hasCurrentSession && coordinator.selection == expectedSelection ? coordinator.quoteState : .idle
    }
    public var creationState: RegistrationCreationState { hasCurrentSession ? coordinator.creationState : .idle }
    public var readbackState: RegistrationReadbackState { hasCurrentSession ? coordinator.readbackState : .idle }
    public var canReadStatus: Bool {
        guard hasCurrentSession, !isReadingStatus else { return false }
        if case .responseReceived = creationState { return true }
        return false
    }
    public var confirmationBlock: RegistrationUIBlock? {
        if !hasCurrentSession { return .sessionChanged }
        if hasRetainedIntent || durableCreation != .none { return .intentAlreadySubmitted }
        if !creationPolicy.permits(identity: openedIdentity, activityID: activity.summary.id, ticketID: selectedTicketID, now: now()) { return .creationDisabled }
        if isRecordingConsent { return .missingConsent }
        if isReadingWaitlist || isMutatingWaitlist || waitlistOutcomeUnknown { return .waitlistUnavailable }
        if activeWaitlistOffer != nil && !hasActiveWaitlistOffer { return .soldOut }
        if selectedTicket?.isSoldOut == true && !hasActiveWaitlistOffer { return .soldOut }
        if case .approved = creationPolicy, quoteReceivedAt.map({ now().timeIntervalSince($0) >= 0 && now().timeIntervalSince($0) < 120 }) != true { return .quoteUnavailable }
        if draft.validation != nil { return .invalidForm }
        if !consented { return .missingConsent }
        if isQuoting || !coordinator.canConfirm { return .quoteUnavailable }
        return nil
    }

    /// Called when the sheet opens or the host's session identity changes. No requests.
    public func open() {
        generation &+= 1; quoteGeneration &+= 1; participantGeneration &+= 1
        clearForm()
        openedIdentity = currentIdentity()
        guard hasCurrentSession else { block = .sessionChanged; changed(); return }
        if let intent = coordinator.retainedIntent {
            selectedTicketID = intent.selection.ticketID; usePoints = intent.selection.usePoints
        } else {
            selectedTicketID = activity.tickets.first?.id; usePoints = false
            applySelection()
        }
        refreshCreationLock()
        changed()
    }
    public func setName(_ value: String) {
        guard canEdit else { return }
        draft.realName = value; manuallyEdited = true; invalidateConfirmation(); changed()
    }
    public func setPhone(_ value: String) {
        guard canEdit else { return }
        draft.phone = value; manuallyEdited = true; invalidateConfirmation(); changed()
    }
    public func selectParticipant(id: Int) {
        guard canEdit, let participant = participants.first(where: { $0.id == id }) else { return }
        applyParticipant(participant); manuallyEdited = true; invalidateConfirmation(); changed()
    }
    /// Only an acknowledged create receipt supplies the new ID. Re-read that owned row;
    /// stale accounts, cancellation and malformed/mismatched readbacks never select it.
    public func selectCreatedParticipant(_ receipt: ProfileParticipant, identity: ProfileReadIdentity) async {
        guard canEdit, identity == openedIdentity, let participantReader,
              participantReader.identity == identity, receipt.id > 0 else { return }
        participantGeneration &+= 1
        let stamp = generation, participantStamp = participantGeneration
        do {
            let row = try await participantReader.profileParticipant(id: receipt.id)
            guard matches(stamp, identity), participantStamp == participantGeneration, canEdit, !Task.isCancelled,
                  participantReader.identity == identity, row.id == receipt.id,
                  row.fullName == receipt.fullName, row.mobilePhone == receipt.mobilePhone else { return }
            participants.removeAll { $0.id == row.id }; participants.append(row); participantsState = .received
            applyParticipant(row); manuallyEdited = true; invalidateConfirmation(); changed()
        } catch { if matches(stamp, identity), participantStamp == participantGeneration { participantsState = .unavailable; changed() } }
    }
    public func useManualEntry() {
        guard canEdit else { return }
        selectedParticipantID = nil; manuallyEdited = true; invalidateConfirmation(); changed()
    }
    @discardableResult public func selectTicket(id: Int?) -> Bool {
        guard canEdit, (id == nil ? activity.tickets.isEmpty : activity.tickets.contains(where: { $0.id == id })) else { return false }
        guard selectedTicketID != id else { return false }
        selectedTicketID = id; resetWaitlist(); refreshCreationLock(); applySelection(); changed(); return true
    }
    @discardableResult public func setUsePoints(_ value: Bool) -> Bool {
        guard canEdit, value != usePoints else { return false }
        usePoints = value; applySelection(); changed(); return true
    }
    public func setConsent(_ value: Bool) {
        guard canEdit, creationPolicy.permitsCreation else { return }
        consented = value; invalidateConfirmation(); changed()
    }
    public func loadParticipants() async {
        guard hasCurrentSession, !hasRetainedIntent, let participantReader,
              participantReader.isConfigured, participantReader.identity == openedIdentity else { return }
        participantGeneration &+= 1
        let stamp = generation, participantStamp = participantGeneration
        let identity = openedIdentity
        participantsState = .loading; changed()
        do {
            let rows = try await participantReader.profileParticipants()
            guard matches(stamp, identity), participantStamp == participantGeneration,
                  participantReader.identity == identity, !Task.isCancelled else { return }
            participants = rows; participantsState = .received
            if canEdit, !manuallyEdited, selectedParticipantID == nil,
               draft.realName.isEmpty, draft.phone.isEmpty,
               let preferred = rows.first(where: \.isDefault) ?? rows.first {
                applyParticipant(preferred)
            }
        } catch {
            guard matches(stamp, identity), participantStamp == participantGeneration, !Task.isCancelled else { return }
            participants = []; participantsState = .unavailable
        }
        changed()
    }
    public func requestQuote() async {
        guard canEdit else { block = .sessionChanged; changed(); return }
        guard quoteEnabled else { block = .quotingDisabled; changed(); return }
        quoteGeneration &+= 1
        let stamp = generation, quoteStamp = quoteGeneration, identity = openedIdentity
        isQuoting = true; invalidateConfirmation(); changed()
        _ = await coordinator.requestQuote()
        guard matches(stamp, identity), quoteStamp == quoteGeneration else { return }
        isQuoting = false
        if case .received = coordinator.quoteState { quoteReceivedAt = now() }
        changed()
    }
    @discardableResult public func prepareConfirmation() -> Bool {
        if let reason = confirmationBlock { block = reason; changed(); return false }
        guard let identity = openedIdentity, let selection = coordinator.selection,
              selection == expectedSelection, case .received(let quote) = coordinator.quoteState else {
            block = .quoteUnavailable; changed(); return false
        }
        confirmation = .init(identity: identity, selection: selection, quote: quote, draft: draft)
        block = nil; changed(); return true
    }
    public func cancelConfirmation() { confirmation = nil; changed() }
    public func confirm() async {
        guard let review = confirmation else { block = .confirmationChanged; changed(); return }
        guard confirmationBlock == nil, review.identity == openedIdentity,
              review.selection == coordinator.selection, review.selection == expectedSelection,
              review.draft == draft, case .received(let quote) = coordinator.quoteState,
              review.quote == quote else {
            confirmation = nil; block = confirmationBlock ?? .confirmationChanged; changed(); return
        }
        // Final check repeats the compile-time creation gate immediately before dispatch.
        guard creationPolicy.permitsCreation else { block = .creationDisabled; changed(); return }
        let stamp = generation, identity = openedIdentity
        confirmation = nil; isSubmitting = true; changed()
        _ = await coordinator.confirm(review.draft.details(waitlistOffer: review.selection.waitlistOffer))
        guard matches(stamp, identity) else { return }
        isSubmitting = false; changed()
    }
    public func readKnownStatus() async {
        guard canReadStatus else { return }
        let stamp = generation, identity = openedIdentity
        isReadingStatus = true; changed()
        let action = await coordinator.readKnownStatus()
        guard matches(stamp, identity) else { return }
        isReadingStatus = false; changed()
        if action == .applied, case .received(let snapshot) = coordinator.readbackState { onReadback(snapshot) }
    }
    /// Dismissal invalidates callbacks and scrubs form fields. It never resets/recreates
    /// the host's retained intent, sends cancellation, or claims a dispatched write failed.
    public func leave() {
        if hasCurrentSession { coordinator.cancelPendingOperations() }
        generation &+= 1; quoteGeneration &+= 1; participantGeneration &+= 1
        clearForm(); openedIdentity = nil; changed()
    }
    private func refreshCreationLock() {
        durableStatus = nil
        guard case .approved = creationPolicy, let service = waitlistService as? any RegistrationPendingServing, let scope = waitlistScope else { durableCreation = .none; return }
        do { durableCreation = try service.creationLock(scope) }
        catch { durableCreation = .pending(registrationID: nil) }
    }
    public func readDurableStatus() async {
        guard hasCurrentSession, !isReadingStatus, case .pending(let id) = durableCreation, id != nil,
              let scope = waitlistScope, let service = waitlistService as? any RegistrationPendingServing else { return }
        let stamp = generation, identity = openedIdentity
        isReadingStatus = true; changed()
        do {
            let snapshot = try await service.readRetainedStatus(scope)
            guard matches(stamp, identity), waitlistScope == scope, !Task.isCancelled else { return }
            guard snapshot.registrationID == id else { throw APIError.malformedResponse }
            durableStatus = snapshot; onReadback(snapshot)
        } catch { guard matches(stamp, identity) else { return }; block = .quoteUnavailable }
        isReadingStatus = false; changed()
    }
    public var waitlistReadKey: RegistrationWaitlistReadKey? {
        guard hasCurrentSession, let openedIdentity, let scope = waitlistScope else { return nil }
        return .init(identity: openedIdentity, scope: scope)
    }
    public var waitlistAvailable: Bool { waitlistService != nil && selectedTicketID != nil }
    public var hasActiveWaitlistOffer: Bool {
        guard let activeWaitlistOffer, let waitlistStatus, let scope = waitlistScope else { return false }
        return waitlistStatus.offer(at: now()) == activeWaitlistOffer && waitlistStatus.matches(scope, accountID: openedIdentity?.accountID ?? 0)
    }
    public var canJoinWaitlist: Bool { canEdit && !isReadingWaitlist && !waitlistOutcomeUnknown && waitlistStatus?.canJoin == true && selectedTicket?.isSoldOut == true }
    public var canCancelWaitlist: Bool { canEdit && !isReadingWaitlist && !waitlistOutcomeUnknown && waitlistStatus?.canCancel == true }
    private var waitlistScope: RegistrationWaitlistScope? {
        guard let selectedTicketID else { return nil }
        return try? .init(activityID: activity.summary.id, ticketID: selectedTicketID)
    }
    /// A fresh authoritative read stays in the existing form; never auto-claims or pays.
    public func loadWaitlist() async {
        guard canEdit, !isReadingWaitlist, let scope = waitlistScope, let waitlistService else { return }
        waitlistGeneration &+= 1
        let stamp = generation, waitlistStamp = waitlistGeneration, identity = openedIdentity
        isReadingWaitlist = true; invalidateConfirmation(); changed()
        defer {
            // Cancellation may be ignored by the transport. Finish only this read's
            // presentation state, including canceled success, never a newer read's spinner.
            if matches(stamp, identity), waitlistStamp == waitlistGeneration, waitlistScope == scope {
                isReadingWaitlist = false; changed()
            }
        }
        do {
            let result = try await waitlistService.status(scope)
            guard matches(stamp, identity), waitlistStamp == waitlistGeneration, waitlistScope == scope, !Task.isCancelled else { return }
            guard result.matches(scope, accountID: identity?.accountID ?? 0) else { throw APIError.malformedResponse }
            waitlistStatus = result; waitlistOutcomeUnknown = false
            if let activeWaitlistOffer, result.offer(at: now()) != activeWaitlistOffer {
                self.activeWaitlistOffer = nil; consented = false; applySelection()
            }
        } catch {
            guard matches(stamp, identity), waitlistStamp == waitlistGeneration,
                  waitlistScope == scope, !Task.isCancelled else { return }
            waitlistStatus = nil; activeWaitlistOffer = nil; consented = false; applySelection()
            if error is RegistrationPendingFailure { waitlistOutcomeUnknown = true }
            block = .waitlistUnavailable
        }
    }
    public func recordSignupConsent() async {
        guard canEdit, consented, case .approved = creationPolicy,
              let scope = waitlistScope, let service = waitlistService as? any RegistrationLegalServing else { return }
        let stamp = generation, identity = openedIdentity
        isRecordingConsent = true; invalidateConfirmation(); changed()
        do {
            try await service.agreeToSignupNotice(scope)
            guard matches(stamp, identity), waitlistScope == scope, !Task.isCancelled else { return }
            isRecordingConsent = false; changed()
            await requestQuote()
        } catch {
            guard matches(stamp, identity) else { return }
            isRecordingConsent = false; block = .missingConsent; changed()
        }
    }
    public func joinWaitlist() async { guard canJoinWaitlist else { return }; await mutateWaitlist(join: true) }
    public func cancelWaitlist() async { guard canCancelWaitlist else { return }; await mutateWaitlist(join: false) }
    private func mutateWaitlist(join: Bool) async {
        guard let scope = waitlistScope, let waitlistService else { return }
        let stamp = generation, identity = openedIdentity
        isMutatingWaitlist = true; activeWaitlistOffer = nil; consented = false; applySelection(); changed()
        do {
            let result: RegistrationWaitlistStatus
            if join { result = try await waitlistService.join(scope) }
            else { result = try await waitlistService.cancel(scope) }
            guard matches(stamp, identity), waitlistScope == scope, !Task.isCancelled else { return }
            guard result.matches(scope, accountID: identity?.accountID ?? 0) else { throw APIError.malformedResponse }
            waitlistStatus = result; waitlistOutcomeUnknown = false
        } catch {
            guard matches(stamp, identity) else { return }
            waitlistStatus = nil; waitlistOutcomeUnknown = true; block = .waitlistUnavailable
        }
        guard matches(stamp, identity) else { return }
        isMutatingWaitlist = false; changed()
    }
    public func reviewWaitlistOffer() async {
        guard canEdit, !isReadingWaitlist else { return }
        let scope = waitlistScope, identity = openedIdentity, stamp = generation
        await loadWaitlist()
        guard matches(stamp, identity), waitlistScope == scope, canEdit, !waitlistOutcomeUnknown, let offer = waitlistStatus?.offer(at: now()) else { return }
        activeWaitlistOffer = offer; consented = false; applySelection(); changed()
        await requestQuote()
    }
    /// Local countdown expiry only removes capability; only the backend releases inventory.
    public func checkWaitlistDeadline() {
        if activeWaitlistOffer != nil && !hasActiveWaitlistOffer {
            activeWaitlistOffer = nil; consented = false; applySelection(); changed()
        }
    }
    private func resetWaitlist() {
        waitlistGeneration &+= 1; waitlistStatus = nil; activeWaitlistOffer = nil; consented = false
        waitlistOutcomeUnknown = false; isReadingWaitlist = false; isMutatingWaitlist = false; isRecordingConsent = false
    }
    private var expectedSelection: RegistrationQuoteRequest? {
        try? RegistrationQuoteRequest(ownerID: activity.summary.id, ticketID: selectedTicketID, usePoints: usePoints, waitlistOffer: activeWaitlistOffer)
    }
    private func applySelection() {
        quoteGeneration &+= 1; isQuoting = false; quoteReceivedAt = nil; invalidateConfirmation()
        if let selection = expectedSelection { _ = coordinator.select(selection) }
    }
    private func applyParticipant(_ participant: ProfileParticipant) {
        selectedParticipantID = participant.id
        draft = .init(realName: participant.fullName, phone: participant.mobilePhone)
    }
    private func matches(_ stamp: UInt64, _ identity: ProfileReadIdentity?) -> Bool {
        generation == stamp && openedIdentity == identity && hasCurrentSession
    }
    private func invalidateConfirmation() { confirmation = nil; block = nil }
    private func clearForm() {
        resetWaitlist(); quoteReceivedAt = nil; durableCreation = .none; durableStatus = nil
        draft = .init(); participants = []; participantsState = .idle; selectedParticipantID = nil
        selectedTicketID = nil; usePoints = false; consented = false; confirmation = nil; block = nil
        manuallyEdited = false; isQuoting = false; isSubmitting = false; isReadingStatus = false
    }
    private func changed() { onChange?() }
}
