import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class MerchantEngagementProductionTests: XCTestCase {
    private let url = URL(string: "https://example.com")!
    private var segment: MerchantEngagementCommand { .saveSegment(name: "Reviewed segment", filter: .init()) }
    private func context(account: Int = 21, epoch: UInt64 = 1, namespace: String = "merchant-cn", role: String = "merchant", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: url, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "test-token"))
    }
    private func scope(_ context: RuntimeDependencyContext) -> MerchantBusinessScope { .init(realm: url.absoluteString, accountID: context.session.accountID, epoch: context.session.epoch) }
    private func approval(_ command: MerchantEngagementCommand, obligations: Set<MerchantEngagementObligation> = [.marketingConsent, .customerContactPrivacy, .customerExportPrivacy, .aftercareEvidencePrivacy], devices: [MerchantEngagementDeviceGrant] = []) throws -> MerchantEngagementProductionApproval {
        try .init(market: .china, endpoints: .init(baseURL: url, namespace: "merchant-cn", accountID: 21, paths: [command.request(requestID: "grant-validation").path]),
            grants: [.init(merchantID: 710, command: command)], deviceGrants: devices, reviewedObligations: obligations, reviewedPolicyVersion: "reviewed-test-policy")
    }
    private func reader(_ wire: Wire, command: MerchantEngagementCommand, approval: MerchantEngagementProductionApproval? = nil,
                        beforeForward: (@MainActor () async -> Void)? = nil, current: @escaping () -> RuntimeDependencyContext?) throws -> MerchantEngagementSessionReader {
        let api = try APIConfiguration(baseURL: url), approval = try approval ?? self.approval(command)
        func factory() -> MerchantEngagementProductionFactory {
            var factory = MerchantEngagementProductionFactory(api: api, approval: approval, transport: wire, current: current).withDownloadTestingTransport(wire)
            if let beforeForward { factory = factory.withDispatchBarrier(beforeForward) }; return factory
        }
        return MerchantEngagementSessionReader(service: .init(configuration: api, readTransport: wire), session: {
            guard let current = current() else { return nil }; return try? .init(accountID: current.session.accountID, epoch: current.session.epoch, token: current.session.token)
        }, productionService: { command, merchant in factory().service(for: command, merchantID: merchant) },
           devicePermission: { action, merchant in factory().permitsDevice(action, merchantID: merchant) }, runtimeContext: current)
    }
    private func journalURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("intents.json") }
    private func coordinator(_ reader: MerchantEngagementSessionReader, journal: any MerchantBusinessIntentStore) -> MerchantEngagementCoordinator {
        .init(reader: reader, journal: journal, exportRecovery: MerchantExportMemoryRecoveryStore())
    }
    private func confirm(_ coordinator: MerchantEngagementCoordinator, _ command: MerchantEngagementCommand) async throws {
        await coordinator.prepare(command); await coordinator.confirm(try XCTUnwrap(coordinator.review))
    }
    func testDormantFactoryAndBareServiceCannotDispatch() async throws {
        let c = try context(), wire = Wire(), api = try APIConfiguration(baseURL: url)
        XCTAssertNil(MerchantEngagementProductionFactory(api: api, transport: wire, current: { c }).service(for: segment, merchantID: 710))
        let service = try XCTUnwrap(MerchantEngagementProductionFactory(api: api, approval: approval(segment), transport: wire, current: { c }).service(for: segment, merchantID: 710))
        do { _ = try await service.execute(segment, requestID: "request-123", access: .init(Wire.accessFields), token: "test-token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        XCTAssertEqual(wire.requests.count, 0)
    }
    func testExactCommandMerchantAccountNamespaceMarketAndOriginRequired() throws {
        let c = try context(), approval = try approval(segment)
        XCTAssertTrue(approval.permits(segment, merchantID: 710, context: c))
        XCTAssertFalse(approval.permits(.saveSegment(name: "Other content", filter: .init()), merchantID: 710, context: c))
        XCTAssertFalse(approval.permits(segment, merchantID: 711, context: c))
        XCTAssertFalse(approval.permits(segment, merchantID: 710, context: try context(account: 22)))
        XCTAssertFalse(approval.permits(segment, merchantID: 710, context: try context(namespace: "other-cn")))
        XCTAssertFalse(approval.permits(segment, merchantID: 710, context: try context(market: .unitedStates)))
        let other = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://other.example.com")!, role: c.role, session: c.session)
        XCTAssertFalse(approval.permits(segment, merchantID: 710, context: other))
    }
    func testPrivacyAndMarketingObligationsAreIndependent() throws {
        let c = try context(), contact = MerchantEngagementCommand.contact(try .init(61001), .copy)
        XCTAssertFalse(try approval(contact, obligations: []).permits(contact, merchantID: 710, context: c))
        let broadcast = MerchantEngagementCommand.broadcast(try .init(audience: .init(filter: .init(), scope: .all, groups: []), content: "Reviewed message"))
        XCTAssertFalse(try approval(broadcast, obligations: [.customerContactPrivacy]).permits(broadcast, merchantID: 710, context: c))
    }
    func testOrdinaryHTTPPersistsReviewAndReadsPermissionsThreeTimes() async throws {
        let c = try context(), wire = Wire(), path = journalURL(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let reader = try reader(wire, command: segment, current: { c }), journal = MerchantBusinessFileIntentStore(url: path)
        let coordinator = coordinator(reader, journal: journal)
        XCTAssertFalse(reader.isSyntheticEnabled); await coordinator.prepare(segment)
        let review = try XCTUnwrap(coordinator.review); await coordinator.confirm(review)
        XCTAssertNotNil(coordinator.receipt); XCTAssertEqual(wire.writes.count, 1); XCTAssertEqual(wire.accessCount, 3)
        let request = try XCTUnwrap(wire.writes.first)
        XCTAssertEqual(request.url?.path, "/api/merchant/crm/segments"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(request.httpBody)).object?["requestId"], .string(review.requestID))
        XCTAssertTrue(try journal.intents().isEmpty)
        await coordinator.confirm(review); XCTAssertEqual(wire.writes.count, 1)
    }
    func testProductionRequiresDurableJournal() async throws {
        let c = try context(), wire = Wire(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: MerchantBusinessMemoryIntentStore())
        try await confirm(coordinator, segment); XCTAssertEqual(coordinator.failure, .disabled); XCTAssertTrue(wire.writes.isEmpty)
    }
    func testFreshPermissionRevocationDoesNotUseRoleAsAuthority() async throws {
        let c = try context(), wire = Wire(), journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: journal)
        await coordinator.prepare(segment); let review = try XCTUnwrap(coordinator.review)
        wire.permissions = []; await coordinator.confirm(review)
        XCTAssertEqual(coordinator.failure, .denied); XCTAssertTrue(wire.writes.isEmpty); XCTAssertTrue(journal.rows.isEmpty)
    }
    func testChangedMerchantAfterReviewIsRejected() async throws {
        let c = try context(), wire = Wire(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: ReentrantJournal())
        await coordinator.prepare(segment); let review = try XCTUnwrap(coordinator.review); wire.merchantID = 711
        await coordinator.confirm(review); XCTAssertEqual(coordinator.failure, .conflict); XCTAssertTrue(wire.writes.isEmpty)
    }
    func testAfterReservationPermissionRevocationRetainsUncertainLock() async throws {
        let c = try context(), wire = Wire(), journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: journal)
        journal.onReserve = { wire.permissions = [] }
        try await confirm(coordinator, segment); XCTAssertTrue(wire.writes.isEmpty); XCTAssertEqual(journal.rows.count, 1)
    }
    func testJournalReentrancyCancellationPreventsDispatch() async throws {
        let c = try context(), wire = Wire(), journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: journal)
        journal.onReserve = { coordinator.cancelReview() }
        try await confirm(coordinator, segment); XCTAssertTrue(wire.writes.isEmpty); XCTAssertEqual(journal.rows.count, 1)
    }
    func testFinalHTTPBarrierCancellationPreventsDispatch() async throws {
        let c = try context(), wire = Wire(), journal = ReentrantJournal(); var cancel: (() -> Void)?
        let reader = try reader(wire, command: segment, beforeForward: { cancel?(); await Task.yield() }, current: { c })
        let coordinator = coordinator(reader, journal: journal); cancel = { coordinator.cancelReview() }
        try await confirm(coordinator, segment); XCTAssertTrue(wire.writes.isEmpty); XCTAssertEqual(journal.rows.count, 1)
    }
    func testSameEpochNamespaceOrRoleChangeInvalidatesReview() async throws {
        for roleChange in [false, true] {
            var c = try context(); let wire = Wire(), journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: journal)
            await coordinator.prepare(segment); let review = try XCTUnwrap(coordinator.review)
            c = try context(namespace: roleChange ? "merchant-cn" : "other-cn", role: roleChange ? "player" : "merchant")
            await coordinator.confirm(review); XCTAssertTrue(wire.writes.isEmpty); XCTAssertNil(coordinator.receipt)
        }
    }
    func testTimeoutLockPersistsAcrossReopenedCoordinatorAndNoSecretsSaved() async throws {
        let c = try context(), wire = Wire(), path = journalURL(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let reader = try reader(wire, command: segment, current: { c }), journal = MerchantBusinessFileIntentStore(url: path)
        wire.writeError = URLError(.timedOut); try await confirm(coordinator(reader, journal: journal), segment)
        let raw = try String(contentsOf: path); XCTAssertTrue(raw.contains("merchant-cn")); XCTAssertFalse(raw.contains("test-token")); XCTAssertFalse(raw.contains("Reviewed segment"))
        let reopened = coordinator(reader, journal: MerchantBusinessFileIntentStore(url: path)); await reopened.prepare(segment)
        XCTAssertEqual(reopened.failure, .pending); XCTAssertNil(reopened.review); XCTAssertEqual(wire.writes.count, 1)
    }
    func testDownstreamDisabledErrorAfterForwardDoesNotEraseLock() async throws {
        let c = try context(), wire = Wire(), journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: journal)
        wire.writeError = MerchantBusinessFailure.disabled; try await confirm(coordinator, segment)
        XCTAssertEqual(coordinator.failure, .unknown); XCTAssertEqual(journal.rows.count, 1)
    }
    func testAccountReplacementAfterResponseCannotShowReceiptOrClearLock() async throws {
        var c: RuntimeDependencyContext? = try context(); let wire = Wire(), journal = ReentrantJournal()
        let coordinator = coordinator(try reader(wire, command: segment, current: { c }), journal: journal)
        wire.onWrite = { c = nil }; try await confirm(coordinator, segment)
        XCTAssertNil(coordinator.receipt); XCTAssertEqual(journal.rows.count, 1)
    }
    func testCampaignCreationAndBroadcastKeepExactContentAndAudience() async throws {
        let c = try context()
        let commands: [MerchantEngagementCommand] = [
            .createCampaign(try .init(segmentID: 71001, channel: .inApp, couponID: nil, title: "Reviewed title", content: "Reviewed content")),
            .broadcast(try .init(audience: .init(filter: .init(), scope: .team, groups: ["Reviewed team"]), content: "Reviewed content"))]
        for command in commands {
            let wire = Wire(), coordinator = coordinator(try reader(wire, command: command, current: { c }), journal: ReentrantJournal())
            try await confirm(coordinator, command); XCTAssertNotNil(coordinator.receipt); XCTAssertEqual(wire.writes.count, 1)
            let fields = try JSONDecoder().decode(MerchantBusinessValue.self, from: XCTUnwrap(wire.writes.first?.httpBody)).object
            XCTAssertEqual(fields?["content"], .string("Reviewed content")); XCTAssertFalse(wire.writes.contains { $0.url?.path.hasSuffix("/dispatch") == true })
        }
    }
    func testCampaignTitleOnlySourceAndOpaqueInvitationStayProductionDisabled() async throws {
        let c = try context(), wire = Wire(), command = MerchantEngagementCommand.dispatchCampaign(73001)
        let coordinator = coordinator(try reader(wire, command: command, current: { c }), journal: ReentrantJournal())
        try await confirm(coordinator, command); XCTAssertEqual(coordinator.failure, .disabled); XCTAssertTrue(wire.writes.isEmpty)
        XCTAssertThrowsError(try MerchantEngagementActionGrant(merchantID: 710, command: .acceptInvitation(.init(token: "opaque-invitation-token"))))
    }
    func testEvidenceUsesExactSelectionAndFreshCanRespond() async throws {
        let c = try context(), selection = try MerchantEvidenceSelection.importing(Data([137,80,78,71,13,10,26,10,0]))
        let command = MerchantEngagementCommand.uploadEvidence(try .init(64001), selection, scope: scope(c), merchantID: 710)
        let wire = Wire(), journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: command, current: { c }), journal: journal)
        try await confirm(coordinator, command); XCTAssertNotNil(coordinator.receipt)
        let request = try XCTUnwrap(wire.writes.first), body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(request.url?.path, "/api/common/uploadOSS"); XCTAssertTrue(body.range(of: selection.bytes) != nil)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("merchant_aftercare_evidence"))
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("name=\"refundId\"\r\n\r\n64001\r\n"))
        XCTAssertFalse(wire.writes.contains { $0.url?.path.hasSuffix("/respond") == true })
        let second = self.coordinator(try reader(wire, command: command, current: { c }), journal: ReentrantJournal())
        await second.prepare(command); let review = try XCTUnwrap(second.review); wire.canRespond = false; await second.confirm(review)
        XCTAssertEqual(wire.writes.count, 1); XCTAssertEqual(second.failure, .denied)
    }
    func testDownloadExactOriginTokenHeaderAndRejectsUnboundedPayload() async throws {
        let c = try context(), ticket = try MerchantExportTicket(creation: ["id": .int(74001), "status": .string("SUCCESS"), "rowCount": .int(7), "downloadToken": .string("export-test-token")])
        let command = MerchantEngagementCommand.downloadExport(ticket, scope: scope(c), merchantID: 710)
        for oversized in [false, true] {
            let wire = Wire(); if oversized { wire.binary = Data(repeating: 0, count: MerchantEngagementProductionFactory.maximumDownloadBytes + 1) }
            let journal = ReentrantJournal(), coordinator = coordinator(try reader(wire, command: command, current: { c }), journal: journal)
            try await confirm(coordinator, command)
            let request = try XCTUnwrap(wire.writes.first)
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/merchant/crm/exports/74001/download")
            XCTAssertNil(request.url?.query); XCTAssertEqual(request.value(forHTTPHeaderField: "X-CRM-Export-Token"), "export-test-token")
            XCTAssertEqual(request.httpMethod, "GET")
            if oversized { XCTAssertNil(coordinator.receipt); XCTAssertEqual(journal.rows.count, 1) }
            else { XCTAssertNotNil(coordinator.receipt); XCTAssertTrue(journal.rows.isEmpty) }
        }
    }
    func testContactAPIPermissionDoesNotGrantDeviceCopyAndConsumptionIsOneShot() async throws {
        let c = try context(), command = MerchantEngagementCommand.contact(try .init(61001), .copy)
        for allowed in [false, true] {
            let wire = Wire(), device = try MerchantEngagementDeviceGrant(merchantID: 710, action: .contact(.init(61001), .copy))
            let reader = try reader(wire, command: command, approval: approval(command, devices: allowed ? [device] : []), current: { c })
            let coordinator = coordinator(reader, journal: ReentrantJournal()), delivery = Delivery()
            try await confirm(coordinator, command)
            do { try await coordinator.consumeContact(using: delivery); XCTAssertTrue(allowed) } catch { XCTAssertFalse(allowed) }
            XCTAssertEqual(delivery.count, allowed ? 1 : 0)
            if allowed { do { try await coordinator.consumeContact(using: delivery); XCTFail() } catch {} }
        }
    }
    func testContactPermissionRevokedBeforeDeviceActionDoesNotDisclose() async throws {
        let c = try context(), command = MerchantEngagementCommand.contact(try .init(61001), .copy), wire = Wire()
        let device = try MerchantEngagementDeviceGrant(merchantID: 710, action: .contact(.init(61001), .copy))
        let coordinator = coordinator(try reader(wire, command: command, approval: approval(command, devices: [device]), current: { c }), journal: ReentrantJournal()), delivery = Delivery()
        try await confirm(coordinator, command); wire.permissions = []
        do { try await coordinator.consumeContact(using: delivery); XCTFail() } catch {}
        XCTAssertEqual(delivery.count, 0)
    }
    func testExportCreationIsOnlyRequestAndDoesNotDownloadOrSaveAutomatically() async throws {
        let c = try context(), command = MerchantEngagementCommand.createExport(.init()), wire = Wire()
        let coordinator = coordinator(try reader(wire, command: command, current: { c }), journal: ReentrantJournal())
        try await confirm(coordinator, command)
        XCTAssertNotNil(coordinator.exportTicket); XCTAssertEqual(coordinator.exportTicket?.task.status, "PENDING")
        XCTAssertEqual(wire.writes.count, 1); XCTAssertEqual(wire.writes.first?.url?.path, "/api/merchant/crm/exports")
        let allowed = await coordinator.authorizeExportSave(taskID: 74001); XCTAssertFalse(allowed)
    }
    func testContactDoubleTapWhileFreshAccessSuspendedDisclosesOnlyOnce() async throws {
        let c = try context(), command = MerchantEngagementCommand.contact(try .init(61001), .copy), wire = Wire()
        let device = try MerchantEngagementDeviceGrant(merchantID: 710, action: .contact(.init(61001), .copy))
        let coordinator = coordinator(try reader(wire, command: command, approval: approval(command, devices: [device]), current: { c }), journal: ReentrantJournal())
        let delivery = Delivery(), pause = PausedAccess()
        try await confirm(coordinator, command); wire.beforeAccess = { await pause.suspend() }
        let first = Task { try await coordinator.consumeContact(using: delivery) }; await pause.waitUntilStarted()
        do { try await coordinator.consumeContact(using: delivery); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure, .disabled) }
        pause.resume(); try await first.value; XCTAssertEqual(delivery.count, 1)
    }
    func testAllowedEvidenceDecisionRequiredEvenWhenCanRespondIsTrue() async throws {
        let c = try context(), selection = try MerchantEvidenceSelection.importing(Data([137,80,78,71,13,10,26,10,0]))
        let command = MerchantEngagementCommand.uploadEvidence(try .init(64001), selection, scope: scope(c), merchantID: 710), wire = Wire()
        wire.allowedEvidence = false
        let coordinator = coordinator(try reader(wire, command: command, current: { c }), journal: ReentrantJournal())
        try await confirm(coordinator, command); XCTAssertTrue(wire.writes.isEmpty); XCTAssertEqual(coordinator.failure, .denied)
    }
    @MainActor private final class PausedAccess {
        private var continuation: CheckedContinuation<Void, Never>?
        private var started: CheckedContinuation<Void, Never>?
        func suspend() async { await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
        func waitUntilStarted() async { if continuation != nil { return }; await withCheckedContinuation { started = $0 } }
        func resume() { continuation?.resume(); continuation = nil }
    }
    @MainActor private final class Delivery: MerchantContactDelivering {
        var count = 0
        func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws { count += 1 }
    }
    @MainActor private final class ReentrantJournal: MerchantBusinessIntentStore {
        let isDurable = true; var rows: [MerchantBusinessIntent] = []; var onReserve: (() -> Void)?
        func intents() throws -> [MerchantBusinessIntent] { rows }
        func reserve(_ intent: MerchantBusinessIntent) throws { guard !rows.contains(where: { $0.sameTarget(as: intent) }) else { throw MerchantBusinessFailure.pending }; rows.append(intent); onReserve?() }
        func complete(_ intent: MerchantBusinessIntent) throws { rows.removeAll { $0 == intent } }
    }
    /// This is deliberately ordinary HTTPTransport, never MerchantBusinessTestTransport.
    @MainActor private final class Wire: HTTPTransport {
        static var accessFields: MerchantBusinessObject { try! MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.access).object! }
        var merchantID = 710, accessCount = 0
        var permissions = Wire.accessFields["permissions"]!.array!
        var canRespond = true, allowedEvidence = true
        var beforeAccess: (() async -> Void)?
        var requests: [URLRequest] = [], writes: [URLRequest] = []
        var writeError: Error?, onWrite: (() -> Void)?
        var binary = MerchantEngagementSyntheticFixtures.workbookBytes
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path
            let isWrite = ["/api/merchant/crm/segments", "/api/merchant/crm/campaigns", "/api/merchant/crm/broadcast", "/api/merchant/crm/exports", "/api/merchant/crm/customers/61001/contact", "/api/common/uploadOSS", "/api/merchant/crm/campaigns/73001/dispatch"].contains(path) && request.httpMethod == "POST" || path.hasSuffix("/download")
            if isWrite { writes.append(request); onWrite?(); if let writeError { throw writeError } }
            if path.hasSuffix("/download") { return (binary, 200) }
            if path == "/api/common/uploadOSS" { return (Data(#"{"code":200,"fileName":"upload/merchant-aftercare-evidence/00000000000000000000000000000001.png"}"#.utf8), 200) }
            let value: MerchantBusinessValue
            switch path {
            case "/api/merchant/access/me":
                accessCount += 1; if let beforeAccess { await beforeAccess() }; var fields = Self.accessFields; fields["permissions"] = .array(permissions); fields["canManageOperators"] = .bool(permissions.contains(.string("merchant:operator:manage"))); fields["merchant"] = .object(["id": .int(merchantID)]); value = .object(fields)
            case "/api/merchant/crm/segments": value = request.httpMethod == "GET" ? try MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.segments) : .object(["id": .int(71002)])
            case "/api/merchant/crm/campaigns/preview": value = try MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.audience)
            case "/api/merchant/crm/broadcast/preview": value = try MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.broadcast)
            case "/api/merchant/crm/campaigns", "/api/merchant/crm/campaigns/73001": value = try MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.campaign)
            case "/api/merchant/crm/broadcast": value = .object(["id": .int(1), "status": .string("SUCCESS"), "audienceCount": .int(7), "consentedCount": .int(5), "noConsentCount": .int(2), "frequencySkippedCount": .int(1), "deliveredCount": .int(4), "failedCount": .int(0)])
            case "/api/merchant/crm/exports": value = .object(["id": .int(74001), "status": .string("PENDING"), "downloadToken": .string("export-test-token")])
            case "/api/merchant/crm/exports/74001/status": value = try MerchantEngagementSyntheticFixtures.decode(MerchantEngagementSyntheticFixtures.exportTask)
            case "/api/merchant/crm/customers/61001/detail": value = try MerchantEngagementSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.customer)
            case "/api/merchant/crm/customers/61001/contact": value = .object(["phone": .string("+1 (202) 555-0100")])
            case "/api/merchant/aftercare/detail": value = .object(["refundId": .int(64001), "processing": .string("WAITING_PLATFORM_REVIEW"), "merchantOpinion": .string("PENDING"), "canRespond": .bool(canRespond), "allowedDecisions": .array(canRespond ? [.string(allowedEvidence ? "EVIDENCE" : "AGREE")] : []), "responses": .array([]), "refunded": .bool(false)])
            default: throw URLError(.unsupportedURL)
            }
            return (try JSONEncoder().encode(MerchantBusinessValue.object(["code": .int(200), "data": value])), 200)
        }
    }
}
