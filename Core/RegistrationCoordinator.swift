import Foundation

/// Injected boundary only: conformers perform at most one request, with no hidden retries.
/// No endpoint, credentials, payment SDK or task scheduler is created by the coordinator.
@MainActor
public protocol RegistrationCoordinatingService {
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot
}

extension RegistrationService: RegistrationCoordinatingService {}

/// Values explicitly supplied at confirmation; never logged or written to storage here.
public struct RegistrationParticipantDetails {
    public let realName: String
    public let phone: String
    public let email: String?
    public let participateDate: String?
    public let usesAppPaymentChannel: Bool
    public let waitlistOffer: RegistrationWaitlistOffer?

    public init(realName: String, phone: String, email: String? = nil,
                participateDate: String? = nil, usesAppPaymentChannel: Bool = true,
                waitlistOffer: RegistrationWaitlistOffer? = nil) {
        self.realName = realName
        self.phone = phone
        self.email = email
        self.participateDate = participateDate
        self.usesAppPaymentChannel = usesAppPaymentChannel
        self.waitlistOffer = waitlistOffer
    }
}

/// Structured diagnostics preserve server codes/messages without retaining arbitrary
/// error descriptions (which may contain a URL, credential or participant information).
public enum RegistrationCoordinatorIssue: Equatable {
    case cancelled
    case transport(code: Int)
    case api(APIError)
    case business(RegistrationResponseFailure)
    case http(RegistrationHTTPFailure)
    case other

    fileprivate init(_ error: Error) {
        if error is CancellationError { self = .cancelled }
        else if let error = error as? URLError, error.code == .cancelled { self = .cancelled }
        else if let error = error as? URLError { self = .transport(code: error.code.rawValue) }
        else if let error = error as? RegistrationResponseFailure { self = .business(error) }
        else if let error = error as? RegistrationHTTPFailure { self = .http(error) }
        else if let error = error as? APIError { self = .api(error) }
        else { self = .other }
    }
}

public enum RegistrationQuoteState: Equatable {
    case idle
    case loading
    /// May be incomplete: `isUsableForCreate` still gates confirmation.
    case received(RegistrationQuote)
    case unavailable(RegistrationCoordinatorIssue)
}

public enum RegistrationCreateUncertainty: Equatable {
    case cancelledLocally
    case accountChanged
    case requestDidNotProduceUsableResponse(RegistrationCoordinatorIssue)
}

public enum RegistrationCreationState: Equatable {
    case idle
    case submitting(requestID: String)
    case outcomeUnknown(requestID: String, reason: RegistrationCreateUncertainty)
    /// Receipt of a create response is NOT a payment or registration success verdict.
    case responseReceived(requestID: String, result: RegistrationCreateResult)
}

public enum RegistrationReadbackState: Equatable {
    case idle
    case loading(registrationID: Int)
    case received(RegistrationStatusSnapshot)
    case unavailable(registrationID: Int, issue: RegistrationCoordinatorIssue)
}

public enum RegistrationCoordinatorAction: Equatable {
    case applied
    case ignoredStale
    case blocked(RegistrationCoordinatorBlock)
}

public enum RegistrationCoordinatorBlock: Equatable {
    case signedOut
    case missingSelection
    case quoteNotUsable
    case intentAlreadySubmitted
    case invalidRequest
    case cancelledBeforeDispatch
    case noKnownRegistrationID
    case readbackInProgress
}

/// Single-flow, main-actor domain coordinator. Every external operation is explicit.
/// Keep this instance alive across sheet dismissal/account changes: it retains one
/// immutable submitted intent per account in memory, including unknown outcomes.
/// There is intentionally no reset, replay, replacement-intent or persistence API.
@MainActor
public final class RegistrationCoordinator {
    public private(set) var accountID: Int?
    public private(set) var selection: RegistrationQuoteRequest?
    public private(set) var quoteState: RegistrationQuoteState = .idle
    public private(set) var readbackState: RegistrationReadbackState = .idle

