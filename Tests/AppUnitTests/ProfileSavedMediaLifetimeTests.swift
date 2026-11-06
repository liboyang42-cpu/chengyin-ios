import Foundation
import XCTest
@testable import Questify
@MainActor private final class SavedMediaHostVault: AppTokenStorage {
    var token: String? = "synthetic-saved-host"
    func read() throws -> String? { token }
    func write(_ value: String) throws { token = value }
    func clear() throws { token = nil }
}
@MainActor private final class SavedMediaHostLogin: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ r: URLRequest) async throws -> (Data, Int) {
        requests.append(r); return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor private final class SavedMediaHostWire: ProfileSavedMediaDispatching {
    var requests: [URLRequest] = []
    func send(_ r: URLRequest, authorization: ProfileSavedMediaReadAuthorization) async throws -> Data {
        try authorization.forward(r, cancel: {}) { requests.append(r) }; return Data([1, 2, 3])
    }
}
@MainActor private final class SavedMediaHostFixture {
    let root: AppCompositionRoot, defaults: UserDefaults, suite = "saved-media-host-" + UUID().uuidString
    let vault = SavedMediaHostVault(), wire = SavedMediaHostLogin(), read = SavedMediaHostWire()
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let d = try ReviewedAppDeployment(market: .china, baseURL: "https://saved-host.example.test/native",
            approvedBaseURLs: [.china: ["https://saved-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.saved." + UUID().uuidString.lowercased(), realm: "synthetic")
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(d), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let s = root.makeSession(); await s.bootstrap(); wire.requests = []; return s }
    func grant(_ s: AppSession, kind: ProfileCurrentMediaKind = .caseImage, viewer: UInt64? = nil) throws -> ProfileSavedMediaReadApproval {
        let identity = s.profileSavedMediaIdentity(kind)
        let a = try ProfileSavedMediaReadApproval(context: XCTUnwrap(identity.context), viewerRevision: viewer ?? identity.viewerRevision,
            kind: kind, approvedOrigins: ["https://saved-images.example.test"], expiresAt: Date().addingTimeInterval(600))
        try root.profileSavedMediaSelection.replace(kind, with: a); return a
    }
    func cleanup() { ProfileCurrentMediaKind.allCases.forEach { root.profileSavedMediaSelection.revoke($0) }; defaults.removePersistentDomain(forName: suite) }
}
@MainActor private final class SavedMediaHostProfile: ProfileEditServing {
    var writes = 0
    func read(token: String) async throws -> ProfileEditSnapshot {
        try JSONDecoder().decode(ProfileEditSnapshot.self, from: Data(#"{"id":7,"nickname":"原名字","introduction":"Saved","avatar":"https://saved-images.example.test/a.jpg?sig=a%2Bb","wechat":"https://saved-images.example.test/qr.jpg","casePics":"https://saved-images.example.test/work.jpg","tagIds":""}"#.utf8))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws { writes += 1; throw ProfileEditWriteError.outcomeUnknown }
}
@MainActor final class ProfileSavedMediaLifetimeTests: XCTestCase {
    private func host() throws -> SavedMediaHostFixture {
        let f = try SavedMediaHostFixture(); addTeardownBlock { @MainActor in f.cleanup() }; return f
    }
    func testDefaultCompositionHasNoPurposeReaderOrRequest() async throws {
        let f = try host(), s = await f.boot()
        XCTAssertNil(s.profileSavedMediaReaders)
        for kind in ProfileCurrentMediaKind.allCases { XCTAssertNil(s.makeProfileSavedMediaReader(kind, transport: f.read)) }
        XCTAssertTrue(f.read.requests.isEmpty); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testWorkGrantDoesNotEnableAvatarOrQR() async throws {
        let f = try host(), s = await f.boot(); _ = try f.grant(s)
        let values = try XCTUnwrap(s.profileSavedMediaReaders)
        XCTAssertNotNil(values.work); XCTAssertNil(values.avatar); XCTAssertNil(values.contactQR)
    }
    func testIndependentQRRevocationDoesNotRetireLiveWorkReader() async throws {
        let f = try host(), s = await f.boot(); _ = try f.grant(s); _ = try f.grant(s, kind: .contactQR)
        let before = try XCTUnwrap(s.profileSavedMediaReaders), work = try XCTUnwrap(before.work), qr = try XCTUnwrap(before.contactQR)
        f.root.profileSavedMediaSelection.revoke(.contactQR)
        let after = try XCTUnwrap(s.profileSavedMediaReaders)
        XCTAssertTrue(after.work === work); XCTAssertTrue(work.isConfigured); XCTAssertFalse(qr.isConfigured); XCTAssertNil(after.contactQR)
    }
    func testReplacementAndUsedLeaseFailClosedWithoutAccountMutation() async throws {
        let f = try host(), s = await f.boot(), old = try f.grant(s), reader = try XCTUnwrap(s.profileSavedMediaReaders?.work)
        _ = try f.grant(s); let replacement = try XCTUnwrap(s.profileSavedMediaReaders?.work)
        XCTAssertFalse(reader.isConfigured); XCTAssertFalse(reader === replacement); XCTAssertTrue(replacement.isConfigured)
        XCTAssertThrowsError(try f.root.profileSavedMediaSelection.replace(.caseImage, with: old))
        XCTAssertTrue(replacement.isConfigured); XCTAssertEqual(s.account?.id, 7); XCTAssertEqual(f.vault.token, "synthetic-saved-host")
    }
    func testPurposeMismatchDoesNotReplaceCurrentSelection() async throws {
        let f = try host(), s = await f.boot(), work = try f.grant(s)
        XCTAssertThrowsError(try f.root.profileSavedMediaSelection.replace(.contactQR, with: work))
        XCTAssertNotNil(s.profileSavedMediaReaders?.work); XCTAssertNil(s.profileSavedMediaReaders?.contactQR)
    }
    func testWrongViewerAndChangedRoleCannotReuseReader() async throws {
        let f = try host(), s = await f.boot()
        _ = try f.grant(s, viewer: s.profileSavedMediaIdentity(.caseImage).viewerRevision &+ 1)
        XCTAssertNil(s.makeProfileSavedMediaReader(.caseImage, transport: f.read))
        _ = try f.grant(s); let reader = try XCTUnwrap(s.profileSavedMediaReaders?.work)
        f.wire.role = "merchant"; await s.refreshOwnAccount()
        XCTAssertFalse(reader.isConfigured); XCTAssertNil(s.profileSavedMediaReaders)
    }
    func testOnlyMockAnonymousMediaTransportReceivesCurrentSnapshotURL() async throws {
        let f = try host(), s = await f.boot(); _ = try f.grant(s)
        let reader = try XCTUnwrap(s.makeProfileSavedMediaReader(.caseImage, transport: f.read))
        let snapshot = try await SavedMediaHostProfile().read(token: "synthetic"), identity = s.profileSavedMediaIdentity(.caseImage)
        let key = try XCTUnwrap(reader.key(snapshot: snapshot, kind: .caseImage, originalIndex: 0,
            identity: .init(accountID: 7, epoch: try XCTUnwrap(identity.context).session.epoch), viewerRevision: identity.viewerRevision))
        _ = try await reader.image(snapshot: snapshot, key: key, currentSnapshot: { snapshot })
        XCTAssertEqual(f.read.requests.count, 1); XCTAssertNil(f.read.requests[0].value(forHTTPHeaderField: "Authorization")); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testVisibilityRequiresActualMountAndNeverRevivesDismissedOwner() {
        let visibility = ProfileSavedMediaVisibility(); visibility.scene(active: true)
        XCTAssertFalse(visibility.active); visibility.appear(active: true); let old = visibility.lifetime
        XCTAssertTrue(visibility.matches(old)); visibility.disappear(); visibility.scene(active: true)
        XCTAssertFalse(visibility.active); XCTAssertFalse(visibility.matches(old))
    }
    func testBackgroundInvalidatesPendingDecodeAndNewAppearanceHasNewLifetime() {
        let visibility = ProfileSavedMediaVisibility(); visibility.appear(active: true); let old = visibility.lifetime
        visibility.scene(active: false); XCTAssertFalse(visibility.matches(old))
        visibility.scene(active: true); XCTAssertTrue(visibility.active); XCTAssertFalse(visibility.matches(old))
        let current = visibility.lifetime; visibility.disappear(); visibility.appear(active: true)
        XCTAssertFalse(visibility.matches(current)); XCTAssertTrue(visibility.active)
    }
    func testCancelledOldEditorCannotReadNewEditorsSnapshot() async throws {
        let service = SavedMediaHostProfile(), session = try ProfileEditSession(accountID: 7, epoch: 1, token: "synthetic-editor", viewerRevision: 3)
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        await model.resetAndLoad(); model.beginTextEdit(.casePictures); let old = try XCTUnwrap(model.textEdit)
        XCTAssertNotNil(model.currentMediaReadSnapshot(for: old)); model.cancelTextEdit(old)
        model.beginTextEdit(.contactQR); let current = try XCTUnwrap(model.textEdit); model.cancelTextEdit(old)
        XCTAssertNil(model.currentMediaReadSnapshot(for: old)); XCTAssertNotNil(model.currentMediaReadSnapshot(for: current)); XCTAssertEqual(service.writes, 0)
    }
    func testBackgroundAndOwnerChangeDenySnapshotWithoutWriting() async throws {
        let service = SavedMediaHostProfile()
        var session: ProfileEditSession? = try .init(accountID: 7, epoch: 1, token: "synthetic-editor", viewerRevision: 3)
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        await model.resetAndLoad(); XCTAssertNotNil(model.savedAvatarReadSnapshot)
        model.beginTextEdit(.contactQR); let edit = try XCTUnwrap(model.textEdit)
        model.suspendForBackground(); XCTAssertNil(model.currentMediaReadSnapshot(for: edit)); XCTAssertNil(model.savedAvatarReadSnapshot)
        session = try .init(accountID: 8, epoch: 2, token: "synthetic-other", viewerRevision: 4)
        model.activateAvatar(); XCTAssertNil(model.savedAvatarReadSnapshot); XCTAssertEqual(service.writes, 0)
    }
    func testReadOnlySnapshotDoesNotStageRemovalOrResolveUnknownSave() async throws {
        let service = SavedMediaHostProfile(), session = try ProfileEditSession(accountID: 7, epoch: 1, token: "synthetic-editor", viewerRevision: 3)
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        await model.resetAndLoad(); model.beginTextEdit(.casePictures); let edit = try XCTUnwrap(model.textEdit), before = model.draft
        _ = model.currentMediaReadSnapshot(for: edit); XCTAssertEqual(model.draft, before); XCTAssertEqual(service.writes, 0)
        model.cancelTextEdit(edit); model.draft.introduction = "Changed"; await model.prepare()
        let confirmation = try XCTUnwrap(model.confirmation); _ = await model.save(confirmation)
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertNil(model.savedAvatarReadSnapshot)
        XCTAssertNil(model.currentMediaReadSnapshot(for: edit)); XCTAssertEqual(service.writes, 1)
    }
    func testExpirationRetiresOnlyMatchingPurposeAndKeepsTokens() async throws {
        let f = try host(), session = await f.boot(); _ = try f.grant(session)
        let identity = session.profileSavedMediaIdentity(.contactQR)
        let short = try ProfileSavedMediaReadApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision,
            kind: .contactQR, approvedOrigins: ["https://saved-images.example.test"], expiresAt: Date().addingTimeInterval(0.5))
        try f.root.profileSavedMediaSelection.replace(.contactQR, with: short)
        let work = try XCTUnwrap(session.profileSavedMediaReaders?.work)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(session.profileSavedMediaReaders?.contactQR); XCTAssertTrue(work === session.profileSavedMediaReaders?.work)
        XCTAssertTrue(work.isConfigured); XCTAssertEqual(f.vault.token, "synthetic-saved-host")
    }
    func testNormalNilSourceLeavesQRAndWorkEditingAvailableWithoutWrites() async throws {
        let service = SavedMediaHostProfile(), session = try ProfileEditSession(accountID: 7, epoch: 1, token: "synthetic-editor", viewerRevision: 3)
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        await model.resetAndLoad(); model.beginTextEdit(.contactQR); let qr = try XCTUnwrap(model.textEdit)
        XCTAssertNotNil(model.currentMediaReadSnapshot(for: qr)); model.cancelTextEdit(qr)
        model.beginTextEdit(.casePictures); XCTAssertEqual(model.textEdit?.field, .casePictures)
        XCTAssertEqual(service.writes, 0); XCTAssertFalse(model.draft.removesContactQR); XCTAssertFalse(model.draft.removesCasePictures)
    }
    func testGalleryLayoutRetainsAccessibleControls() {
        XCTAssertEqual(ProfileCurrentMediaPreviewLayout.minimumAction, 44)
        XCTAssertTrue(ProfileCurrentMediaPreviewLayout.expandsThumbnails(for: .accessibility3))
        XCTAssertTrue(ProfileCurrentMediaPreviewLayout.scrollsGallery(for: .large, verticalSizeClass: .compact))
        XCTAssertFalse(ProfileCurrentMediaPreviewLayout.scrollsGallery(for: .large, verticalSizeClass: .regular))
    }
}
