import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftUI
@testable import Questify

@MainActor private final class IdentityJournal: OperationPendingJournal {
    var value: OperationPendingRecord?
    var unreadable = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if unreadable { throw PublishModesError.storage }
        return value.flatMap { $0.ownerKey == ownerKey && $0.targetKey == targetKey ? $0 : nil }
    }
    func write(_ record: OperationPendingRecord) throws {
        guard value == nil || value == record else { throw PublishModesError.uncertain }; value = record
    }
    func clear(_ record: OperationPendingRecord) throws { guard value == record else { throw PublishModesError.storage }; value = nil }
}
@MainActor private final class IdentityTransport: HTTPTransport {
    var paths: [String] = []
    var registered = false
    var loseWrite = false
    var failRead = false
    var badACK = false
    var code = 200
    var registeredValue: ProjectEditJSON?
    var onRead: (() async -> Void)?
    var onWrite: (() -> Void)?
    var bodyCheck: (([String: ProjectEditJSON]) throws -> Void)?
    var writes: Int { paths.filter { $0 == "/api/publisher/identity" }.count }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""; paths.append(path)
        if path.hasSuffix("/status") {
            if let onRead { await onRead() }
            if failRead { throw URLError(.networkConnectionLost) }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(["registered": registeredValue ?? .bool(registered)])]), 200)
        }
        try bodyCheck?(JSONDecoder().decode([String: ProjectEditJSON].self, from: request.httpBody ?? Data()))
        onWrite?()
        if loseWrite { throw URLError(.networkConnectionLost) }
        if code == 200 && !badACK { registered = true }
        return (try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(code)), "data": .object(["registered": badACK ? .string("true") : .bool(true)])]), 200)
    }
}
@MainActor private final class IdentityHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://identity.example.test")!)
    let session: PublishingSession
    var credentials: PublishingCredentials?
    let transport = IdentityTransport()
    let journal = IdentityJournal()
    var grants = PublisherIdentityRegistrationGrants()
    init(approved: Bool = true, role: String = "club", region: PublishingRegion = .china) throws {
        session = PublishingSession(namespace: "identity-tests", accountID: 7, epoch: UUID(), role: role, region: region)
        credentials = try PublishingCredentials(session: session, token: "synthetic-identity-token")
        if approved {
            grants = try PublisherIdentityRegistrationGrants(
                read: OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [PublisherIdentityRegistrationWire.statusPath]),
                register: OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [PublisherIdentityRegistrationWire.registerPath]))
        }
    }
    func service() -> PublisherIdentityRegistrationService {
        PublisherIdentityRegistrationService(configuration: configuration, transport: transport, grants: grants,
            journal: journal, session: session, credentials: { [weak self] in self?.credentials })
    }
    // Deliberately nonexistent region prefix; generated checksum fixture, not a person's identifier.
    var syntheticID: String {
        let digits = Array("00000020000101000"), weights = [7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2]
        let sum = (0..<17).reduce(0) { $0 + digits[$1].wholeNumberValue! * weights[$1] }
        return String(digits) + String(Array("10X98765432")[sum % 11])
    }
    func prepare(_ service: PublisherIdentityRegistrationService, consent: Bool = true) throws -> PublishingAuxiliaryReview {
        try service.prepare(name: "演示", idCard: syntheticID, consent: consent, currentYear: 2026)
    }
}

