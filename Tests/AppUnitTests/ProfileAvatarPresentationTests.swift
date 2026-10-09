import XCTest
import UIKit
@testable import Questify

@MainActor private final class AvatarProfileFixture: ProfileAvatarEditServing {
    var avatarSavingAvailable = true
    var reads = 0
    var writes = 0
    var failRead = false
    var snapshot: ProfileEditSnapshot
    init() throws {
        snapshot = try JSONDecoder().decode(ProfileEditSnapshot.self, from: Data(#"{"id":41,"nickname":"Name","introduction":"intro","avatar":" raw old ","wechat":" raw contact ","casePics":"a;;b;","tagIds":"9,2"}"#.utf8))
    }
    func read(token: String) async throws -> ProfileEditSnapshot { reads += 1; if failRead { throw APIError.httpStatus(503) }; return snapshot }
    func save(_ payload: ProfileEditPayload, token: String) async throws { writes += 1; throw ProfileEditWriteError.outcomeUnknown }
    func saveAvatar(_ payload: ProfileEditPayload, token: String, isCurrent: @escaping @MainActor () -> Bool) async throws {
        guard isCurrent() else { throw ProfileEditWriteError.notSent }; writes += 1; throw ProfileEditWriteError.outcomeUnknown
    }
}
@MainActor private final class AvatarPresentationTransport: ProfileAvatarDispatching {
    let isConfigured = true
    var forwards = 0
    func send(_ request: URLRequest, authorization: ProfileAvatarDispatchAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request) { forwards += 1 }
        return (Data(#"{"code":200,"url":"https://avatar.invalid/staged.jpg"}"#.utf8), 200)
    }
}
@MainActor private final class AvatarPresentationFixture {
    let service = try! AvatarProfileFixture()
    var session = try! ProfileEditSession(accountID: 41, epoch: 1, token: "fixture-token", viewerRevision: 1)
    let transport = AvatarPresentationTransport()
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://profile.invalid/")!)
    let approval = try! ProfileAvatarApproval(baseURL: URL(string: "https://profile.invalid/")!, namespace: "fixture", accountID: 41, approvedOrigins: ["https://avatar.invalid"], nativePicker: true)
    var storage: [String: Data] = [:]
    lazy var coordinator = ProfileEditCoordinator(service: service, currentSession: { [unowned self] in session })
    lazy var model = ProfileEditModel(coordinator: coordinator)
    lazy var source = ProfileAvatarUploadClient(configuration: configuration, approval: approval, transport: transport,
        credentials: { [unowned self] in try? .init(session: session, namespace: "fixture", token: "fixture-token") },
        currentApproval: { [unowned self] in approval })
    lazy var journal = StoredProfileAvatarJournal(read: { [unowned self] in storage[$0] }, write: { [unowned self] in storage[$1] = $0 })
    func stage() async throws -> ProfileAvatarReplacement {
        await model.resetAndLoad()
        let target = try XCTUnwrap(model.avatarTarget(source: source))
        let flow = ProfileAvatarFlow(target: target, source: source, journal: journal,
            currentSnapshot: { [unowned self] in coordinator.snapshot }, currentDraft: { [unowned self] in model.draft },
            currentRevision: { [unowned self] in model.avatarDraftRevision }, ownerCurrent: { [unowned self] in model.ownsAvatarScope(target.scope) },
            apply: { [unowned self] in model.stageAvatar($0, preview: nil) })
        flow.prepare(try .init(jpeg: Data([255, 216, 255, 1]), width: 2, height: 2))
        await flow.confirm(try XCTUnwrap(flow.review)); flow.stage()
        XCTAssertEqual(flow.state, .staged); return try XCTUnwrap(model.draft.avatarReplacement)
    }
}
@MainActor final class ProfileAvatarPresentationTests: XCTestCase {
    func testDefaultOrdinaryServiceHasNoAvatarCapability() async throws {
        let fixture = AvatarPresentationFixture(); fixture.service.avatarSavingAvailable = false
        await fixture.model.resetAndLoad()
        XCTAssertNil(fixture.model.avatarTarget(source: fixture.source)); XCTAssertEqual(fixture.transport.forwards, 0)
    }
    func testStagedAvatarAloneMakesReloadAskWithoutReading() async throws {
        let fixture = AvatarPresentationFixture(); let replacement = try await fixture.stage(); let count = fixture.service.reads
        await fixture.model.requestReload()
        XCTAssertNotNil(fixture.model.reloadConfirmation); XCTAssertEqual(fixture.service.reads, count)
        fixture.model.cancelReload(); XCTAssertEqual(fixture.model.draft.avatarReplacement, replacement)
        XCTAssertEqual(fixture.service.writes, 0)
    }
    func testFailedConfirmedReloadPreservesStagedAvatarAndTypedBytes() async throws {
        let fixture = AvatarPresentationFixture(); let replacement = try await fixture.stage()
        fixture.model.draft.name = " raw \u{0065}\u{0301} "; let before = fixture.model.draft
        await fixture.model.requestReload(); let dialog = try XCTUnwrap(fixture.model.reloadConfirmation)
        fixture.service.failRead = true; let task = try XCTUnwrap(fixture.model.confirmReload(dialog)); await task.value
        XCTAssertEqual(fixture.model.draft.avatarReplacement, replacement)
        XCTAssertEqual(Data(fixture.model.draft.name.utf8), Data(before.name.utf8)); XCTAssertEqual(fixture.service.writes, 0)
    }
    func testRetiredAvatarOwnerCannotSaveAfterBackgroundReturnABA() async throws {
        let fixture = AvatarPresentationFixture(); _ = try await fixture.stage()
        fixture.model.retireAvatar(); fixture.model.activateAvatar(); await fixture.model.prepare()
        XCTAssertNil(fixture.model.confirmation); XCTAssertEqual(fixture.service.writes, 0)
        XCTAssertEqual(fixture.coordinator.messageKey, "profile.avatar.changed")
    }
    func testOwnerTeardownCallsRetirementAndRevokesExactScope() async throws {
        let fixture = AvatarPresentationFixture(); let replacement = try await fixture.stage(); var retired = 0
        fixture.model.observeAvatarRetirement { retired += 1 }
        let anchor = ProfileAvatarOwnerAnchor.Coordinator(fixture.model)
        ProfileAvatarOwnerAnchor.dismantleUIViewController(UIViewController(), coordinator: anchor)
        XCTAssertEqual(retired, 1); XCTAssertFalse(fixture.model.ownsAvatarScope(replacement.receipt.target.scope))
    }
    func testRawDraftABAAfterReviewCannotDispatchStagedAvatar() async throws {
        let fixture = AvatarPresentationFixture(); _ = try await fixture.stage(); await fixture.model.prepare()
        let review = try XCTUnwrap(fixture.model.confirmation), original = fixture.model.draft
        fixture.model.draft.name += "x"; fixture.model.draft = original
        await fixture.model.save(review); XCTAssertEqual(fixture.service.writes, 0)
        XCTAssertFalse(fixture.coordinator.isLocked)
    }
    func testDiscardTargetsExactStagedImageAndPreservesOtherFields() async throws {
        let fixture = AvatarPresentationFixture(); let replacement = try await fixture.stage()
        fixture.model.draft.name = " typed "; fixture.model.draft.routePreferenceIDs = []
        fixture.model.discardAvatar(id: UUID()); XCTAssertNotNil(fixture.model.draft.avatarReplacement)
        fixture.model.discardAvatar(id: replacement.id)
        XCTAssertNil(fixture.model.draft.avatarReplacement); XCTAssertEqual(fixture.model.draft.name, " typed ")
        XCTAssertEqual(fixture.model.draft.routePreferenceIDs, []); XCTAssertEqual(fixture.service.writes, 0)
    }
    func testChangedAccountCannotAdoptStagedImage() async throws {
        let fixture = AvatarPresentationFixture(); let replacement = try await fixture.stage()
        fixture.session = try .init(accountID: 42, epoch: 2, token: "fixture-token", viewerRevision: 2)
        XCTAssertFalse(fixture.model.ownsAvatarScope(replacement.receipt.target.scope))
        await fixture.model.prepare(); XCTAssertNil(fixture.model.draft.avatarReplacement); XCTAssertEqual(fixture.service.writes, 0)
    }
}
