import Foundation
import XCTest
@testable import Questify

@MainActor final class ProfileParticipantHostRecoveryTests: XCTestCase {
    func setup() async throws -> (ParticipantHostSpecimen, AppSession) {
        let h = try ParticipantHostSpecimen(); addTeardownBlock { @MainActor in h.cleanup() }
        let session = await h.login(); h.install(session, writes: true); return (h, session)
    }
    func testOriginalCreateUnknownReadbackRetryAndSameUUID() async throws {
        let (h, session) = try await setup()
        let model = ParticipantFormModel(id: nil, reader: session.participantReader, coordinator: session.participantCoordinator)
        await model.load(); model.draft = ParticipantHostSpecimen.draft(); model.prepareSave()
        let original = try XCTUnwrap(model.originalCreateRetry)
        h.wire.failAddress = true
        let completed = await model.confirmMutation(); XCTAssertFalse(completed)
        XCTAssertTrue(model.showsOwnedUnknown); XCTAssertTrue(model.canRetryOriginalCreate)
        h.wire.failAddress = false
        await model.readBack(); XCTAssertTrue(model.showsOwnedUnknown); XCTAssertFalse(model.canMutate)
        let recovered = await model.retryOriginalCreate(); XCTAssertTrue(recovered)
        let creates = h.wire.addressRequests.filter { $0.url?.path.hasSuffix("/action") == true }
        XCTAssertEqual(creates.count, 2)
        for request in creates {
            let text = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            XCTAssertTrue(text.contains(original.requestID.uuidString.lowercased()))
        }
        XCTAssertEqual(session.participantCoordinator.savedParticipant?.id, 9)
    }
    func testNilCreateACKDoesNotAutoSelectOrClaimSuccess() async throws {
        let (h, session) = try await setup(); h.wire.missingCreateRow = true
        let model = ParticipantFormModel(id: nil, reader: session.participantReader, coordinator: session.participantCoordinator)
        await model.load(); model.draft = ParticipantHostSpecimen.draft(); model.prepareSave()
        let result = await model.confirmMutation(); XCTAssertFalse(result)
        XCTAssertTrue(model.showsOwnedUnknown); XCTAssertNil(session.participantCoordinator.savedParticipant)
        XCTAssertEqual(h.wire.addressRequests.count, 1)
    }
    func testGrantWithdrawalAfterDispatchKeepsUnknownAndCurrentReadNeedsOnlyReadGrant() async throws {
        let (h, session) = try await setup(), coordinator = session.participantCoordinator
        let review = try coordinator.prepare(.delete(id: 9), expectedIdentity: try XCTUnwrap(session.participantReader.identity))
        h.wire.onAddress = { h.access?.revoke() }
        _ = await coordinator.confirm(review); h.wire.onAddress = nil
        if case .outcomeUnknown = coordinator.state {} else { XCTFail() }
        XCTAssertFalse(session.participantReader.isConfigured); XCTAssertEqual(h.wire.addressRequests.count, 1)
        h.install(session, writes: false)
        XCTAssertTrue(coordinator === session.participantCoordinator)
        _ = await coordinator.readBackUncertainOutcome()
        if case .received(.list) = coordinator.readbackState {} else { XCTFail() }
        if case .outcomeUnknown = coordinator.state {} else { XCTFail() }
        XCTAssertFalse(coordinator.canPrepare); XCTAssertEqual(h.wire.addressRequests.count, 2)
        let model = ParticipantFormModel(id: 9, reader: session.participantReader, coordinator: coordinator)
        await model.load(); XCTAssertTrue(model.showsOwnedUnknown); XCTAssertTrue(model.canReadBack)
        await model.readBack(); model.disappear()
        XCTAssertEqual(coordinator.readbackState, .idle)
        session.participantAccessSelector = { _ in nil }
        await model.load(); XCTAssertTrue(model.showsOwnedUnknown); XCTAssertFalse(model.canReadBack)
        XCTAssertFalse(coordinator.isConfigured); XCTAssertEqual(h.wire.addressRequests.count, 3)
    }
    func testNilThenSameGrantCannotReviveOldConfirmationOrPayload() async throws {
        let (h, session) = try await setup(), coordinator = session.participantCoordinator
        let originalGrant = try XCTUnwrap(h.access), identity = try XCTUnwrap(session.participantReader.identity)
        let review = try coordinator.prepare(.save(ParticipantHostSpecimen.draft()), expectedIdentity: identity)
        session.participantAccessSelector = { _ in nil }
        session.participantAccessSelector = { _ in originalGrant }
        XCTAssertNotEqual(identity, session.participantReader.identity)
        _ = await coordinator.confirm(review); XCTAssertTrue(h.wire.addressRequests.isEmpty)
        let second = try coordinator.prepare(.save(ParticipantHostSpecimen.draft()), expectedIdentity: try XCTUnwrap(session.participantReader.identity))
        let retry = try XCTUnwrap(ParticipantOriginalCreateRetry(confirmation: second))
        h.wire.failAddress = true; _ = await coordinator.confirm(second)
        session.participantAccessSelector = { _ in nil }; session.participantAccessSelector = { _ in originalGrant }
        XCTAssertFalse(coordinator.canRetryOriginalCreate(retry)); XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(h.wire.addressRequests.count, 1)
    }
    func testBackgroundAndLeaveDoNotReplayAndSameOwnerReloginRetainsOnlyMemoryLock() async throws {
        let (h, session) = try await setup()
        let model = ParticipantFormModel(id: nil, reader: session.participantReader, coordinator: session.participantCoordinator)
        await model.load(); model.draft = ParticipantHostSpecimen.draft(); model.prepareSave()
        h.wire.failAddress = true; _ = await model.confirmMutation()
        model.suspendOriginalCreateRetry(); XCTAssertNotNil(model.originalCreateRetry)
        XCTAssertEqual(h.wire.addressRequests.count, 1)
        model.disappear(); XCTAssertNil(model.originalCreateRetry); XCTAssertTrue(model.draft.fullName.isEmpty)
        await session.logout(); XCTAssertNil(session.participantReader.identity)
        h.wire.failAddress = false
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        h.install(session, writes: true)
        if case .outcomeUnknown = session.participantCoordinator.state {} else { XCTFail() }
        XCTAssertFalse(session.participantCoordinator.canPrepare)
        let restarted = await h.login(); h.install(restarted, writes: true)
        XCTAssertEqual(restarted.participantCoordinator.state, .idle) // No durable claim or automatic replay.
    }
    func testChangedOwnerDiscardsLate401WithoutExpiringReplacement() async throws {
        let h = try ParticipantHostSpecimen(); addTeardownBlock { @MainActor in h.cleanup() }
        let original = RuntimeDependencyContext(market: .china, baseURL: ParticipantHostSpecimen.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: h.namespace, token: "synthetic-participant-7"))
        let replacement = RuntimeDependencyContext(market: .china, baseURL: original.baseURL, role: "player",
            session: try .init(accountID: 8, epoch: 2, namespace: h.namespace, token: "synthetic-replacement"))
        var current: RuntimeDependencyContext? = original
        let access = try ProfileParticipantAccess(context: original, permitsWrites: true, expiresAt: Date().addingTimeInterval(60))
        var expirations = 0
        let host = ProfileParticipantHost(current: { current }, viewer: { 1 }, access: { _ in access },
            makeTransport: { owner, issued, valid in
                ProfileParticipantTransport(context: owner, access: issued, underlying: h.wire, current: { current }, stillCurrent: valid)
            }, unauthorized: { _, _ in expirations += 1 })
        let review = try host.coordinator.prepare(.delete(id: 9), expectedIdentity: try XCTUnwrap(host.reader.identity))
        h.wire.status = 401; h.wire.onAddress = { current = replacement }
        _ = await host.coordinator.confirm(review)
        XCTAssertEqual(expirations, 0); XCTAssertEqual(host.coordinator.state, .idle)
        XCTAssertEqual(host.coordinator.readbackState, .idle)
        current = original; host.coordinator.synchronizeSession()
        if case .outcomeUnknown = host.coordinator.state {} else { XCTFail() }
        XCTAssertFalse(host.coordinator.canPrepare); XCTAssertEqual(h.wire.addressRequests.count, 1)
    }
    func testRegistrationParticipantRevisionDoesNotReplaceOriginalRegistrationIdentityOrGrant() async throws {
        let (h, session) = try await setup()
        let owner = try XCTUnwrap(session.profileReader.identity), participant = try XCTUnwrap(session.participantReader.identity)
        XCTAssertNotEqual(owner, participant)
        let endpoint = try OperationEndpointApproval(baseURL: ParticipantHostSpecimen.base,
            namespace: h.namespace, accountID: owner.accountID, paths: RegistrationProductionApproval.registrationPaths)
        let grant = try RegistrationProductionApproval(endpoint: endpoint, identity: owner, market: .china, storefront: "CHN",
            product: .physicalActivity, activityID: 7, ticketIDs: [11], consentVersion: "test-v1",
            noticeURL: URL(string: "https://example.com/notice")!, expiresAt: Date().addingTimeInterval(60))
        let activity = try JSONDecoder().decode(ActivityDetail.self,
            from: Data(#"{"id":7,"name":"Synthetic","omsTicketList":[{"id":11,"name":"Ticket","price":1,"remainingInventory":4}]}"#.utf8))
        let registration = RegistrationCoordinator(service: ParticipantRegistrationNoWrite())
        try registration.setAccount(id: owner.accountID, token: "synthetic-participant-7")
        let flow = RegistrationUIFlow(activity: activity, coordinator: registration, participantReader: session.participantReader,
            currentIdentity: { session.profileReader.identity }, creationPolicy: .approved(grant))
        flow.open(); await flow.loadParticipants()
        XCTAssertEqual(flow.identity, owner); XCTAssertEqual(flow.participantsState, .received)
        XCTAssertTrue(flow.participantProjectionIsCurrent)
        XCTAssertTrue(grant.permits(identity: flow.identity, activityID: 7, ticketID: 11, now: Date()))
        XCTAssertFalse(grant.permits(identity: participant, activityID: 7, ticketID: 11, now: Date()))
        let row = try await session.participantReader.profileParticipant(id: 9)
        await flow.selectCreatedParticipant(row, identity: participant)
        XCTAssertEqual(flow.selectedParticipantID, 9)
        h.access?.revoke(); flow.synchronizeParticipantIdentity()
        XCTAssertFalse(flow.participantProjectionIsCurrent); XCTAssertTrue(flow.participants.isEmpty)
        XCTAssertTrue(flow.draft.realName.isEmpty); XCTAssertTrue(flow.draft.phone.isEmpty)
        XCTAssertEqual(flow.identity, owner); XCTAssertTrue(flow.hasCurrentSession)
        XCTAssertTrue(grant.permits(identity: flow.identity, activityID: 7, ticketID: 11, now: Date()))
    }
}
private struct ParticipantRegistrationNoWrite: RegistrationCoordinatingService {
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote { throw APIError.notConfigured }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult { XCTFail("Participant capability must not create registrations"); throw APIError.notConfigured }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot { throw APIError.notConfigured }
}
