import Foundation
import Observation
import UIKit
import XCTest
@testable import Questify
@MainActor private final class AudioPreviewVault: AppTokenStorage {
    var token: String? = "synthetic-audio-preview"
    func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
}
@MainActor private final class AudioPreviewLogin: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor private final class AudioPreviewListBox { var approval: OwnMediaReadApproval? }
@MainActor @Observable private final class AudioPreviewRowBox { var row: OwnMediaAsset? }
@MainActor private final class AudioPreviewMetadata: OwnMediaAudioPreviewMetadataReading {
    var requests: [URLRequest] = [], status = 200, after: (() -> Void)?, wait = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var value: (Data, Int) { (Data(#"{"code":200,"data":{"authorPreviewUrl":"https://owner-audio.example.test/a.wav?Signature=a%2Bb"}}"#.utf8), status) }
    func send(_ request: URLRequest, authorization: OwnMediaAudioPreviewAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        if wait { wait = false; return try await withCheckedThrowingContinuation { pending = $0 } }; return value
    }
    func finish() { let p = pending; pending = nil; p?.resume(returning: value) }
}
@MainActor private final class AudioPreviewBytes: OwnMediaPrivateAudioReading {
    var requests: [URLRequest] = [], after: (() -> Void)?
    func audio(_ request: URLRequest, authorization: OwnMediaAudioPreviewAuthorization) async throws -> Data {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        return Data([82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69]) // Header-only mock data, never native-decoded.
    }
}
@MainActor private final class AudioPreviewMemoryDevice: OwnMediaAudioPreviewPlaying {
    var position: TimeInterval = 0, prepares = 0, plays = 0, pauses = 0, stops = 0, fail = false
    var current: (() -> Bool)?, event: ((OwnMediaAudioPreviewDeviceEvent) -> Void)?
    func prepare(_ bytes: Data, current: @escaping () -> Bool, event: @escaping (OwnMediaAudioPreviewDeviceEvent) -> Void) throws -> TimeInterval {
        prepares += 1; if fail || !current() { throw OwnMediaAudioPreviewFailure.invalidResponse }; self.current = current; self.event = event; return 30
    }
    func play() throws { guard current?() == true else { throw OwnMediaAudioPreviewFailure.stale }; plays += 1 }
    func pause() { pauses += 1 }
    func seek(_ time: TimeInterval) throws { guard current?() == true else { throw OwnMediaAudioPreviewFailure.stale }; position = time }
    func stop() { stops += 1; current = nil; event = nil }
}
@MainActor private final class AudioPreviewHost {
    let root: AppCompositionRoot, defaults: UserDefaults, suite = "owner-audio-" + UUID().uuidString, notes = NotificationCenter()
    let vault = AudioPreviewVault(), login = AudioPreviewLogin(), listBox = AudioPreviewListBox(), rowBox = AudioPreviewRowBox()
    let metadata = AudioPreviewMetadata(), bytes = AudioPreviewBytes()
    let asset = OwnMediaAsset(id: 9, reviewState: .hold, reviewReason: "Pending", mediaType: .audio)
    var devices: [AudioPreviewMemoryDevice] = [], made = 0
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let d = try ReviewedAppDeployment(market: .china, baseURL: "https://audio-api.example.test/native", approvedBaseURLs: [.china: ["https://audio-api.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.owner.audio." + UUID().uuidString.lowercased(), realm: "synthetic")
        let login = login, vault = vault, box = listBox
        root = .init(deployment: .reviewed(d), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { login })
        root.ownMediaReadApproval = { context in box.approval.flatMap { $0.matches(context) ? $0 : nil } }; rowBox.row = asset
    }
    func boot() async -> AppSession { let s = root.makeSession(); await s.bootstrap(); login.requests = []; return s }
    func listGrant(_ s: AppSession) throws {
        let c = try XCTUnwrap(s.ownMediaAudioPreviewIdentity(asset).context); listBox.approval = try .init(context: c, expiresAt: Date().addingTimeInterval(600))
    }
    func grant(_ s: AppSession, id: Int64 = 9, duration: TimeInterval = 600) throws -> OwnMediaAudioPreviewApproval {
        let identity = s.ownMediaAudioPreviewIdentity(asset)
        let value = try OwnMediaAudioPreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision,
            assetID: id, approvedOrigins: ["https://owner-audio.example.test"], expiresAt: Date().addingTimeInterval(duration))
        try root.ownMediaAudioPreviewSelection.replace(assetID: id, with: value); return value
    }
    func model(_ s: AppSession) -> OwnMediaAudioPreviewModel {
        let access = OwnMediaAudioPreviewAccess(sourceRevision: s.ownMediaAudioPreviewAccess.sourceRevision, makeReader: { [unowned self] asset in
            made += 1; return s.makeOwnMediaAudioPreviewReader(asset, metadata: metadata, audioReader: bytes)
        })
        return .init(asset: asset, access: access, currentAsset: { [unowned self] in rowBox.row }, notifications: notes,
                     makeDevice: { [unowned self] in let device = AudioPreviewMemoryDevice(); devices.append(device); return device })
    }
    func cleanup() { root.ownMediaAudioPreviewSelection.revoke(assetID: 9); root.ownMediaAudioPreviewSelection.revoke(assetID: 10); listBox.approval?.revoke(); devices.forEach { $0.stop() }; metadata.finish(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class OwnMediaAudioPreviewHostTests: XCTestCase {
    private func host() throws -> AudioPreviewHost { let f = try AudioPreviewHost(); addTeardownBlock { @MainActor in f.cleanup() }; return f }
    func testDefaultHostCannotFetchDecodeOrPlay() async throws {
        let f = try host(), s = await f.boot(); let model = f.model(s); model.appear(foreground: true)
        XCTAssertNil(s.ownMediaAudioPreviewAccess.sourceRevision(f.asset)); XCTAssertNil(model.open()); XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.devices.isEmpty)
    }
    func testListAuthorityCannotGrantAudioAndAudioCannotReplaceList() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); XCTAssertNil(s.ownMediaAudioPreviewAccess.sourceRevision(f.asset)); _ = try f.grant(s)
        XCTAssertNotNil(s.ownMediaAudioPreviewAccess.sourceRevision(f.asset)); f.listBox.approval?.revoke(); XCTAssertNil(s.makeOwnMediaAudioPreviewReader(f.asset, metadata: f.metadata, audioReader: f.bytes))
    }
    func testImageGrantCannotAuthorizeAudio() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let identity = s.ownMediaAudioPreviewIdentity(f.asset)
        let image = try OwnMediaImagePreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision, assetID: 9, approvedOrigins: ["https://owner-audio.example.test"], expiresAt: .distantFuture)
        try f.root.ownMediaImagePreviewSelection.replace(assetID: 9, with: image); XCTAssertNil(s.ownMediaAudioPreviewAccess.sourceRevision(f.asset))
        _ = try f.grant(s); f.root.ownMediaAudioPreviewSelection.revoke(assetID: 9); XCTAssertFalse(image.revoked); f.root.ownMediaImagePreviewSelection.revoke(assetID: 9)
    }
    func testAppearanceDoesNotRequestAndLoadedPreviewDoesNotAutoplay() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true)
        XCTAssertTrue(f.devices.isEmpty); XCTAssertTrue(f.metadata.requests.isEmpty); await model.open()?.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.devices.first?.prepares, 1); XCTAssertEqual(f.devices.first?.plays, 0); model.disappear()
    }
    func testExplicitPlayPauseSeekAreBoundToCurrentControls() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let id = try XCTUnwrap(model.presentation), run = model.controlRevision; model.toggle(id, operation: run); XCTAssertEqual(model.phase, .playing)
        model.seek(id, operation: run, to: 10); XCTAssertEqual(f.devices[0].position, 10); model.toggle(id, operation: run); XCTAssertEqual(model.phase, .paused); model.disappear()
    }
    func testFirstPartyTokenNeverGoesToAudioResourceOrGenericHostTransport() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertEqual(f.metadata.requests.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-audio-preview"); XCTAssertNil(f.bytes.requests.first?.value(forHTTPHeaderField: "Authorization")); XCTAssertTrue(f.login.requests.isEmpty); model.disappear()
    }
    func testSystemBackgroundSynchronouslyStopsAndNeverResumes() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let id = try XCTUnwrap(model.presentation); model.toggle(id, operation: model.controlRevision); f.notes.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0); model.setForeground(true); XCTAssertEqual(f.devices[0].plays, 1); XCTAssertEqual(f.metadata.requests.count, 1)
    }
    func testRowWillChangeStopsSynchronouslyWithoutSwiftUIRendering() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.toggle(try XCTUnwrap(model.presentation), operation: model.controlRevision); f.rowBox.row = nil
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testListWithdrawalStopsSynchronouslyWithoutWaitingForUI() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.toggle(try XCTUnwrap(model.presentation), operation: model.controlRevision); f.listBox.approval?.revoke()
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testSourceWithdrawalStopsOnlyThisAsset() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let other = try f.grant(s, id: 10); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        f.root.ownMediaAudioPreviewSelection.revoke(assetID: 9); XCTAssertNil(model.presentation); XCTAssertFalse(other.revoked); XCTAssertTrue(s.ownMediaReader.isAvailable)
    }
    func testSessionLifetimeStopsReadersAndPlayingDeviceSynchronously() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.toggle(try XCTUnwrap(model.presentation), operation: model.controlRevision); s.ownMediaAudioPreviewLifetime.retireAll()
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices.first?.stops ?? 0, 0); XCTAssertEqual(f.vault.token, "synthetic-audio-preview")
    }
    func testAuthoritativeRoleRefreshStopsOldAudio() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        f.login.role = "merchant"; await s.refreshOwnAccount(); XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testOriginalLoginGateTransitionStopsOldAudioEvenWhenLoginFails() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        await s.login(username: "synthetic", password: "synthetic") // Stub returns no login token; no real HTTP.
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testQueuedOpenCancelledBeforeAdmissionDoesNotRead() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true)
        let work = model.open(); model.disappear(); await work?.value; XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.devices.isEmpty)
    }
    func testOldCloseAndControlsCannotStopNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let old = try XCTUnwrap(model.presentation), run = model.controlRevision, binding = model.binding(old); model.close(old); await model.open()?.value
        let current = try XCTUnwrap(model.presentation); model.close(old); binding.wrappedValue = nil; model.toggle(old, operation: run); model.seek(old, operation: run, to: 4)
        XCTAssertEqual(model.presentation, current); XCTAssertEqual(f.devices.last?.plays, 0); model.close(current)
    }
    func testLateOldMetadataCannotDecodeOrPlayNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); f.metadata.wait = true
        let oldTask = model.open(); for _ in 0..<100 { if f.metadata.pending != nil { break }; await Task.yield() }
        guard f.metadata.pending != nil else { model.disappear(); await oldTask?.value; XCTFail("Synthetic admission failed"); return }
        model.close(try XCTUnwrap(model.presentation)); await model.open()?.value; f.metadata.finish(); await oldTask?.value
        XCTAssertEqual(f.devices.count, 1); XCTAssertEqual(f.devices[0].plays, 0); model.disappear()
    }
    func testEndedPlaybackNeedsExplicitReloadAndOldCallbacksCannotAffectRetry() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let id = try XCTUnwrap(model.presentation), oldEvent = f.devices[0].event, run = model.controlRevision; oldEvent?(.ended); XCTAssertEqual(model.phase, .ended)
        await model.retry(id, operation: run)?.value; oldEvent?(.failed); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.devices.last?.plays, 0); model.disappear()
    }
    func testPerAssetExpiryStopsPlaybackAndDoesNotLogOut() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let grant = try f.grant(s, duration: 0.5), other = try f.grant(s, id: 10)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value; if let id = model.presentation { model.toggle(id, operation: model.controlRevision) }
        try await Task.sleep(nanoseconds: 600_000_000); XCTAssertTrue(grant.revoked); XCTAssertFalse(other.revoked); XCTAssertNil(model.presentation)
        XCTAssertGreaterThan(f.devices.first?.stops ?? 0, 0); XCTAssertEqual(f.vault.token, "synthetic-audio-preview")
    }
    func testMetadataDenialDoesNotRevokeListOrAccount() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let grant = try f.grant(s); f.metadata.status = 403
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertTrue(grant.revoked); XCTAssertTrue(s.ownMediaReader.isAvailable); XCTAssertEqual(s.account?.id, 7); XCTAssertTrue(f.devices.isEmpty)
    }
    func testSignificantTimeChangeSynchronouslyDropsPrivateAudio() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.toggle(try XCTUnwrap(model.presentation), operation: model.controlRevision); f.notes.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices.first?.stops ?? 0, 0); XCTAssertEqual(f.metadata.requests.count, 1)
    }

}
