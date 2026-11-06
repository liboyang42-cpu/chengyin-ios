import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Concrete dormant HTTP adapter. Host must inject endpoint, existing token/session access,
/// journal and explicit grants. No production transport or endpoint is constructed here.
@MainActor public final class AccountComplianceService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let journal: any ComplianceJournaling
    private let current: () -> ComplianceSession?
    private let token: () -> String?
    private let readsEnabled: Bool
    private let writesEnabled: Bool
    private let legalApproved: (ComplianceSubject, ComplianceSession) -> Bool
    private let authoritativeMerchantID: () -> Int?
    private let npcChatDataReadApproval: () -> OperationEndpointApproval?
    private let marketingOriginal: () -> MerchantMarketingConsentOriginalClient?
    public var marketingOriginalRevision: UUID? { marketingOriginal()?.approval.revision }
    /// Read-only availability query; the original writer rechecks the same grant at send time.
    public func canChangeMarketing(_ row: ComplianceMarketingConsent, channel: ComplianceMarketingChannel,
                                   optedIn: Bool, session: ComplianceSession) -> Bool {
        guard journal.isDurable, let client = try? marketingClient(session) else { return false }
        return client.canWrite(row, channel, optedIn)
    }
    private let deregistrationOriginal: () -> AccountDeregistrationOriginalClient?
    public var deregistrationOriginalRevision: UUID? { deregistrationOriginal()?.approval.issuanceID }
    private var busy = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                journal: any ComplianceJournaling, current: @escaping () -> ComplianceSession?,
                token: @escaping () -> String?, readsEnabled: Bool = false, writesEnabled: Bool = false,
                legalApproved: @escaping (ComplianceSubject, ComplianceSession) -> Bool = { _, _ in false },
                authoritativeMerchantID: @escaping () -> Int? = { nil },
                npcChatDataReadApproval: @escaping () -> OperationEndpointApproval? = { nil },
                marketingOriginal: @escaping () -> MerchantMarketingConsentOriginalClient? = { nil },
                deregistrationOriginal: @escaping () -> AccountDeregistrationOriginalClient? = { nil }) {
        self.configuration = configuration; self.transport = transport; self.journal = journal
        self.current = current; self.token = token; self.readsEnabled = readsEnabled
        self.writesEnabled = writesEnabled; self.legalApproved = legalApproved; self.authoritativeMerchantID = authoritativeMerchantID
        self.npcChatDataReadApproval = npcChatDataReadApproval
        self.deregistrationOriginal = deregistrationOriginal
        self.marketingOriginal = marketingOriginal
    }
    /// Separate, exact read acceptance. Chat/model grants and the existing generic
    /// compliance read/write booleans cannot authorize this private-text endpoint.
    public func canReadNPCChatData(session: ComplianceSession) -> Bool {
        guard session.valid, current() == session, let credential = token(), AuthRequestBuilder.isValidToken(credential),
              let approval = npcChatDataReadApproval() else { return false }
        return approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: NPCChatData.path)
    }
    public func readNPCChatData(session: ComplianceSession) async throws -> NPCChatData {
        guard canReadNPCChatData(session: session), let credential = token(), let approval = npcChatDataReadApproval() else {
            throw NPCChatDataFailure.unavailable
        }
        // Identity comes only from the existing Authorization header. No body,
        // user ID, merchant ID, query filter, model context or new token is sent.
        var outgoing = try request("/" + NPCChatData.path, method: "GET", session: session)
        outgoing.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        outgoing.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard outgoing.value(forHTTPHeaderField: "Authorization") == credential, current() == session,
              npcChatDataReadApproval() == approval, canReadNPCChatData(session: session) else { throw NPCChatDataFailure.staleSession }
        let (bytes, status) = try await transport.send(outgoing)
        try Task.checkCancellation()
        guard current() == session, token() == credential, npcChatDataReadApproval() == approval,
              canReadNPCChatData(session: session) else { throw NPCChatDataFailure.staleSession }
        guard status != 401 else { throw NPCChatDataFailure.signedOut }
        guard (200..<300).contains(status) else { throw NPCChatDataFailure.failed }
        return try NPCChatData.decode(bytes, expectedAccountID: session.accountID)
    }
    public func check(_ session: ComplianceSession) throws {
        guard session.valid, current() == session else { throw ComplianceFailure.staleSession }
        try Task.checkCancellation()
    }
    public func unresolved(_ operation: String, session: ComplianceSession) throws -> CompliancePendingOperation? {
        try check(session); return try journal.pending(scope: session.journalScope, operation: operation)
    }
    private func request(_ path: String, method: String = "POST", body: [String: Any]? = nil,
                         form: [String: String]? = nil, session: ComplianceSession) throws -> URLRequest {
        try check(session)
        guard let token = token(), AuthRequestBuilder.isValidToken(token) else { throw ComplianceFailure.staleSession }
        let url = configuration.baseURL.appendingPathComponent(String(path.dropFirst()))
        if let form { return try AuthRequestBuilder.makeFormRequest(url: url, fields: form, token: token) }
        var request = URLRequest(url: url); request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func send(_ request: URLRequest, session: ComplianceSession) async throws -> Any? {
        try check(session)
        let (data, status) = try await transport.send(request)
        try check(session)
        // HTTP failures are uncertain for mutations. Only a valid business rejection is definite.
        guard (200..<300).contains(status), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = root["code"] as? Int else { throw ComplianceFailure.malformed }
        let message = (root["msg"] as? String) ?? String(code)
        guard code == 200 else { throw ComplianceFailure.rejected(message) }
        return root["data"]
    }
    private func decode<T: Decodable>(_ data: Any?, as type: T.Type) throws -> T {
        guard let data, !(data is NSNull) else { throw ComplianceFailure.malformed }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed))
    }
    private func read(_ path: String, method: String = "POST", body: [String: Any]? = nil, session: ComplianceSession) async throws -> Any? {
        guard readsEnabled else { throw ComplianceFailure.unavailable }
        return try await send(request(path, method: method, body: body, session: session), session: session)
    }
    private func checkScope(_ subject: ComplianceSubject) throws {
        if let id = subject.scopeID, authoritativeMerchantID() != id { throw ComplianceFailure.staleSession }
    }
    public func latest(_ subject: ComplianceSubject, session: ComplianceSession) async throws -> ComplianceConsent? {
        try checkScope(subject)
        let data = try await read("/api/compliance/consents/latest", body: subject.fields(), session: session)
        try checkScope(subject)
        guard let object = data as? [String: Any], !object.isEmpty else { return nil }
        return try decode(object, as: ComplianceConsent.self)
    }
    private func start(_ operation: String, requestID: String, session: ComplianceSession) throws {
        try check(session)
        guard readsEnabled, writesEnabled else { throw ComplianceFailure.unavailable }
        guard !busy else { throw ComplianceFailure.busy }
        guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, requestID.count <= 64 else { throw ComplianceFailure.invalidInput }
        try journal.begin(.init(scope: session.journalScope, operation: operation, requestID: requestID, epoch: session.epoch)); busy = true
    }
    private func write(_ request: URLRequest, operation: String, session: ComplianceSession) async throws -> Any? {
        do { return try await send(request, session: session) }
        catch ComplianceFailure.rejected(let message) {
            try journal.resolve(scope: session.journalScope, operation: operation)
            throw ComplianceFailure.rejected(message)
        }
    }
    private func beginDeregistrationCancelPending(_ operation: String, requestID: String, session: ComplianceSession) throws {
        try check(session)
        guard readsEnabled, writesEnabled else { throw ComplianceFailure.unavailable }
        guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, requestID.count <= 64 else { throw ComplianceFailure.invalidInput }
        try journal.begin(.init(scope: session.journalScope, operation: operation, requestID: requestID, epoch: session.epoch))
    }
    /// Compare both captured intents before removing either. Another service/view sharing
    /// the journal must not have its newly created application erased by a delayed status.
    private func resolveCancellation(_ cancellation: CompliancePendingOperation,
                                     application: CompliancePendingOperation?, session: ComplianceSession) throws {
        try check(session)
        guard try journal.pending(scope: session.journalScope, operation: "deregisterCancel") == cancellation,
              try journal.pending(scope: session.journalScope, operation: "deregister") == application else { throw ComplianceFailure.unresolved }
        // Keep cancellation as the final recovery marker if resolving either record fails.
        if application != nil { try journal.resolve(scope: session.journalScope, operation: "deregister") }
        try journal.resolve(scope: session.journalScope, operation: "deregisterCancel")
    }
    private func writeDeregistrationCancel(_ request: URLRequest, operation: String, session: ComplianceSession,
                       whileCurrent: () -> Bool = { true }, expectedIntent: CompliancePendingOperation? = nil) async throws -> Any? {
        do { return try await send(request, session: session) }
        catch ComplianceFailure.rejected(let message) {
            try check(session)
            guard whileCurrent() else { throw ComplianceFailure.staleSession }
            if let expectedIntent {
                guard try journal.pending(scope: session.journalScope, operation: operation) == expectedIntent else { throw ComplianceFailure.unresolved }
            }
            try journal.resolve(scope: session.journalScope, operation: operation)
            throw ComplianceFailure.rejected(message)
        }
    }
    /// Local metadata only: old consent rows do not identify a realm or document version.
    public func readDeregistrationConsent(session: ComplianceSession) throws -> AccountDeregistrationConsentReadState {
        try check(session)
        let result: AccountDeregistrationConsentReadState
        do {
            if let intent = try journal.pending(scope: session.journalScope, operation: ComplianceSubject.cancellation.operation) {
                result = intent.scope == session.journalScope && intent.operation == ComplianceSubject.cancellation.operation
                    ? .unknown(requestID: intent.requestID) : .unavailable
            } else { result = .none }
        } catch { result = .unavailable }
        try check(session); return result
    }
    public func consent(_ subject: ComplianceSubject, event: ComplianceEvent, requestID: String, session: ComplianceSession,
                        expectedConsentVersion: String? = nil, whileCurrent: () -> Bool = { true }) async throws -> ComplianceConsent {
        try checkScope(subject)
        if subject == .cancellation, event == .agree, let client = deregistrationOriginal() {
            try check(session)
            guard whileCurrent(), client.matches(session), client.approval.writes, client.approval.legalApproved, journal.isDurable, !busy else { throw ComplianceFailure.unavailable }
            guard let version = expectedConsentVersion, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  AccountDeregistrationOriginalClient.validUUID(requestID) else { throw ComplianceFailure.invalidInput }
            guard try readDeregistrationConsent(session: session) == .none else { throw ComplianceFailure.unresolved }
            busy = true; defer { busy = false }
            let intent = CompliancePendingOperation(scope: session.journalScope, operation: subject.operation, requestID: requestID, epoch: session.epoch)
            try journal.begin(intent)
            guard whileCurrent(), client.matches(session), deregistrationOriginal()?.approval.issuanceID == client.approval.issuanceID,
                  try journal.pending(scope: session.journalScope, operation: subject.operation) == intent else { throw ComplianceFailure.unresolved }
            let result = try await client.consent(requestID: requestID, session: session, expectedDocumentVersion: version)
            try check(session)
            guard whileCurrent(), client.matches(session), deregistrationOriginal()?.approval.issuanceID == client.approval.issuanceID,
                  try journal.pending(scope: session.journalScope, operation: subject.operation) == intent else { throw ComplianceFailure.unresolved }
            try journal.resolve(scope: session.journalScope, operation: subject.operation)
            guard try journal.pending(scope: session.journalScope, operation: subject.operation) == nil else { throw ComplianceFailure.unresolved }
            return result
        }
        if event == .agree, !legalApproved(subject, session) { throw ComplianceFailure.unavailable }
        var fields = try subject.fields(); fields["eventType"] = event.rawValue; fields["requestId"] = requestID
        let request = try request("/api/compliance/consents", body: fields, session: session)
        try start(subject.operation, requestID: requestID, session: session); defer { busy = false }
        _ = try await write(request, operation: subject.operation, session: session)
        guard let result = try await latest(subject, session: session), result.matches(subject, event: event) else { throw ComplianceFailure.readbackMismatch }
        try journal.resolve(scope: session.journalScope, operation: subject.operation)
        return result
    }
    /// Reconcile truth without retrying the mutation; exact scene/scope/event required.
    public func reconcileConsent(_ subject: ComplianceSubject, event: ComplianceEvent, session: ComplianceSession) async throws -> ComplianceConsent {
        // A legacy cancellation consent has no original-result GET. Never settle it from latest.
        if subject == .cancellation, event == .agree { throw ComplianceFailure.unresolved }
        guard let record = try await latest(subject, session: session), record.matches(subject, event: event) else { throw ComplianceFailure.readbackMismatch }
        try journal.resolve(scope: session.journalScope, operation: subject.operation); return record
    }
    private func marketingClient(_ session:ComplianceSession)throws->MerchantMarketingConsentOriginalClient {
        try check(session)
        guard let client=marketingOriginal(),client.matches(session) else{throw ComplianceFailure.unavailable};return client
    }
    public func marketing(session: ComplianceSession) async throws -> [ComplianceMarketingConsent] {
        try await marketingClient(session).list(session:session)
    }
    public func pendingMarketingOperations(session: ComplianceSession) throws -> Set<String> {
        try check(session);return Set(try journal.marketingPending(scope:session.journalScope).map(\.operation))
    }
    /// GET-only original history. Latest boolean equality never settles any original UUID.
    public func recoverMarketing(session: ComplianceSession, whileCurrent: () -> Bool = { true }) async throws -> ComplianceMarketingSnapshot {
        try check(session);guard whileCurrent() else{throw ComplianceFailure.staleSession};guard !busy else{throw ComplianceFailure.busy}
        let client=try marketingClient(session);busy=true;defer{busy=false}
        let pending=try journal.marketingPending(scope:session.journalScope)
        var results:[MerchantMarketingConsentOriginalReceipt]=[]
        for intent in pending {
            try check(session);guard whileCurrent(),client.matches(session),try journal.pending(scope:session.journalScope,operation:intent.operation)==intent else{throw ComplianceFailure.unresolved}
            guard intent.marketingOptedIn != nil,intent.marketingRealm?.utf8.elementsEqual(client.context.baseURL.absoluteString.utf8) == true,MerchantMarketingConsentOriginalTarget(intent:intent) != nil else{continue}
            do {
                let receipt=try await client.result(intent,session:session)
                try check(session);guard whileCurrent(),client.matches(session) else{throw ComplianceFailure.staleSession}
                if receipt.recorded {try resolveMarketing(intent,session:session,whileCurrent:whileCurrent)}
                results.append(receipt)
            } catch {
                if error as? APIError == .unauthorized || error as? MerchantBusinessFailure == .denied {throw error}
                try check(session);guard whileCurrent(),client.matches(session) else{throw ComplianceFailure.staleSession}
                // This one original request remains UNKNOWN. No retry, old bool match or inferred failure.
            }
        }
        let rows:[ComplianceMarketingConsent];let available:Bool
        do{rows=try await client.list(session:session);available=true}
        catch{if error as? APIError == .unauthorized || error as? MerchantBusinessFailure == .denied{throw error};rows=[];available=false}
        try check(session);guard whileCurrent(),client.matches(session) else{throw ComplianceFailure.staleSession}
        return .init(rows:rows,unresolvedOperations:try pendingMarketingOperations(session:session),reconciledCurrentState:false,originalResults:results,currentAvailable:available)
    }
    private func resolveMarketing(_ intent:CompliancePendingOperation,session:ComplianceSession,whileCurrent:()->Bool)throws{
        try check(session);guard whileCurrent(),intent.scope==session.journalScope,try journal.pending(scope:session.journalScope,operation:intent.operation)==intent else{throw ComplianceFailure.unresolved}
        try journal.resolve(scope:session.journalScope,operation:intent.operation)
        guard try journal.pending(scope:session.journalScope,operation:intent.operation)==nil else{throw ComplianceFailure.unresolved}
    }
    public func setMarketing(_ row:ComplianceMarketingConsent,channel:ComplianceMarketingChannel,optedIn:Bool,requestID:String,
                             session:ComplianceSession,whileCurrent:()->Bool = {true})async throws->ComplianceMarketingSnapshot {
        try check(session);guard whileCurrent(),row.valid else{throw ComplianceFailure.invalidInput}
        guard !busy else{throw ComplianceFailure.busy}
        let client=try marketingClient(session);guard journal.isDurable,client.canWrite(row,channel,optedIn) else{throw ComplianceFailure.unavailable}
        let operation=row.operation(channel);guard try journal.pending(scope:session.journalScope,operation:operation)==nil else{throw ComplianceFailure.unresolved}
        let intent=CompliancePendingOperation(scope:session.journalScope,operation:operation,requestID:requestID,epoch:session.epoch,marketingOptedIn:optedIn,marketingRealm:client.context.baseURL.absoluteString)
        guard MerchantMarketingConsentOriginalTarget(intent:intent) != nil else{throw ComplianceFailure.invalidInput}
        busy=true;defer{busy=false}
        let currentRows=try await client.list(session:session)
        try check(session); guard whileCurrent(), client.matches(session) else { throw ComplianceFailure.staleSession }
        guard currentRows.contains(row),row.value(channel) != optedIn else{throw ComplianceFailure.readbackMismatch}
        let prior=try await client.result(intent,session:session)
        try check(session);guard whileCurrent(),client.matches(session),!prior.recorded else{throw ComplianceFailure.unresolved}
        try journal.begin(intent)
        guard try journal.pending(scope:session.journalScope,operation:operation)==intent else{throw ComplianceFailure.unresolved}
        // This independent marketing path never uses generic compliance.write's rejection-clearing behavior.
        do {
            try check(session);guard whileCurrent(),client.matches(session) else{throw ComplianceFailure.staleSession}
            try await client.write(row,channel:channel,optedIn:optedIn,intent:intent,session:session)
            try check(session);guard whileCurrent(),client.matches(session) else{throw ComplianceFailure.staleSession}
            let original=try await client.result(intent,session:session)
            try check(session);guard whileCurrent(),client.matches(session),original.recorded else{throw ComplianceFailure.unresolved}
            try resolveMarketing(intent,session:session,whileCurrent:whileCurrent)
            let rows:[ComplianceMarketingConsent];let available:Bool
            do{rows=try await client.list(session:session);available=true}
            catch{if error as? APIError == .unauthorized || error as? MerchantBusinessFailure == .denied{throw error};rows=[];available=false}
            try check(session);guard whileCurrent(),client.matches(session) else{throw ComplianceFailure.staleSession}
            return .init(rows:rows,unresolvedOperations:try pendingMarketingOperations(session:session),reconciledCurrentState:false,originalResults:[original],currentAvailable:available)
        } catch {
            if error as? APIError == .unauthorized || error as? MerchantBusinessFailure == .denied {throw error}
            throw ComplianceFailure.unresolved
        }
    }
    public func status(session: ComplianceSession) async throws -> ComplianceDeregistration {
        if let client = deregistrationOriginal() { return try await client.status(session: session) }
        return try decode(await read("/api/user/deregister/status", method: "GET", session: session), as: ComplianceDeregistration.self)
    }
    /// Exact GET only, including after cold launch/new authentication. UNKNOWN never becomes a resend.
    public func recoverOriginalApplication(session: ComplianceSession, whileCurrent: () -> Bool = { true }) async throws -> AccountDeregistrationOriginalReceipt? {
        guard !busy, whileCurrent() else { throw ComplianceFailure.busy }
        guard let intent = try unresolved("deregister", session: session), intent.deregistrationOriginalVersion == 1 else { return nil }
        guard let client = deregistrationOriginal(), client.matches(session) else { throw ComplianceFailure.unavailable }
        busy = true; defer { busy = false }
        let receipt = try await client.result(intent, session: session)
        try check(session)
        guard whileCurrent(), client.matches(session), try unresolved("deregister", session: session) == intent else { throw ComplianceFailure.unresolved }
        if receipt.settled && !receipt.accepted { try journal.resolve(scope: session.journalScope, operation: "deregister") }
        // Accepted retains its original epoch for the unchanged cancellation/fresh-login guard.
        return receipt
    }
    /// Read-only recovery of the current cancellation state. This endpoint has no request
    /// receipt contract: NORMAL, PENDING, FAILED and unknown states cannot settle a lost cancel.
    public func recoverDeregistrationStatus(session: ComplianceSession,
                                             whileCurrent: () -> Bool = { true }) async throws -> ComplianceDeregistration {
        guard !busy else { throw ComplianceFailure.busy }
        guard whileCurrent() else { throw ComplianceFailure.staleSession }
        busy = true; defer { busy = false }
        let pendingCancellation = try unresolved("deregisterCancel", session: session)
        let pendingApplication = try unresolved("deregister", session: session)
        let result = try await status(session: session)
        try check(session)
        guard whileCurrent() else { throw ComplianceFailure.staleSession }
        if let pendingCancellation, result.cancellationConfirmed {
            try resolveCancellation(pendingCancellation, application: pendingApplication, session: session)
        }
        return result
    }
    public func precheck(session: ComplianceSession) async throws -> ComplianceDeregistration {
        if let client = deregistrationOriginal() { return try await client.precheck(session: session) }
        return try decode(await read("/api/user/deregister/precheck", session: session), as: ComplianceDeregistration.self)
    }
    public func apply(smscode: String, requestID: String, session: ComplianceSession, impact: AccountDeregistrationImpact? = nil, whileCurrent: () -> Bool = { true }) async throws -> ComplianceDeregistration {
        if let client = deregistrationOriginal() {
            try check(session)
            guard !busy, whileCurrent(), journal.isDurable, client.matches(session), client.approval.writes, client.approval.legalApproved else { throw ComplianceFailure.unavailable }
            guard try readDeregistrationConsent(session: session) == .none else { throw ComplianceFailure.unresolved }
            guard try unresolved("deregister", session: session) == nil, try unresolved("deregisterCancel", session: session) == nil else { throw ComplianceFailure.unresolved }
            guard let impact, impact.valid(for: session.accountID), impact.confirmable else { throw ComplianceFailure.invalidInput }
            let code = try AuthChannelInput.code(smscode)
            let intent = CompliancePendingOperation(scope: session.journalScope, operation: "deregister", requestID: requestID, epoch: session.epoch,
                deregistrationRealm: client.context.baseURL.absoluteString, deregistrationOriginalVersion: 1, deregistrationImpactRevision: impact.revision)
            guard AccountDeregistrationOriginalClient.validUUID(requestID) else { throw ComplianceFailure.invalidInput }
            busy = true; defer { busy = false }
            let prior = try await client.result(intent, session: session)
            try check(session)
            guard whileCurrent(), client.matches(session), !prior.settled else { throw ComplianceFailure.unresolved }
            try journal.begin(intent)
            guard try unresolved("deregister", session: session) == intent, whileCurrent(), client.matches(session) else { throw ComplianceFailure.unresolved }
            try await client.apply(code: code, intent: intent, session: session)
            try check(session); guard whileCurrent(), client.matches(session) else { throw ComplianceFailure.staleSession }
            let receipt = try await client.result(intent, session: session)
            try check(session)
            guard whileCurrent(), client.matches(session), try unresolved("deregister", session: session) == intent, receipt.settled else { throw ComplianceFailure.unresolved }
            if !receipt.accepted {
                try journal.resolve(scope: session.journalScope, operation: "deregister")
                throw ComplianceFailure.rejected(receipt.reason == "ACCOUNT_IMPACT_CHANGED_REFRESH_AND_CONFIRM"
                    ? "compliance.impactChanged" : "compliance.failed")
            }
            // Server normally revokes the old credential on accepted apply. A 401 leaves this intent for fresh-login GET recovery.
            return try await client.status(session: session)
        }
        guard impact == nil, legalApproved(.cancellation, session) else { throw ComplianceFailure.unavailable }
        let request = try request("/api/user/deregister/apply", form: ["smscode": AuthChannelInput.code(smscode), "requestId": requestID], session: session)
        try start("deregister", requestID: requestID, session: session); defer { busy = false }
        let result = try decode(await write(request, operation: "deregister", session: session), as: ComplianceDeregistration.self)
        // Accepted applications retain the original epoch until fresh authentication and status read.
        if result.blocked { try journal.resolve(scope: session.journalScope, operation: "deregister") }
        return result
    }
    public func cancel(session: ComplianceSession,
                       whileCurrent: () -> Bool = { true }) async throws -> ComplianceDeregistration {
        guard !busy else { throw ComplianceFailure.busy }
        guard whileCurrent() else { throw ComplianceFailure.staleSession }
        busy = true; defer { busy = false }
        // Never redispatch an outcome-unknown cancellation, even after relaunch or a new login.
        guard try unresolved("deregisterCancel", session: session) == nil else { throw ComplianceFailure.unresolved }
        let pending = try unresolved("deregister", session: session)
        if let pending, pending.epoch == session.epoch { throw ComplianceFailure.staleSession }
        let before = try await status(session: session)
        try check(session)
        guard whileCurrent() else { throw ComplianceFailure.staleSession }
        guard before.pending else { throw ComplianceFailure.invalidInput }
        guard try unresolved("deregister", session: session) == pending else { throw ComplianceFailure.unresolved }
        let request = try request("/api/user/deregister/cancel", session: session)
        try beginDeregistrationCancelPending("deregisterCancel", requestID: UUID().uuidString, session: session)
        guard let cancellation = try unresolved("deregisterCancel", session: session) else { throw ComplianceFailure.unresolved }
        let data = try await writeDeregistrationCancel(request, operation: "deregisterCancel", session: session, whileCurrent: whileCurrent, expectedIntent: cancellation)
        try check(session)
        guard whileCurrent() else { throw ComplianceFailure.staleSession }
        let result = try decode(data, as: ComplianceDeregistration.self)
        guard result.cancellationConfirmed else { throw ComplianceFailure.readbackMismatch }
        let confirmed = try await status(session: session)
        try check(session)
        guard whileCurrent() else { throw ComplianceFailure.staleSession }
        guard confirmed.cancellationConfirmed else { throw ComplianceFailure.readbackMismatch }
        try resolveCancellation(cancellation, application: pending, session: session)
        return confirmed
    }
}
