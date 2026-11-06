import Foundation
import XCTest
@testable import Questify

@MainActor final class NativeWebhookVisitBindingTests: XCTestCase {
    private func makeOwner(provider: NativeWebhookAppFixtureProvider,
        transport: NativeWebhookAppFixtureTransport, journal: NativeWebhookAppFixtureJournal) -> NativeWebhookCoordinator {
        NativeWebhookCoordinator(service: NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport),
            provider: provider, journal: NativeWebhookPendingJournal(journal: journal))
    }
    func testConstructionAndBindingDoNotReadOrCreateCredential() throws {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
        let journal = NativeWebhookAppFixtureJournal(), visit = NativeWebhookRuntimeVisit()
        let owner = makeOwner(provider: provider, transport: transport, journal: journal)
        XCTAssertTrue(visit.bind(owner)); XCTAssertTrue(visit.isCurrent)
        XCTAssertTrue(transport.requests.isEmpty); XCTAssertNil(owner.credential); XCTAssertNil(journal.record)
    }
    func testRetainedVisitDoesNotKeepDeallocatedOwnerAlive() throws {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
        let journal = NativeWebhookAppFixtureJournal(), visit = NativeWebhookRuntimeVisit()
        var owner: NativeWebhookCoordinator? = makeOwner(provider: provider, transport: transport, journal: journal)
        XCTAssertTrue(visit.bind(try XCTUnwrap(owner)))
        weak var weakOwner = owner
        owner = nil
        XCTAssertNil(weakOwner); XCTAssertFalse(visit.isCurrent)
    }
    func testLeaveAndBackgroundRetireSynchronouslyWithoutDeletingPending() throws {
        for background in [false, true] {
            let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
            let journal = NativeWebhookAppFixtureJournal(), visit = NativeWebhookRuntimeVisit()
            let owner = makeOwner(provider: provider, transport: transport, journal: journal)
            let original = OperationPendingRecord(ownerKey: "synthetic-owner", targetKey: "synthetic-original")
            journal.record = original
            XCTAssertTrue(visit.bind(owner))
            if background { owner.background() } else { owner.leave() }
            XCTAssertFalse(visit.isCurrent); XCTAssertEqual(journal.record, original)
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }
    func testFalseParentCannotReviveOldVisitAfterItReturns() throws {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
        let journal = NativeWebhookAppFixtureJournal(), visit = NativeWebhookRuntimeVisit()
        let owner = makeOwner(provider: provider, transport: transport, journal: journal)
        var parent = true
        XCTAssertTrue(visit.bind(owner)); owner.restrictPresentation { parent }
        XCTAssertTrue(visit.isCurrent)
        parent = false; XCTAssertFalse(visit.isCurrent)
        parent = true; XCTAssertFalse(visit.isCurrent)
    }
    func testAlreadyBoundOwnerCannotSilentlyBypassVisitRetirement() throws {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
        let owner = makeOwner(provider: provider, transport: transport, journal: NativeWebhookAppFixtureJournal())
        XCTAssertTrue(owner.bindRuntimeRetirement({}))
        let visit = NativeWebhookRuntimeVisit()
        XCTAssertFalse(visit.bind(owner)); XCTAssertFalse(visit.isCurrent)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testForegroundBuildsFreshOwnerAndOnlyPerformsReads() async throws {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
        let journal = NativeWebhookAppFixtureJournal()
        var owners: [NativeWebhookCoordinator] = [], visits: [NativeWebhookRuntimeVisit] = []
        let model = NativeWebhookViewModel(makeCoordinator: {
            let owner = self.makeOwner(provider: provider, transport: transport, journal: journal)
            let visit = NativeWebhookRuntimeVisit(); XCTAssertTrue(visit.bind(owner))
            owners.append(owner); visits.append(visit); return owner
        })
        await model.start(); XCTAssertEqual(owners.count, 1)
        model.background(); XCTAssertFalse(visits[0].isCurrent)
        await model.foreground()
        XCTAssertEqual(owners.count, 2); XCTAssertFalse(owners[0] === owners[1])
        XCTAssertFalse(visits[0].isCurrent); XCTAssertTrue(visits[1].isCurrent)
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertNil(model.sheet); XCTAssertNil(owners[1].credential)
    }
    func testFamilySwitchClearsSecretsWithoutRetiringLiveVisit() async throws {
        let provider = try NativeWebhookAppFixtureProvider(), transport = NativeWebhookAppFixtureTransport()
        let journal = NativeWebhookAppFixtureJournal(), visit = NativeWebhookRuntimeVisit()
        let owner = makeOwner(provider: provider, transport: transport, journal: journal)
        XCTAssertTrue(visit.bind(owner))
        let model = NativeWebhookViewModel(makeCoordinator: { owner })
        await model.start()
        // Same-family no-op must not be mistaken for app background.
        await model.switchFamily(.subscription)
        XCTAssertTrue(visit.isCurrent); XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
}
