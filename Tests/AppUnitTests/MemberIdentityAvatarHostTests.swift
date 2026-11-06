import Foundation
import UIKit
import XCTest
@testable import Questify

@MainActor private final class CardHostMember: MemberHomeReading {
    var scope = UUID(), isSignedIn = true, isConfigured = true, roleInfoAvailable = false
    func identity() async throws -> MemberIdentitySnapshot { throw APIError.notConfigured }
    func roleInfo() async throws -> MemberRoleInfo { throw APIError.notConfigured }
}
@MainActor private final class CardHostBytes: MemberIdentityAvatarDispatching {
    var requests: [URLRequest] = [], cancelled = false, pause = false
    var pending: CheckedContinuation<Data, Error>?
    var after: (() -> Void)?
    func send(_ request: URLRequest, authorization: MemberIdentityAvatarAuthorization) async throws -> Data {
        try authorization.forward(request, cancel: { self.cancelled = true }) { requests.append(request) }
        if pause { pause = false; return try await withCheckedThrowingContinuation { pending = $0 } }
        after?(); return Data([1, 2, 3])
    }
    func finish() { let value = pending; pending = nil; value?.resume(returning: Data([1, 2, 3])) }
}
@MainActor private final class CardHostSurface: MemberIdentityAvatarSurface {
    var displays = 0, clears = 0, visible = false
    func display(_ image: UIImage) { displays += 1; visible = true }
    func clear() { clears += 1; visible = false }
}
@MainActor private final class CardHostFixture {
    let member = CardHostMember(), bytes = CardHostBytes(), owner = MemberIdentityCardReadOwner()
    let selector = MemberIdentityAvatarSourceSelection(), lifetime = MemberIdentityAvatarLifetime(), notes = NotificationCenter()
    let context: RuntimeDependencyContext
    let approval: MemberIdentityAvatarApproval
    var decodes = 0, made = 0, revokeWhileDecoding = false
    init(install: Bool = true) throws {
        context = .init(market: .china, baseURL: URL(string: "https://card-api.example.test/native")!, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "card", token: "synthetic-card", role: "player"))
        approval = try .init(context: context, viewerRevision: 3, approvedOrigins: ["https://card-images.example.test"], expiresAt: Date().addingTimeInterval(600))
        if install { try selector.replace(with: approval) }
        owner.appear(active: true); let run = try XCTUnwrap(owner.begin(scope: member.scope))
        owner.publish(try Self.snapshot(), run: run, scope: member.scope)
    }
    static func snapshot(raw: String = "https://card-images.example.test/a.png?Signature=a%2Bb") throws -> MemberIdentitySnapshot {
        try JSONDecoder().decode(MemberIdentitySnapshot.self, from: JSONSerialization.data(withJSONObject: ["id": 7, "avatar": raw, "nickname": "Synthetic"]))
    }
    func makeReader() -> MemberIdentityAvatarReader? {
        guard let selected = selector.approval(for: context) else { return nil }; made += 1
        let reader = MemberIdentityAvatarReader(approval: selected, currentContext: { [unowned self] in context }, currentViewer: { 3 }, selected: { [unowned self] in selector.approval(for: context) }, member: member, transport: bytes)
        lifetime.register(reader); return reader
    }
    func model() throws -> MemberIdentityAvatarModel {
        .init(observation: try XCTUnwrap(owner.observation), owner: owner,
              access: .init(sourceRevision: { [unowned self] in selector.approval(for: context)?.revision }, makeReader: { [unowned self] in makeReader() }), notifications: notes,
              decode: { [unowned self] _ in decodes += 1; if revokeWhileDecoding { approval.revoke() }; return UIImage() })
    }
    func cleanup() { owner.disappear(); selector.revoke(); bytes.finish() }
}
@MainActor private final class CardHostVault: AppTokenStorage {
    var token: String? = "synthetic-card"
    func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
}
@MainActor private final class CardHostLogin: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor final class MemberIdentityAvatarHostTests: XCTestCase {
    private func fixture(install: Bool = true) throws -> CardHostFixture {
        let f = try CardHostFixture(install: install); addTeardownBlock { @MainActor in f.cleanup() }; return f
    }
    func testNoSourceMeansNoReaderDownloadDecodeOrPixels() async throws {
        let f = try fixture(install: false), model = try f.model(), surface = CardHostSurface(); model.attach(surface)
        await model.appear(active: true)?.value
        XCTAssertEqual(f.made, 0); XCTAssertEqual(f.decodes, 0); XCTAssertTrue(f.bytes.requests.isEmpty); XCTAssertFalse(surface.visible)
    }
    func testGrantedCurrentSelfSourceDisplaysOnlySanitizedMemoryAdapterOutput() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface)
        await model.appear(active: true)?.value
        XCTAssertEqual(f.bytes.requests.count, 1); XCTAssertEqual(f.decodes, 1); XCTAssertEqual(model.phase, .ready); XCTAssertTrue(surface.visible)
        model.disappear(); XCTAssertFalse(surface.visible)
    }
    func testDirectApprovalRevocationClearsSurfaceSynchronously() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
        f.approval.revoke(); XCTAssertFalse(surface.visible); XCTAssertEqual(model.phase, .idle)
    }
    func testSelectorWithdrawalClearsWithoutAwaitingSwiftUI() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
        f.selector.revoke(); XCTAssertFalse(surface.visible); XCTAssertFalse(model.available)
    }
    func testHostLifetimeClearsSurfaceWithoutWaitingForAnotherRead() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
        f.lifetime.retireAll(); XCTAssertFalse(surface.visible); XCTAssertEqual(model.phase, .idle)
    }
    func testNewMetadataRequestClearsOldPhotoBeforeResponse() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
        _ = f.owner.begin(scope: f.member.scope); XCTAssertFalse(surface.visible); XCTAssertNil(f.owner.observation)
    }
    func testLatestRunWinsAndOldCancellationCannotClearNewObservation() throws {
        let f = try fixture(), first = try XCTUnwrap(f.owner.begin(scope: f.member.scope)), second = try XCTUnwrap(f.owner.begin(scope: f.member.scope))
        f.owner.publish(try CardHostFixture.snapshot(raw: "https://card-images.example.test/new"), run: second, scope: f.member.scope)
        let latest = f.owner.observation
        f.owner.publish(try CardHostFixture.snapshot(raw: "https://card-images.example.test/old"), run: first, scope: f.member.scope); f.owner.invalidate(first)
        XCTAssertEqual(f.owner.observation, latest); XCTAssertTrue(f.owner.accepts(second, scope: f.member.scope)); XCTAssertFalse(f.owner.accepts(first, scope: f.member.scope))
    }
    func testUnmountedOrBackgroundOwnerRejectsQueuedReadStart() throws {
        let f = try fixture(); f.owner.disappear(); XCTAssertNil(f.owner.begin(scope: f.member.scope))
        f.owner.appear(active: false); XCTAssertNil(f.owner.begin(scope: f.member.scope))
        f.owner.scene(active: true); XCTAssertNotNil(f.owner.begin(scope: f.member.scope))
    }
    func testScopeChangeCannotPublishOldMetadata() throws {
        let f = try fixture(), run = try XCTUnwrap(f.owner.begin(scope: f.member.scope)); f.member.scope = UUID()
        f.owner.publish(try CardHostFixture.snapshot(), run: run, scope: f.member.scope); XCTAssertNil(f.owner.observation)
    }
    func testOldMountCannotAdoptReplacementIssuance() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
        let next = try MemberIdentityAvatarApproval(context: f.context, viewerRevision: 3, approvedOrigins: ["https://card-images.example.test"], expiresAt: Date().addingTimeInterval(600))
        try f.selector.replace(with: next); XCTAssertFalse(surface.visible); XCTAssertFalse(model.available)
        XCTAssertNil(model.start()); XCTAssertEqual(f.bytes.requests.count, 1)
    }
    func testConsumedIssuanceCannotBeReinstalled() throws {
        let f = try fixture(); f.selector.revoke(); XCTAssertThrowsError(try f.selector.replace(with: f.approval)); XCTAssertNil(f.selector.approval(for: f.context))
    }
    func testQueuedDownloadRetiredBeforeAdmissionMakesNoRequest() async throws {
        let f = try fixture(), model = try f.model(), work = model.appear(active: true); model.disappear(); await work?.value
        XCTAssertTrue(f.bytes.requests.isEmpty); XCTAssertEqual(f.decodes, 0)
    }
    func testLateBytesAfterOwnerWithdrawalNeverDecodeOrRepaint() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); f.bytes.pause = true
        let work = model.appear(active: true)
        for _ in 0..<100 { if f.bytes.pending != nil { break }; await Task.yield() }
        guard f.bytes.pending != nil else { model.disappear(); await work?.value; XCTFail("Synthetic admission failed"); return }
        f.owner.invalidate(); XCTAssertTrue(f.bytes.cancelled); f.bytes.finish(); await work?.value
        XCTAssertEqual(f.decodes, 0); XCTAssertFalse(surface.visible)
    }
    func testRevocationDuringDecodeCannotPublishImage() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); f.revokeWhileDecoding = true
        await model.appear(active: true)?.value; XCTAssertEqual(f.decodes, 1); XCTAssertFalse(surface.visible); XCTAssertEqual(surface.displays, 0)
    }
    func testMainQueueBackgroundAndClockSignalsClearSynchronously() async throws {
        for note in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.significantTimeChangeNotification] {
            let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
            f.notes.post(name: note, object: nil); XCTAssertFalse(surface.visible); XCTAssertEqual(model.phase, .idle)
        }
    }
    func testSurfaceReplacementClearsOldAndLateDetachKeepsSuccessor() async throws {
        let f = try fixture(), model = try f.model(), old = CardHostSurface(), next = CardHostSurface()
        model.attach(old); await model.appear(active: true)?.value; model.attach(next)
        XCTAssertFalse(old.visible); XCTAssertTrue(next.visible); model.detach(old); XCTAssertTrue(next.visible)
        model.disappear(); XCTAssertFalse(next.visible)
    }
    func testRepeatedAppearAndStartDoNotDuplicateInflightRead() async throws {
        let f = try fixture(), model = try f.model(), work = model.appear(active: true)
        XCTAssertNil(model.start()); XCTAssertNil(model.appear(active: true)); await work?.value; XCTAssertEqual(f.bytes.requests.count, 1)
    }
    func testDisappearStopsAndCannotBeResurrectedBySceneActiveAlone() async throws {
        let f = try fixture(), model = try f.model(), surface = CardHostSurface(); model.attach(surface); await model.appear(active: true)?.value
        model.disappear(); model.scene(active: true); XCTAssertFalse(model.available); XCTAssertFalse(surface.visible); XCTAssertEqual(f.bytes.requests.count, 1)
    }
    func testActualHostDefaultsClosedAndRoleRefreshRetiresExactReader() async throws {
        let suite = "card-avatar-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = CardHostVault(), login = CardHostLogin()
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://card-api.example.test/native", approvedBaseURLs: [.china: ["https://card-api.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.card." + UUID().uuidString.lowercased(), realm: "synthetic")
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { login })
        let session = root.makeSession(); await session.bootstrap(); login.requests = []
        XCTAssertNil(session.memberIdentityAvatarAccess.sourceRevision()); XCTAssertNil(session.makeMemberIdentityAvatarReader())
        let identity = session.profileSavedMediaIdentity(.avatar)
        let grant = try MemberIdentityAvatarApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision, approvedOrigins: ["https://card-images.example.test"], expiresAt: Date().addingTimeInterval(600))
        try root.memberIdentityAvatarSelection.replace(with: grant)
        defer { root.memberIdentityAvatarSelection.revoke() }
        let reader = try XCTUnwrap(session.makeMemberIdentityAvatarReader(transport: CardHostBytes())); var clears = 0; reader.onRetire = { clears += 1 }
        XCTAssertTrue(reader.isConfigured); XCTAssertTrue(login.requests.isEmpty)
        login.role = "merchant"; await session.refreshOwnAccount(); XCTAssertEqual(clears, 1); XCTAssertFalse(reader.isConfigured)
        XCTAssertEqual(vault.token, "synthetic-card")
    }
    func testEditorPurposeGrantDoesNotEnableIdentityCardHost() async throws {
        let f = try fixture(install: false)
        let editor = try ProfileSavedMediaReadApproval(context: f.context, viewerRevision: 3, kind: .avatar, approvedOrigins: ["https://card-images.example.test"], expiresAt: Date().addingTimeInterval(600))
        let selector = ProfileSavedMediaSourceSelection(); try selector.replace(.avatar, with: editor); defer { selector.revoke(.avatar) }
        let model = try f.model(); await model.appear(active: true)?.value
        XCTAssertTrue(f.bytes.requests.isEmpty); XCTAssertEqual(f.decodes, 0)
    }
}