    private let service: any RegistrationCoordinatingService
    private let makeRequestID: () -> String
    private var token: String?
    private var accountGeneration: UInt64 = 0
    private var quoteGeneration: UInt64 = 0
    private var readbackGeneration: UInt64 = 0
    private var records: [Int: SubmittedRecord] = [:]

    private struct SubmittedRecord {
        let intent: RegistrationCreateIntent
        var state: RegistrationCreationState
    }

    public init(service: any RegistrationCoordinatingService,
                makeRequestID: @escaping () -> String = { "app-\(UUID().uuidString)" }) {
        self.service = service
        self.makeRequestID = makeRequestID
    }

    /// Only the current account's record is exposed. Credentials never appear in state.
    public var retainedIntent: RegistrationCreateIntent? { currentRecord?.intent }
    public var creationState: RegistrationCreationState { currentRecord?.state ?? .idle }
    public var canConfirm: Bool {
        guard accountID != nil, selection != nil, currentRecord == nil,
              case .received(let quote) = quoteState else { return false }
        return quote.isUsableForCreate
    }

    private var currentRecord: SubmittedRecord? {
        accountID.flatMap { records[$0] }
    }

    /// Call for every authenticated-session replacement, even for the same account ID.
    /// The caller must supply the verified account identity belonging to this credential.
    /// Returning to an account restores its lock/intent, never its old quote or credential.
    public func setAccount(id: Int, token: String) throws {
        guard id > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        invalidateAccount()
        accountID = id
        self.token = token
        selection = records[id]?.intent.selection
    }

    public func clearAccount() {
        invalidateAccount()
    }

    private func invalidateAccount() {
        if let id = accountID, var record = records[id], case .submitting = record.state {
            record.state = .outcomeUnknown(requestID: record.intent.requestID, reason: .accountChanged)
            records[id] = record
        }
        accountGeneration &+= 1
        quoteGeneration &+= 1
        readbackGeneration &+= 1
        accountID = nil
        token = nil
        selection = nil
        quoteState = .idle
        readbackState = .idle
    }

    /// A submitted intent locks selection. It cannot be silently replaced after a timeout.
    @discardableResult
    public func select(_ selection: RegistrationQuoteRequest) -> RegistrationCoordinatorAction {
        guard accountID != nil else { return .blocked(.signedOut) }
        guard currentRecord == nil else { return .blocked(.intentAlreadySubmitted) }
        guard self.selection != selection else { return .applied }
        quoteGeneration &+= 1
        self.selection = selection
        quoteState = .idle
        return .applied
    }

    /// A refresh immediately invalidates the previous quote; latest explicit request wins.
    @discardableResult
    public func requestQuote() async -> RegistrationCoordinatorAction {
        guard let id = accountID, let token else { return .blocked(.signedOut) }
        guard currentRecord == nil else { return .blocked(.intentAlreadySubmitted) }
        guard let selection else { return .blocked(.missingSelection) }
        guard !Task.isCancelled else { return .blocked(.cancelledBeforeDispatch) }
        let accountStamp = accountGeneration
        quoteGeneration &+= 1
        let quoteStamp = quoteGeneration
        quoteState = .loading
        do {
            let quote = try await service.quote(selection, token: token)
            guard isCurrent(id, accountStamp), quoteStamp == quoteGeneration else { return .ignoredStale }
            try Task.checkCancellation()
            quoteState = .received(quote)
        } catch {
            guard isCurrent(id, accountStamp), quoteStamp == quoteGeneration else { return .ignoredStale }
            quoteState = .unavailable(RegistrationCoordinatorIssue(error))
        }
        return .applied
    }