@MainActor final class PublisherIdentityRegistrationOwnerTests: XCTestCase {
    private func makeOwner(_ h: IdentityHarness) async -> PublisherIdentityRegistrationOwner {
        let owner = PublisherIdentityRegistrationOwner()
        owner.bind(account: h.session, draftID: UUID(), draft: .init()); owner.appear(active: true)
        await owner.begin(service: h.service(), expected: owner.actionID); return owner
    }
    private func fill(_ owner: PublisherIdentityRegistrationOwner, _ h: IdentityHarness) {
        owner.textBinding(nameField: true).wrappedValue = "演示"
        owner.textBinding(nameField: false).wrappedValue = h.syntheticID
        owner.consentBinding().wrappedValue = true
    }
    private func submit(_ owner: PublisherIdentityRegistrationOwner) async {
        await owner.submit(currentYear: 2026, expected: owner.actionID)
    }
    func testNormalFirstOpeningReadsOnlyStatusWithoutChangingOriginalDraft() async throws {
        let h = try IdentityHarness(); var draft = ActivityPublishDraft(); draft.name = "Unsaved original e\u{301}"
        let original = ProjectEditPendingMaterials.exactData(draft), id = UUID(), owner = PublisherIdentityRegistrationOwner()
        owner.bind(account: h.session, draftID: id, draft: draft); owner.appear(active: true)
        await owner.begin(service: h.service(), expected: owner.actionID)
        XCTAssertTrue(owner.open); XCTAssertEqual(owner.status, .unregistered); XCTAssertTrue(owner.canEdit)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), original); XCTAssertEqual(h.transport.writes, 0)
    }
    func testExplicitSubmissionAcknowledgmentFreshReadClearsInputsAndReturnsToSameDraft() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); await submit(owner)
        XCTAssertEqual(owner.status, .registered); XCTAssertTrue(owner.confirmedRegistered)
        XCTAssertEqual(h.transport.paths, ["/api/publisher/identity/status", "/api/publisher/identity/status", "/api/publisher/identity", "/api/publisher/identity/status"])
        XCTAssertEqual(owner.name, ""); XCTAssertEqual(owner.idCard, ""); XCTAssertFalse(owner.consent)
        owner.close(owner.actionID); XCTAssertFalse(owner.open); XCTAssertEqual(h.transport.writes, 1)
        XCTAssertTrue(owner.confirmedRegistered)
    }
    func testCancelClearsSensitiveValuesButDoesNotWrite() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h)
        owner.close(owner.actionID); XCTAssertEqual(owner.name, ""); XCTAssertEqual(owner.idCard, ""); XCTAssertFalse(owner.consent)
        XCTAssertEqual(h.transport.writes, 0)
    }
    func testExplicitRejectionRetainsUserControlledTemporaryValuesUntilLeaving() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); h.transport.code = 500
        await submit(owner); XCTAssertEqual(owner.status, .rejected); XCTAssertEqual(owner.name, "演示"); XCTAssertEqual(owner.idCard, h.syntheticID)
        owner.disappear(); XCTAssertEqual(owner.name, ""); XCTAssertEqual(owner.idCard, ""); XCTAssertFalse(owner.open)
    }
    func testUnknownRetainsMarkerAcrossCloseAndNewOwnerWithoutResubmitting() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); h.transport.loseWrite = true
        await submit(owner); XCTAssertEqual(owner.status, .unknown); XCTAssertTrue(owner.uncertain); XCTAssertFalse(owner.canEdit)
        let marker = h.journal.value; owner.close(owner.actionID); let next = await makeOwner(h)
        XCTAssertEqual(next.status, .unknown); XCTAssertFalse(next.canEdit); await submit(next)
        XCTAssertEqual(h.transport.writes, 1); XCTAssertEqual(h.journal.value, marker)
    }
    func testUnknownRegisteredReadbackCannotClaimOriginalAcknowledgmentOrClearMarker() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); h.transport.loseWrite = true
        await submit(owner); let marker = h.journal.value; h.transport.registered = true
        await owner.refresh(expected: owner.actionID); XCTAssertEqual(owner.status, .registered)
        XCTAssertTrue(owner.uncertain); XCTAssertEqual(h.journal.value, marker); XCTAssertEqual(h.transport.writes, 1)
    }
    func testAcknowledgmentWithFailedReadbackCannotEnableAnotherSubmission() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h)
        h.transport.onWrite = { h.transport.failRead = true }; await submit(owner)
        XCTAssertEqual(owner.status, .acknowledgedReadFailed); XCTAssertFalse(owner.canEdit); XCTAssertEqual(owner.idCard, "")
        await submit(owner); XCTAssertEqual(h.transport.writes, 1)
        h.transport.failRead = false; h.transport.registered = false
        await owner.refresh(expected: owner.actionID); XCTAssertEqual(owner.status, .acknowledgedReadFailed); XCTAssertFalse(owner.canEdit)
    }
    func testOldBindingsCannotReadOrChangeReopenedSensitiveInput() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h)
        let oldName = owner.textBinding(nameField: true), oldID = owner.textBinding(nameField: false), oldConsent = owner.consentBinding()
        owner.close(owner.actionID); await owner.begin(service: h.service(), expected: owner.actionID); fill(owner, h)
        XCTAssertEqual(oldName.wrappedValue, ""); XCTAssertEqual(oldID.wrappedValue, ""); XCTAssertFalse(oldConsent.wrappedValue)
        oldName.wrappedValue = "Wrong"; oldID.wrappedValue = "Wrong"; oldConsent.wrappedValue = false
        XCTAssertEqual(owner.name, "演示"); XCTAssertEqual(owner.idCard, h.syntheticID); XCTAssertTrue(owner.consent)
    }
    func testOldCloseRefreshAndSubmitCannotConsumeNewVisit() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h), old = owner.actionID
        owner.close(old); await owner.begin(service: h.service(), expected: owner.actionID); fill(owner, h)
        let count = h.transport.paths.count
        owner.close(old); await owner.refresh(expected: old); await owner.submit(currentYear: 2026, expected: old)
        XCTAssertTrue(owner.open); XCTAssertEqual(owner.name, "演示"); XCTAssertEqual(h.transport.paths.count, count)
    }
    func testOldOpenCannotRestartAfterDraftReplacement() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); owner.close(owner.actionID); let old = owner.actionID
        owner.bind(account: h.session, draftID: UUID(), draft: .init())
        let count = h.transport.paths.count; await owner.begin(service: h.service(), expected: old)
        XCTAssertFalse(owner.open); XCTAssertEqual(h.transport.paths.count, count)
    }
    func testDraftByteChangeRetiresInputAndOldBinding() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); let old = owner.textBinding(nameField: true)
        var draft = ActivityPublishDraft(); draft.description = "Changed"
        owner.bind(account: h.session, draftID: UUID(), draft: draft)
        XCTAssertFalse(owner.open); XCTAssertEqual(owner.name, ""); XCTAssertEqual(old.wrappedValue, "")
    }
    func testAccountChangeClearsAndRejectsOldOwner() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); let old = owner.textBinding(nameField: false)
        h.credentials = nil; owner.bind(account: nil, draftID: UUID(), draft: .init())
        XCTAssertEqual(owner.idCard, ""); XCTAssertEqual(old.wrappedValue, ""); await submit(owner); XCTAssertEqual(h.transport.writes, 0)
    }
    func testBackgroundClearsAndForegroundDoesNotReopen() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h)
        owner.setActive(false); XCTAssertEqual(owner.idCard, ""); XCTAssertEqual(owner.name, ""); XCTAssertFalse(owner.open)
        let count = h.transport.paths.count; owner.setActive(true); XCTAssertFalse(owner.open); XCTAssertEqual(h.transport.paths.count, count)
    }
    func testHiddenForegroundCannotStartAnyRead() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); owner.disappear(); owner.setActive(false); owner.setActive(true)
        let count = h.transport.paths.count; await owner.begin(service: h.service(), expected: owner.actionID)
        XCTAssertFalse(owner.open); XCTAssertEqual(h.transport.paths.count, count)
    }
    func testCloseDuringPreflightDoesNotDispatchAndKeepsInputCleared() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h)
        h.transport.onRead = { owner.close(owner.actionID) }; await submit(owner)
        XCTAssertFalse(owner.open); XCTAssertEqual(owner.idCard, ""); XCTAssertEqual(h.transport.writes, 0)
    }
    func testLateAcknowledgmentAfterExitCannotPublishRegisteredState() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h)
        h.transport.onWrite = { owner.disappear() }; await submit(owner)
        XCTAssertFalse(owner.open); XCTAssertFalse(owner.confirmedRegistered); XCTAssertEqual(owner.name, "")
        XCTAssertNotNil(h.journal.value)
    }
    func testDefaultOffAndUnreadableStatusDoNotEnableInput() async throws {
        let h = try IdentityHarness(approved: false), owner = await makeOwner(h)
        XCTAssertEqual(owner.status, .unavailable); XCTAssertFalse(owner.canEdit); XCTAssertTrue(h.transport.paths.isEmpty)
        let active = try IdentityHarness(); active.transport.failRead = true; let failed = await makeOwner(active)
        XCTAssertEqual(failed.status, .failed); XCTAssertFalse(failed.canEdit); XCTAssertEqual(active.transport.writes, 0)
    }
    func testRepeatedVisibleAppearDoesNotEraseInProgressInput() async throws {
        let h = try IdentityHarness(), owner = await makeOwner(h); fill(owner, h); let stamp = owner.actionID
        owner.appear(active: true); XCTAssertEqual(owner.actionID, stamp); XCTAssertEqual(owner.idCard, h.syntheticID)
    }

    private func composition() throws -> (CompositionHTTPTransport, IdentityTransport, PublishingSession, PublisherIdentityRegistrationGrants, APIConfiguration) {
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://identity.example.test",
            approvedBaseURLs: [.china: ["https://identity.example.test"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.identity.registration", realm: "synthetic")
        let api = try APIConfiguration(baseURL: URL(string: "https://identity.example.test")!)
        let session = PublishingSession(namespace: deployment.storageScope.service, accountID: 7, epoch: UUID(), role: "club", region: .china)
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.namespace, accountID: 7,
            paths: [PublisherIdentityRegistrationWire.statusPath, PublisherIdentityRegistrationWire.registerPath])
        let grants = PublisherIdentityRegistrationGrants(read: approval, register: approval), underlying = IdentityTransport()
        let root = CompositionHTTPTransport(deployment: deployment, underlying: underlying)
        root.current = { .init(epoch: 3, accountID: 7, role: "club", token: "synthetic-identity-token") }
        return (root, underlying, session, grants, api)
    }
    func testTypedProductionCompositionDefaultsClosedAndNeedsOwnSelector() async throws {
        let (root, underlying, session, grants, api) = try composition()
        let request = try OperationAdapterHTTP.json(configuration: api, path: PublisherIdentityRegistrationWire.statusPath,
            body: Data("{}".utf8), token: "synthetic-identity-token")
        do { _ = try await root.sendPublisherIdentityRegistration(request, session: session, grants: grants); XCTFail() } catch {}
        XCTAssertTrue(underlying.paths.isEmpty)
        root.publisherIdentityRegistrationApproval = { _ in grants }
        _ = try await root.sendPublisherIdentityRegistration(request, session: session, grants: grants)
        XCTAssertEqual(underlying.paths, ["/api/publisher/identity/status"])
    }
    func testTypedCompositionPreservesLiveSelectorThroughCloneAndRevocation() async throws {
        let (root, underlying, session, grants, api) = try composition(); root.publisherIdentityRegistrationApproval = { _ in grants }
        let clone = root.replacingUnderlying(underlying)
        let request = try OperationAdapterHTTP.json(configuration: api, path: PublisherIdentityRegistrationWire.statusPath,
            body: Data("{}".utf8), token: "synthetic-identity-token")
        _ = try await clone.sendPublisherIdentityRegistration(request, session: session, grants: grants)
        root.publisherIdentityRegistrationApproval = { _ in .init() }
        do { _ = try await clone.sendPublisherIdentityRegistration(request, session: session, grants: grants); XCTFail() } catch {}
        XCTAssertEqual(underlying.paths.count, 1)
    }
    func testTypedCompositionRejectsNewGrantRevisionAndWrongAccount() async throws {
        let (root, underlying, session, grants, api) = try composition()
        root.publisherIdentityRegistrationApproval = { _ in .init(read: grants.read, register: grants.register) }
        let request = try OperationAdapterHTTP.json(configuration: api, path: PublisherIdentityRegistrationWire.statusPath,
            body: Data("{}".utf8), token: "synthetic-identity-token")
        do { _ = try await root.sendPublisherIdentityRegistration(request, session: session, grants: grants); XCTFail() } catch {}
        root.publisherIdentityRegistrationApproval = { _ in grants }; root.current = { .init(epoch: 4, accountID: 8, role: "club", token: "synthetic-identity-token") }
        do { _ = try await root.sendPublisherIdentityRegistration(request, session: session, grants: grants); XCTFail() } catch {}
        XCTAssertTrue(underlying.paths.isEmpty)
    }
    func testTypedCompositionRunsExplicitSubmissionButGenericRegistrationRemainsClosed() async throws {
        let (root, underlying, session, grants, api) = try composition(); root.publisherIdentityRegistrationApproval = { _ in grants }
        let credentials = try PublishingCredentials(session: session, token: "synthetic-identity-token")
        let journal = IdentityJournal(), h = try IdentityHarness()
        let service = PublisherIdentityRegistrationService(configuration: api, transport: root, grants: grants, journal: journal,
            session: session, credentials: { credentials }); service.activate()
        let review = try service.prepare(name: "演示", idCard: h.syntheticID, consent: true, currentYear: 2026)
        let result = await service.submit(review); guard case .acknowledged = result else { return XCTFail() }
        XCTAssertEqual(underlying.writes, 1); XCTAssertNil(journal.value)
        let request = try OperationAdapterHTTP.json(configuration: api, path: review.request.path,
            body: JSONEncoder().encode(review.request.fields), token: "synthetic-identity-token")
        do { _ = try await root.send(request); XCTFail() } catch {}
        XCTAssertEqual(underlying.writes, 1)
    }
}
