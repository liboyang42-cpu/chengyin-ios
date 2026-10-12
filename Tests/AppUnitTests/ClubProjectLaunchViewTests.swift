import XCTest
@testable import Questify

@MainActor final class ClubProjectLaunchViewTests: XCTestCase {
    private func permit(_ m: ClubProjectLaunchModel, _ f: LaunchFixture) throws -> ClubProjectLaunchModel.Permit { try XCTUnwrap(m.activate(f.context)) }
    private func read(_ m: ClubProjectLaunchModel, _ f: LaunchFixture, _ p: ClubProjectLaunchModel.Permit, _ product: ProjectEditProduct? = nil) async -> ClubProjectLaunchTarget? {
        await m.read(p, product: product, reader: f.reader, editorContextID: { f.editorID })
    }
    func testInitialReadIsNotAnEditorLaunch() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        let target = await read(m, f, p); XCTAssertNil(target); XCTAssertNil(m.target); XCTAssertEqual(m.phase, .ready); XCTAssertEqual(f.reader.reads, 1)
    }
    func testModeChoiceReadsFreshOwnerAgainAndUsesExactSeed() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        _ = await read(m, f, p); let result = await read(m, f, p, .freeExplore), target = try XCTUnwrap(result)
        XCTAssertEqual(f.reader.reads, 2); XCTAssertEqual(target.seed.clubID, 81); XCTAssertEqual(target.seed.product, .freeExplore)
        XCTAssertTrue(m.isCurrent(target, context: f.context, reader: f.reader, editorContextID: f.editorID))
    }
    func testOwnerLossOrWrongClubCannotReachEditor() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        f.reader.club = LaunchReader.record(owner: false); _ = await read(m, f, p, .city); XCTAssertEqual(m.phase, .denied); XCTAssertNil(m.target)
        f.reader.club = LaunchReader.record(id: 82); _ = await read(m, f, p, .city); XCTAssertEqual(m.phase, .denied); XCTAssertNil(m.target)
    }
    func testFailureAndRetryDoNotManufactureDraft() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        f.reader.failure = true; _ = await read(m, f, p, .city); XCTAssertEqual(m.phase, .failed); XCTAssertNil(m.target)
        f.reader.failure = false; _ = await read(m, f, p); XCTAssertEqual(m.phase, .ready); XCTAssertNil(m.target)
    }
    func testCancelAndOldRetryCannotReadOrLaunch() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        m.leave(); _ = try permit(m, f); _ = await read(m, f, p, .city)
        XCTAssertEqual(f.reader.reads, 0); XCTAssertNil(m.target)
    }
    func testAccountSwitchDuringHeldReadCannotLaunch() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        f.reader.held = true; let entered = expectation(description: "owner"); f.reader.entered = { entered.fulfill() }
        let task = Task { await self.read(m, f, p, .city) }; await fulfillment(of: [entered], timeout: 1)
        f.reader.clubIdentity = .init(accountID: 702, epoch: 2); f.reader.pending[0].resume(returning: f.reader.club)
        let result = await task.value; XCTAssertNil(result); XCTAssertNil(m.target)
    }
    func testEditorConfigurationChangeDuringHeldReadCannotLaunch() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        f.reader.held = true; let entered = expectation(description: "owner"); f.reader.entered = { entered.fulfill() }
        let task = Task { await self.read(m, f, p, .city) }; await fulfillment(of: [entered], timeout: 1)
        f.editorID = "new-config"; f.reader.pending[0].resume(returning: f.reader.club)
        let result = await task.value; XCTAssertNil(result); XCTAssertNil(m.target)
    }
    func testLatestModeWinsAgainstOlderNonCancellingRead() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        f.reader.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        f.reader.entered = { f.reader.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await self.read(m, f, p, .city) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await self.read(m, f, p, .freeExplore) }; await fulfillment(of: [second], timeout: 1)
        f.reader.pending[1].resume(returning: f.reader.club); _ = await new.value
        f.reader.pending[0].resume(returning: f.reader.club); let oldResult = await old.value
        XCTAssertNil(oldResult); XCTAssertEqual(m.target?.seed.product, .freeExplore)
    }
    func testCancellationClearsLoadingAndReturnReadClearsTarget() async throws {
        let f = LaunchFixture(), m = ClubProjectLaunchModel(), p = try permit(m, f)
        f.reader.held = true; let entered = expectation(description: "owner"); f.reader.entered = { entered.fulfill() }
        let task = Task { await self.read(m, f, p, .city) }; await fulfillment(of: [entered], timeout: 1)
        task.cancel(); f.reader.pending[0].resume(returning: f.reader.club); _ = await task.value
        XCTAssertEqual(m.phase, .idle); XCTAssertNil(m.target)
        f.reader.held = false; _ = await read(m, f, p, .city); XCTAssertNotNil(m.target)
        _ = await read(m, f, p); XCTAssertNil(m.target); XCTAssertEqual(m.phase, .ready)
    }
    func testExistingEditorActuallyAppliesClubAndModeSeedWithoutSubmit() async throws {
        let f = LaunchFixture(), target = try ClubProjectLaunchTarget(context: f.context, product: .freeExplore)
        let s = try ProjectEditSession(accountID: 701, epoch: 1, storageNamespace: "synthetic")
        let coordinator = ProjectEditCoordinator(initial: .init(draft: .init(product: .freeExplore)), service: ProjectEditDisabledService(), store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        let model = ProjectEditModel(coordinator: coordinator, seed: target.seed); await model.load()
        XCTAssertEqual(model.draft, target.seed); XCTAssertNil(model.incomingSeed); XCTAssertNil(coordinator.pending); XCTAssertFalse(coordinator.canSubmit)
        model.leave()
    }
    func testExistingLocalRestoreRemainsPendingAndUnchanged() async throws {
        let f = LaunchFixture(), target = try ClubProjectLaunchTarget(context: f.context, product: .city)
        let s = try ProjectEditSession(accountID: 701, epoch: 1, storageNamespace: "synthetic"), storage = ProjectEditMemoryStorage(), identity = try ProjectEditDraftIdentity()
        let store = ProjectEditLocalStore(storage: storage); var old = ProjectEditDraft(product: .city); old.name = "Existing local draft"; old.clubID = 99
        try store.save(old, session: s, identity: identity); let before = storage.data
        let coordinator = ProjectEditCoordinator(initial: .init(draft: .init(product: .city)), service: ProjectEditDisabledService(), store: store, currentSession: { s })
        let model = ProjectEditModel(coordinator: coordinator, seed: target.seed); await model.load()
        XCTAssertTrue(model.hasRestore); XCTAssertNotNil(model.incomingSeed); XCTAssertFalse(model.fullEdit)
        XCTAssertEqual(storage.data, before); model.leave(); XCTAssertEqual(storage.data, before)
    }
    func testEditorPresentationRetiresNamespaceAndSessionChanges() throws {
        let f = LaunchFixture(), target = try ClubProjectLaunchTarget(context: f.context, product: .city)
        var s: ProjectEditSession? = try .init(accountID: 701, epoch: 1, storageNamespace: "one")
        let coordinator = ProjectEditCoordinator(initial: .init(draft: .init()), service: ProjectEditDisabledService(), store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        let presentation = try XCTUnwrap(ClubProjectEditorPresentation(target: target, coordinator: coordinator)); XCTAssertTrue(presentation.hasCurrentSession)
        s = try .init(accountID: 701, epoch: 1, storageNamespace: "two"); XCTAssertFalse(presentation.hasCurrentSession)
        s = nil; XCTAssertFalse(presentation.hasCurrentSession)
    }
}
@MainActor private final class LaunchReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var club = LaunchReader.record()
    var reads = 0
    var failure = false
    var held = false
    var pending: [CheckedContinuation<ClubRecord, Error>] = []
    var entered: (() -> Void)?
    static func record(id: Int = 81, owner: Bool = true, admin: Bool = false) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner),\"viewerIsAdmin\":\(admin)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1; XCTAssertEqual(id, 81)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw CoopFlowFailure.unavailable }; return club
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class LaunchFixture {
    let reader = LaunchReader()
    var editorID = "session:1:config:1"
    var context: ClubProjectLaunchContext { .init(club: reader.club, reader: reader, editorContextID: editorID) }
}