    /// Call only for explicit user confirmation after the separate required consent flow.
    /// This domain slice does not record consent or attest that consent exists server-side.
    /// The immutable intent and lock are installed BEFORE the first suspension point.
    @discardableResult
    public func confirm(_ participant: RegistrationParticipantDetails) async -> RegistrationCoordinatorAction {
        guard let id = accountID, let token else { return .blocked(.signedOut) }
        guard currentRecord == nil else { return .blocked(.intentAlreadySubmitted) }
        guard let selection else { return .blocked(.missingSelection) }
        guard case .received(let quote) = quoteState, quote.isUsableForCreate else {
            return .blocked(.quoteNotUsable)
        }
        guard !Task.isCancelled else { return .blocked(.cancelledBeforeDispatch) }
        guard !participant.realName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !participant.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .blocked(.invalidRequest)
        }
        let intent: RegistrationCreateIntent
        do {
            intent = try RegistrationCreateIntent(
                selection: selection, quote: quote, realName: participant.realName,
                phone: participant.phone, email: participant.email,
                participateDate: participant.participateDate,
                usesAppPaymentChannel: participant.usesAppPaymentChannel,
                requestID: makeRequestID(), waitlistOffer: participant.waitlistOffer
            )
        } catch { return .blocked(.invalidRequest) }
        let accountStamp = accountGeneration
        records[id] = SubmittedRecord(intent: intent, state: .submitting(requestID: intent.requestID))
        do {
            let result = try await service.create(intent, token: token)
            guard isCurrentSubmission(id, accountStamp, intent.requestID) else { return .ignoredStale }
            try Task.checkCancellation()
            records[id]?.state = .responseReceived(requestID: intent.requestID, result: result)
        } catch {
            guard isCurrentSubmission(id, accountStamp, intent.requestID) else { return .ignoredStale }
            let issue = RegistrationCoordinatorIssue(error)
            records[id]?.state = .outcomeUnknown(
                requestID: intent.requestID,
                reason: issue == .cancelled ? .cancelledLocally : .requestDidNotProduceUsableResponse(issue)
            )
        }
        return .applied
    }

    /// Exactly one read, only for the registration ID returned for this account's intent.
    /// Does not poll, classify statuses, unlock create, or reconcile an unknown create ID.
    @discardableResult
    public func readKnownStatus() async -> RegistrationCoordinatorAction {
        guard let id = accountID, let token else { return .blocked(.signedOut) }
        guard case .responseReceived(_, let result) = creationState else {
            return .blocked(.noKnownRegistrationID)
        }
        if case .loading = readbackState { return .blocked(.readbackInProgress) }
        guard !Task.isCancelled else { return .blocked(.cancelledBeforeDispatch) }
        let accountStamp = accountGeneration
        readbackGeneration &+= 1
        let readStamp = readbackGeneration
        let registrationID = result.registrationID
        readbackState = .loading(registrationID: registrationID)
        do {
            let snapshot = try await service.readStatus(registrationID: registrationID, token: token)
            guard isCurrent(id, accountStamp), readStamp == readbackGeneration else { return .ignoredStale }
            try Task.checkCancellation()
            guard snapshot.registrationID == registrationID else { throw APIError.malformedResponse }
            readbackState = .received(snapshot)
        } catch {
            guard isCurrent(id, accountStamp), readStamp == readbackGeneration else { return .ignoredStale }
            readbackState = .unavailable(registrationID: registrationID, issue: RegistrationCoordinatorIssue(error))
        }
        return .applied
    }

    /// Local dismissal/cancellation is not server cancellation. In-flight create is left
    /// unknown and locked; a late completion cannot silently change that decision.
    /// This invalidates completion handlers, not the already-dispatched network request.
    public func cancelPendingOperations() {
        quoteGeneration &+= 1
        quoteState = .idle
        readbackGeneration &+= 1
        if case .loading(let id) = readbackState {
            readbackState = .unavailable(registrationID: id, issue: .cancelled)
        }
        if let id = accountID, var record = records[id], case .submitting = record.state {
            record.state = .outcomeUnknown(requestID: record.intent.requestID, reason: .cancelledLocally)
            records[id] = record
        }
    }

    private func isCurrent(_ id: Int, _ stamp: UInt64) -> Bool {
        accountID == id && accountGeneration == stamp
    }

    private func isCurrentSubmission(_ id: Int, _ stamp: UInt64, _ requestID: String) -> Bool {
        guard isCurrent(id, stamp), case .submitting(let retainedID) = creationState else { return false }
        return retainedID == requestID
    }
}
